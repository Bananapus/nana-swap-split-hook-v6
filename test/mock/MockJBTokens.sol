// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IJBToken} from "@bananapus/core-v6/src/interfaces/IJBToken.sol";
import {IJBTokens} from "@bananapus/core-v6/src/interfaces/IJBTokens.sol";

/// @notice Minimal `IJBTokens` implementation for router fork tests. Every token is treated as an external ERC-20.
contract MockJBTokens is IJBTokens {
    function creditBalanceOf(address, uint256) external pure override returns (uint256) {
        return 0;
    }

    function projectIdOf(IJBToken) external pure override returns (uint256) {
        return 0;
    }

    function tokenOf(uint256) external pure override returns (IJBToken) {
        return IJBToken(address(0));
    }

    function totalBalanceOf(address, uint256) external pure override returns (uint256) {
        return 0;
    }

    function totalCreditSupplyOf(uint256) external pure override returns (uint256) {
        return 0;
    }

    function totalSupplyOf(uint256) external pure override returns (uint256) {
        return 0;
    }

    function burnFrom(address, uint256, uint256) external pure override {}

    function claimTokensFor(address, uint256, uint256, address) external pure override {}

    function deployERC20For(
        uint256,
        string calldata,
        string calldata,
        bytes32
    )
        external
        pure
        override
        returns (IJBToken)
    {
        return IJBToken(address(0));
    }

    function mintFor(address, uint256, uint256) external pure override returns (IJBToken) {
        return IJBToken(address(0));
    }

    function setTokenFor(uint256, IJBToken) external pure override {}

    function setTokenMetadataFor(uint256, string calldata, string calldata) external pure override {}

    function transferCreditsFrom(address, uint256, address, uint256) external pure override {}
}
