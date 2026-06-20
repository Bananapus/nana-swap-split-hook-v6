// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {JBSplitHookContext} from "@bananapus/core-v6/src/structs/JBSplitHookContext.sol";

import {JBSwapSplitHook} from "../../src/JBSwapSplitHook.sol";
import {MockRouterTerminal} from "./MockRouterTerminal.sol";
import {MockDirectory} from "./MockDirectory.sol";

/// @notice Router mock that attempts to reenter the hook before completing a normal mocked route.
contract MockReentrantRouterTerminal is MockRouterTerminal {
    JBSwapSplitHook public hook;
    address public token;
    uint256 public projectId;
    bool public reentryBlocked;

    constructor(MockDirectory directory) MockRouterTerminal(directory) {}

    function setReentry(JBSwapSplitHook hook_, uint256 projectId_, address token_) external {
        hook = hook_;
        projectId = projectId_;
        token = token_;
    }

    function addToBalanceOf(
        uint256 projectId_,
        address token_,
        uint256 amount,
        bool shouldReturnHeldFees,
        string calldata memo,
        bytes calldata metadata
    )
        external
        payable
        override
    {
        JBSplit memory split = JBSplit({
            percent: 0, projectId: 0, beneficiary: payable(token), preferAddToBalance: false, lockedUntil: 0, hook: hook
        });
        JBSplitHookContext memory context = JBSplitHookContext({
            token: token, amount: 0, decimals: 18, projectId: projectId, groupId: uint256(uint160(token)), split: split
        });

        try hook.processSplitWith(context) {
            reentryBlocked = false;
        } catch {
            reentryBlocked = true;
        }

        shouldReturnHeldFees;
        memo;

        _addToBalanceOf({projectId: projectId_, token: token_, amount: amount, metadata: metadata});
    }
}
