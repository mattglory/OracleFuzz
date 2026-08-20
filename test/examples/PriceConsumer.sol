// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9;

import {FtsoV2Interface} from "../../src/interfaces/FtsoV2Interface.sol";

/// @title PriceConsumer
/// @notice Toy example: a minimal "value my collateral" function, structurally
/// identical to the first thing almost every lending/perps/vault protocol on Flare
/// writes against FtsoV2. `maxStaleness` controls whether it's the CORRECT version
/// (rejects stale prices) or the BUGGY version (maxStaleness = type(uint64).max,
/// i.e. no effective staleness check at all) - see PriceConsumer.t.sol.
contract PriceConsumer {
    FtsoV2Interface public immutable ftso;
    bytes21 public immutable feedId;
    uint64 public immutable maxStaleness;

    error StalePrice(uint64 age, uint64 maxAge);

    constructor(FtsoV2Interface _ftso, bytes21 _feedId, uint64 _maxStaleness) {
        ftso = _ftso;
        feedId = _feedId;
        maxStaleness = _maxStaleness;
    }

    /// @notice Returns the collateral value of `amount` units of the underlying,
    /// reverting if the underlying price feed is stale.
    function collateralValue(uint256 amount) external returns (uint256) {
        (uint256 price, uint64 timestamp) = ftso.getFeedByIdInWei(feedId);

        uint64 age = uint64(block.timestamp) - timestamp;
        if (age > maxStaleness) revert StalePrice(age, maxStaleness);

        return (amount * price) / 1e18;
    }
}
