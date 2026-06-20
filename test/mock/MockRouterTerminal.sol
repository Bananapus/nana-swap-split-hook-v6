// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBMetadataResolver} from "@bananapus/core-v6/src/libraries/JBMetadataResolver.sol";
import {JBPayHookSpecification} from "@bananapus/core-v6/src/structs/JBPayHookSpecification.sol";
import {JBRuleset} from "@bananapus/core-v6/src/structs/JBRuleset.sol";

import {MockERC20} from "./MockERC20.sol";

/// @notice Router mock that consumes a configurable fraction of input and deposits minted output into the destination
/// terminal.
contract MockRouterTerminal is IJBTerminal {
    using SafeERC20 for IERC20;

    IJBDirectory public immutable DIRECTORY;

    uint256 public consumeBps = 10_000;
    uint256 public rateNumerator = 1;
    uint256 public rateDenominator = 1;

    receive() external payable {}

    constructor(IJBDirectory directory) {
        DIRECTORY = directory;
    }

    function setConsumeBps(uint256 consumeBps_) external {
        consumeBps = consumeBps_;
    }

    function setRate(uint256 numerator, uint256 denominator) external {
        rateNumerator = numerator;
        rateDenominator = denominator;
    }

    function addToBalanceOf(
        uint256 projectId,
        address token,
        uint256 amount,
        bool,
        string calldata,
        bytes calldata metadata
    )
        external
        payable
        virtual
        override
    {
        _addToBalanceOf({projectId: projectId, token: token, amount: amount, metadata: metadata});
    }

    function _addToBalanceOf(uint256 projectId, address token, uint256 amount, bytes calldata metadata) internal {
        address tokenOut = _tokenOutFrom(metadata);
        uint256 received = _accept({token: token, amount: amount});
        uint256 consumed = (received * consumeBps) / 10_000;
        uint256 residue = received - consumed;

        if (residue != 0) _refund({token: token, amount: residue});

        uint256 output = (consumed * rateNumerator) / rateDenominator;
        IJBTerminal terminal = DIRECTORY.primaryTerminalOf({projectId: projectId, token: tokenOut});

        if (tokenOut == JBConstants.NATIVE_TOKEN) {
            terminal.addToBalanceOf{value: output}({
                projectId: projectId,
                token: tokenOut,
                amount: output,
                shouldReturnHeldFees: false,
                memo: "",
                metadata: bytes("")
            });
        } else {
            MockERC20(tokenOut).mint(address(this), output);
            IERC20(tokenOut).forceApprove({spender: address(terminal), value: output});
            terminal.addToBalanceOf({
                projectId: projectId,
                token: tokenOut,
                amount: output,
                shouldReturnHeldFees: false,
                memo: "",
                metadata: bytes("")
            });
            IERC20(tokenOut).forceApprove({spender: address(terminal), value: 0});
        }
    }

    function _accept(address token, uint256 amount) internal returns (uint256 received) {
        if (token == JBConstants.NATIVE_TOKEN) return msg.value;

        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom({from: msg.sender, to: address(this), value: amount});
        received = IERC20(token).balanceOf(address(this)) - balanceBefore;
    }

    function _refund(address token, uint256 amount) internal {
        if (token == JBConstants.NATIVE_TOKEN) {
            (bool success,) = msg.sender.call{value: amount}("");
            require(success, "REFUND_FAILED");
            return;
        }

        IERC20(token).safeTransfer({to: msg.sender, value: amount});
    }

    function _tokenOutFrom(bytes calldata metadata) internal view returns (address tokenOut) {
        (bool exists, bytes memory data) = JBMetadataResolver.getDataFor({
            id: JBMetadataResolver.getId({purpose: "routeTokenOut", target: address(this)}), metadata: metadata
        });
        require(exists, "NO_ROUTE_TOKEN_OUT");
        tokenOut = abi.decode(data, (address));
    }

    function addAccountingContextsFor(uint256, JBAccountingContext[] calldata) external pure override {}

    function previewPayFor(
        uint256,
        address,
        uint256,
        address,
        bytes calldata
    )
        external
        pure
        override
        returns (
            JBRuleset memory ruleset,
            uint256 beneficiaryTokenCount,
            uint256 reservedTokenCount,
            JBPayHookSpecification[] memory hookSpecifications
        )
    {
        ruleset;
        beneficiaryTokenCount;
        reservedTokenCount;
        hookSpecifications = new JBPayHookSpecification[](0);
    }

    function accountingContextForTokenOf(
        uint256,
        address token
    )
        external
        pure
        override
        returns (JBAccountingContext memory)
    {
        return JBAccountingContext({token: token, decimals: 18, currency: uint32(uint160(token))});
    }

    function accountingContextsOf(uint256) external pure override returns (JBAccountingContext[] memory contexts) {
        return contexts;
    }

    function currentSurplusOf(uint256, address[] calldata, uint256, uint256) external pure override returns (uint256) {
        return 0;
    }

    function migrateBalanceOf(uint256, address, IJBTerminal) external pure override returns (uint256) {
        return 0;
    }

    function pay(
        uint256,
        address,
        uint256,
        address,
        uint256,
        string calldata,
        bytes calldata
    )
        external
        payable
        override
        returns (uint256)
    {
        return 0;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IJBTerminal).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
