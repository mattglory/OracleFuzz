// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9;

/// @notice The only thing Kinetic's OverridablePriceOracle.getPrice() needs
/// from the "underlying" token is `decimals()`. Standing in for a real ERC20.
contract MockDecimalsToken {
    uint8 public immutable decimals;

    constructor(uint8 _decimals) {
        decimals = _decimals;
    }
}
