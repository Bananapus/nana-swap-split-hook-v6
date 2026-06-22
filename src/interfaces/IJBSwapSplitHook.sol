// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {JBSplitHookContext} from "@bananapus/core-v6/src/structs/JBSplitHookContext.sol";

/// @notice A payout split hook that swaps the split's terminal token into the token named by the split beneficiary,
/// then adds the output back to the source project balance through a router terminal.
interface IJBSwapSplitHook is IJBSplitHook {
    /// @notice Emitted after the hook routes a split allocation into the requested output token.
    /// @param projectId The project whose split was processed.
    /// @param terminal The terminal that invoked the hook.
    /// @param tokenIn The terminal token paid to the split.
    /// @param tokenOut The token named by `context.split.beneficiary`.
    /// @param amountIn The amount of `tokenIn` actually routed through the router after transfer effects.
    /// @param returnedAmountIn Any unspent input amount added back to the source project balance.
    /// @param caller The caller observed by this hook.
    event SwapSplit(
        uint256 indexed projectId,
        IJBTerminal indexed terminal,
        address indexed tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 returnedAmountIn,
        address caller
    );

    /// @notice The directory used to verify project terminal callers.
    function DIRECTORY() external view returns (IJBDirectory);

    /// @notice Builds the router metadata used for a split targeting `tokenOut`.
    /// @param tokenOut The token the router should deliver to the destination project.
    /// @return metadata Metadata carrying the router-scoped `routeTokenOut` override.
    function metadataFor(address tokenOut) external view returns (bytes memory metadata);

    /// @notice The router terminal used to convert input split tokens and add the output back to project balance.
    function ROUTER_TERMINAL() external view returns (IJBTerminal);

    /// @notice Process a split allocation.
    /// @param context The split hook context supplied by the terminal.
    function processSplitWith(JBSplitHookContext calldata context) external payable;
}
