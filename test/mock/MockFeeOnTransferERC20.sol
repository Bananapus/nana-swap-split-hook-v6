// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {MockERC20} from "./MockERC20.sol";

/// @notice ERC-20 test token that skims a transfer fee into a sink address.
contract MockFeeOnTransferERC20 is MockERC20 {
    address internal constant FEE_SINK = address(0xfee);

    uint256 public immutable feeBps;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 feeBps_
    )
        MockERC20(name_, symbol_, decimals_)
    {
        feeBps = feeBps_;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from == address(0) || to == address(0) || feeBps == 0) {
            super._update({from: from, to: to, value: value});
            return;
        }

        uint256 fee = (value * feeBps) / 10_000;
        uint256 net = value - fee;

        if (fee != 0) super._update({from: from, to: FEE_SINK, value: fee});
        super._update({from: from, to: to, value: net});
    }
}
