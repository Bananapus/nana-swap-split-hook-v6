// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBMetadataResolver} from "@bananapus/core-v6/src/libraries/JBMetadataResolver.sol";
import {JBSplitHookContext} from "@bananapus/core-v6/src/structs/JBSplitHookContext.sol";

import {IJBSwapSplitHook} from "./interfaces/IJBSwapSplitHook.sol";

/// @notice Swaps payout split funds into the token named by the split beneficiary and adds the output back to the
/// source project's balance.
/// @dev This hook is intentionally stateless and ownerless. Routing policy lives in Juicebox rulesets/splits:
/// - the source token is the payout split group token,
/// - the target token is `context.split.beneficiary`,
/// - slippage/route safety is enforced by the router terminal.
contract JBSwapSplitHook is IJBSwapSplitHook, ReentrancyGuard {
    using SafeERC20 for IERC20;

    //*********************************************************************//
    // ---------------- public immutable stored properties --------------- //
    //*********************************************************************//

    /// @notice The directory used to verify source terminal callers.
    IJBDirectory public immutable override DIRECTORY;

    /// @notice The router terminal used to swap and add output back to project balance.
    IJBTerminal public immutable override ROUTER_TERMINAL;

    //*********************************************************************//
    // ------------------------ internal constants ----------------------- //
    //*********************************************************************//

    /// @notice Metadata key understood by `JBRouterTerminal` for explicit destination-token routing.
    string internal constant ROUTE_TOKEN_OUT_KEY = "routeTokenOut";

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

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
    receive() external payable {}

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Swap split funds into the token named by the split beneficiary and add the result to project balance.
    /// @param context Standard Juicebox split-hook context.
    function processSplitWith(JBSplitHookContext calldata context) external payable override nonReentrant {
        // Make sure the context was meant for this hook.
        if (address(context.split.hook) != address(this)) {
            revert JBSwapSplitHook_HookMismatch({expectedHook: address(this), actualHook: address(context.split.hook)});
        }

        // The split hook can only be invoked by a terminal of the project whose payout is being processed.
        if (!DIRECTORY.isTerminalOf({projectId: context.projectId, terminal: IJBTerminal(msg.sender)})) {
            revert JBSwapSplitHook_InvalidTerminal({projectId: context.projectId, caller: msg.sender});
        }

        // Payout split groups are keyed by the payout token. This rejects reserved-token splits and malformed calls.
        uint256 expectedGroupId = uint256(uint160(context.token));
        if (context.groupId != expectedGroupId) {
            revert JBSwapSplitHook_InvalidGroup({
                token: context.token, groupId: context.groupId, expectedGroupId: expectedGroupId
            });
        }

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

        _routeToBalance({
            projectId: context.projectId, tokenIn: context.token, amountIn: amountIn, metadata: metadataFor(tokenOut)
        });

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
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice Builds router metadata forcing the router to deliver `tokenOut` to the destination project.
    /// @param tokenOut The desired output accounting token.
    /// @return metadata Metadata carrying `routeTokenOut` in the router terminal's namespace.
    function metadataFor(address tokenOut) public view override returns (bytes memory metadata) {
        if (tokenOut == address(0)) revert JBSwapSplitHook_ZeroTokenOut();

        return JBMetadataResolver.addToMetadata({
            originalMetadata: bytes(""),
            idToAdd: JBMetadataResolver.getId({purpose: ROUTE_TOKEN_OUT_KEY, target: address(ROUTER_TERMINAL)}),
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

    /// @notice Route the received input amount through the configured router terminal.
    /// @param projectId The project whose balance should receive the routed output.
    /// @param tokenIn The input token held by this hook.
    /// @param amountIn The amount of input token to route.
    /// @param metadata Router metadata forcing `tokenOut`.
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

    /// @notice Add any input-token residue refunded by the router back to the source project.
    /// @param projectId The source project.
    /// @param terminal The source terminal.
    /// @param token The input token.
    /// @param balanceBaseline This hook's balance before accepting the split.
    /// @return residue The amount added back to the source project balance.
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
}
