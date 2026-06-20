// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {IJBPayHook} from "@bananapus/core-v6/src/interfaces/IJBPayHook.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBSplitHookContext} from "@bananapus/core-v6/src/structs/JBSplitHookContext.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {JBRuleset} from "@bananapus/core-v6/src/structs/JBRuleset.sol";
import {JBPayHookSpecification} from "@bananapus/core-v6/src/structs/JBPayHookSpecification.sol";

/// @notice Minimal terminal that can invoke split hooks and receive add-to-balance calls.
contract MockTerminal is IJBTerminal {
    using SafeERC20 for IERC20;

    mapping(uint256 projectId => mapping(address token => uint256 balance)) public balanceOf;
    mapping(uint256 projectId => mapping(address token => JBAccountingContext context)) public contextOf;

    receive() external payable {}

    function setAccountingContext(uint256 projectId, address token, uint8 decimals, uint32 currency) external {
        contextOf[projectId][token] = JBAccountingContext({token: token, decimals: decimals, currency: currency});
    }

    function executeSplit(JBSplitHookContext calldata context) external payable {
        if (context.token == JBConstants.NATIVE_TOKEN) {
            IJBSplitHook(context.split.hook).processSplitWith{value: context.amount}(context);
            return;
        }

        IERC20(context.token).forceApprove({spender: address(context.split.hook), value: context.amount});
        IJBSplitHook(context.split.hook).processSplitWith(context);
        IERC20(context.token).forceApprove({spender: address(context.split.hook), value: 0});
    }

    function addToBalanceOf(
        uint256 projectId,
        address token,
        uint256 amount,
        bool,
        string calldata,
        bytes calldata
    )
        external
        payable
        override
    {
        if (token == JBConstants.NATIVE_TOKEN) {
            balanceOf[projectId][token] += msg.value;
            return;
        }

        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom({from: msg.sender, to: address(this), value: amount});
        balanceOf[projectId][token] += IERC20(token).balanceOf(address(this)) - balanceBefore;
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
        uint256 projectId,
        address token
    )
        external
        view
        override
        returns (JBAccountingContext memory)
    {
        return contextOf[projectId][token];
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
