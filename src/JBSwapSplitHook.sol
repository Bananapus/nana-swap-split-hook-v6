// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBMetadataResolver} from "@bananapus/core-v6/src/libraries/JBMetadataResolver.sol";
import {JBSplitHookContext} from "@bananapus/core-v6/src/structs/JBSplitHookContext.sol";

import {IJBSwapSplitHook} from "./interfaces/IJBSwapSplitHook.sol";

/// @notice Swaps payout split funds into the token named by the split beneficiary and adds the output back to the
/// source project's balance.
/// @dev This hook is intentionally stateless and ownerless. Routing policy lives in Juicebox rulesets/splits:
/// - the source token is the payout split group token,
/// - the target token is `context.split.beneficiary`,
/// - slippage and route safety are enforced by the router terminal,
/// - any input-token residue refunded by the router is added back to the source project through the source terminal.
contract JBSwapSplitHook is IJBSwapSplitHook, ReentrancyGuard {
    // A library that adds default safety checks to ERC-20 functionality.
    using SafeERC20 for IERC20;

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    /// @notice Thrown when the split context does not name this contract as its hook.
    /// @param expectedHook This hook's address.
    /// @param actualHook The hook address present in the split context.
    error JBSwapSplitHook_HookMismatch(address expectedHook, address actualHook);

    /// @notice Thrown when the split group is not the payout group for the incoming terminal token.
    /// @param token The incoming terminal token.
    /// @param groupId The group ID supplied by the terminal.
    /// @param expectedGroupId The only accepted payout split group ID.
    error JBSwapSplitHook_InvalidGroup(address token, uint256 groupId, uint256 expectedGroupId);

    /// @notice Thrown when a caller is not one of the source project's terminals.
    /// @param projectId The project whose split was being processed.
    /// @param caller The unauthorized caller.
    error JBSwapSplitHook_InvalidTerminal(uint256 projectId, address caller);

    /// @notice Thrown when a native-token split call sends an unexpected amount of ETH.
    /// @param expected The amount named by the split context.
    /// @param actual The amount received as `msg.value`.
    error JBSwapSplitHook_NativeAmountMismatch(uint256 expected, uint256 actual);

    /// @notice Thrown when the hook is constructed with an invalid dependency.
    error JBSwapSplitHook_ZeroAddress();

    /// @notice Thrown when the split beneficiary does not name a token to swap into.
    error JBSwapSplitHook_ZeroTokenOut();

    //*********************************************************************//
    // ------------------------ internal constants ----------------------- //
    //*********************************************************************//

    /// @notice Metadata key understood by `JBRouterTerminal` for explicit destination-token routing.
    string internal constant _ROUTE_TOKEN_OUT_KEY = "routeTokenOut";

    //*********************************************************************//
    // ---------------- public immutable stored properties --------------- //
    //*********************************************************************//

    /// @notice The directory used to verify source terminal callers.
    IJBDirectory public immutable override DIRECTORY;

    /// @notice The router terminal used to swap and add output back to project balance.
    IJBTerminal public immutable override ROUTER_TERMINAL;

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @notice Deploys a stateless swap split hook.
    /// @dev Both dependencies are immutable because there is no owner or admin recovery path. A bad dependency would
    /// permanently route every configured split through the wrong authority or router.
    /// @param directory The Juicebox directory that tracks project terminals.
    /// @param routerTerminal The router terminal that should execute swaps and add the output back to balance.
    constructor(IJBDirectory directory, IJBTerminal routerTerminal) {
        if (address(directory) == address(0) || address(routerTerminal) == address(0)) {
            revert JBSwapSplitHook_ZeroAddress();
        }

        DIRECTORY = directory;
        ROUTER_TERMINAL = routerTerminal;
    }

    //*********************************************************************//
    // ---------------------- receive / fallback ------------------------- //
    //*********************************************************************//

    /// @notice Accept native-token refunds from router partial fills.
    /// @dev The router may return unspent native input to this hook before `processSplitWith` adds residue back to the
    /// source project. Unsolicited native transfers are not swept by this ownerless contract.
    receive() external payable {}

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Swap split funds into the token named by the split beneficiary and add the result to project balance.
    /// @dev Uses `context.split.beneficiary` as the router's output token. The source terminal either pushes native
    /// tokens as `msg.value` or grants a temporary ERC-20 allowance which this hook pulls. The router terminal receives
    /// the funds and metadata, performs the swap or no-op route, and adds the result to the same project without
    /// minting project tokens.
    /// @param context Standard Juicebox split-hook context supplied by the source terminal.
    function processSplitWith(JBSplitHookContext calldata context) external payable override nonReentrant {
        // Confirm this split explicitly installed this hook.
        if (address(context.split.hook) != address(this)) {
            revert JBSwapSplitHook_HookMismatch({expectedHook: address(this), actualHook: address(context.split.hook)});
        }

        // Only a registered terminal of the source project can invoke the hook.
        if (!DIRECTORY.isTerminalOf({projectId: context.projectId, terminal: IJBTerminal(msg.sender)})) {
            revert JBSwapSplitHook_InvalidTerminal({projectId: context.projectId, caller: msg.sender});
        }

        // Payout split groups are keyed by token. This rejects reserved-token splits and malformed calls.
        uint256 expectedGroupId = uint256(uint160(context.token));
        if (context.groupId != expectedGroupId) {
            revert JBSwapSplitHook_InvalidGroup({
                token: context.token, groupId: context.groupId, expectedGroupId: expectedGroupId
            });
        }

        // The split beneficiary is repurposed as the requested output token.
        address tokenOut = address(context.split.beneficiary);
        if (tokenOut == address(0)) revert JBSwapSplitHook_ZeroTokenOut();

        (uint256 amountIn, uint256 balanceBaseline) =
            _acceptSplitFundsFrom({terminal: IJBTerminal(msg.sender), token: context.token, amount: context.amount});

        // Nothing to route. Returning lets ERC-20 split calls refund through the terminal's partial-pull logic. Native
        // zero-value calls also settle as a no-op.
        if (amountIn == 0) {
            emit SwapSplit({
                projectId: context.projectId,
                terminal: IJBTerminal(msg.sender),
                tokenIn: context.token,
                tokenOut: tokenOut,
                amountIn: 0,
                returnedAmountIn: 0,
                caller: msg.sender
            });
            return;
        }

        // Route the funds through the router. `tokenOut` is encoded into the metadata, scoped to that router.
        _routeToBalance({
            projectId: context.projectId, tokenIn: context.token, amountIn: amountIn, metadata: metadataFor(tokenOut)
        });

        // If the router partially filled and returned input-token residue, add that residue back to the source project.
        uint256 returnedAmountIn = _returnInputResidue({
            projectId: context.projectId,
            terminal: IJBTerminal(msg.sender),
            token: context.token,
            balanceBaseline: balanceBaseline
        });

        emit SwapSplit({
            projectId: context.projectId,
            terminal: IJBTerminal(msg.sender),
            tokenIn: context.token,
            tokenOut: tokenOut,
            amountIn: amountIn,
            returnedAmountIn: returnedAmountIn,
            caller: msg.sender
        });
    }

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    /// @notice Builds router metadata forcing the router to deliver `tokenOut` to the destination project.
    /// @dev The metadata ID is scoped to `ROUTER_TERMINAL`, matching `JBRouterTerminal.addToBalanceOf`'s
    /// `routeTokenOut` lookup. The hook does not add destination-terminal metadata.
    /// @param tokenOut The desired output accounting token.
    /// @return metadata Metadata carrying `routeTokenOut` in the router terminal's namespace.
    function metadataFor(address tokenOut) public view override returns (bytes memory metadata) {
        if (tokenOut == address(0)) revert JBSwapSplitHook_ZeroTokenOut();

        return JBMetadataResolver.addToMetadata({
            originalMetadata: bytes(""),
            idToAdd: JBMetadataResolver.getId({purpose: _ROUTE_TOKEN_OUT_KEY, target: address(ROUTER_TERMINAL)}),
            dataToAdd: abi.encode(tokenOut)
        });
    }

    /// @notice Indicates whether this contract adheres to the specified interface.
    /// @param interfaceId The ID of the interface to check for adherence.
    /// @return A flag indicating whether the provided interface ID is supported.
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IJBSwapSplitHook).interfaceId || interfaceId == type(IJBSplitHook).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    //*********************************************************************//
    // --------------------- internal transactions ----------------------- //
    //*********************************************************************//

    /// @notice Accept the split allocation from the terminal.
    /// @param terminal The terminal invoking this hook.
    /// @param token The split token.
    /// @param amount The amount named by the split context.
    /// @return amountIn The amount this hook actually received and can route.
    /// @return balanceBaseline This hook's pre-split balance for the input token.
    /// @dev Native splits are pushed as `msg.value`. ERC-20 splits are pulled from the source terminal and measured
    /// by balance delta so fee-on-transfer or otherwise lossy tokens cannot make the hook over-route.
    function _acceptSplitFundsFrom(
        IJBTerminal terminal,
        address token,
        uint256 amount
    )
        internal
        returns (uint256 amountIn, uint256 balanceBaseline)
    {
        if (token == JBConstants.NATIVE_TOKEN) {
            if (msg.value != amount) {
                revert JBSwapSplitHook_NativeAmountMismatch({expected: amount, actual: msg.value});
            }

            // `address(this).balance` already includes `msg.value`.
            balanceBaseline = address(this).balance - msg.value;
            return (msg.value, balanceBaseline);
        }

        if (msg.value != 0) revert JBSwapSplitHook_NativeAmountMismatch({expected: 0, actual: msg.value});

        balanceBaseline = IERC20(token).balanceOf(address(this));
        if (amount != 0) IERC20(token).safeTransferFrom({from: address(terminal), to: address(this), value: amount});

        amountIn = IERC20(token).balanceOf(address(this)) - balanceBaseline;
    }

    /// @notice Add any input-token residue refunded by the router back to the source project.
    /// @param projectId The source project.
    /// @param terminal The source terminal.
    /// @param token The input token.
    /// @param balanceBaseline This hook's balance before accepting the split.
    /// @return residue The amount added back to the source project balance.
    /// @dev Residue is measured against the pre-split baseline, so forced or stale balances are not swept into the
    /// current rebalance. ERC-20 residue uses a temporary allowance for the source terminal and clears it afterwards.
    function _returnInputResidue(
        uint256 projectId,
        IJBTerminal terminal,
        address token,
        uint256 balanceBaseline
    )
        internal
        returns (uint256 residue)
    {
        if (token == JBConstants.NATIVE_TOKEN) {
            uint256 nativeBalance = address(this).balance;
            if (nativeBalance <= balanceBaseline) return 0;

            residue = nativeBalance - balanceBaseline;
            terminal.addToBalanceOf{value: residue}({
                projectId: projectId,
                token: token,
                amount: residue,
                shouldReturnHeldFees: false,
                memo: "",
                metadata: bytes("")
            });
            return residue;
        }

        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        if (tokenBalance <= balanceBaseline) return 0;

        residue = tokenBalance - balanceBaseline;
        IERC20(token).forceApprove({spender: address(terminal), value: residue});
        terminal.addToBalanceOf({
            projectId: projectId,
            token: token,
            amount: residue,
            shouldReturnHeldFees: false,
            memo: "",
            metadata: bytes("")
        });
        IERC20(token).forceApprove({spender: address(terminal), value: 0});
    }

    /// @notice Route the received input amount through the configured router terminal.
    /// @param projectId The project whose balance should receive the routed output.
    /// @param tokenIn The input token held by this hook.
    /// @param amountIn The amount of input token to route.
    /// @param metadata Router metadata forcing the beneficiary-derived output token.
    /// @dev For native input, forwards `msg.value` to the router. For ERC-20 input, grants the router a temporary
    /// allowance and clears it after a successful route. If the router reverts, the whole transaction reverts and the
    /// temporary allowance is rolled back.
    function _routeToBalance(uint256 projectId, address tokenIn, uint256 amountIn, bytes memory metadata) internal {
        if (tokenIn == JBConstants.NATIVE_TOKEN) {
            ROUTER_TERMINAL.addToBalanceOf{value: amountIn}({
                projectId: projectId,
                token: tokenIn,
                amount: amountIn,
                shouldReturnHeldFees: false,
                memo: "",
                metadata: metadata
            });
            return;
        }

        IERC20(tokenIn).forceApprove({spender: address(ROUTER_TERMINAL), value: amountIn});

        ROUTER_TERMINAL.addToBalanceOf({
            projectId: projectId,
            token: tokenIn,
            amount: amountIn,
            shouldReturnHeldFees: false,
            memo: "",
            metadata: metadata
        });

        IERC20(tokenIn).forceApprove({spender: address(ROUTER_TERMINAL), value: 0});
    }
}
