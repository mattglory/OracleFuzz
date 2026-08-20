// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9;

import {FtsoV2Interface} from "../../src/interfaces/FtsoV2Interface.sol";

/// @title PriceConsumerBuggy
/// @notice Same as PriceConsumer, but missing the staleness check - a realistic
/// omission (the timestamp return value is simply never inspected). Used by
/// PriceConsumer.t.sol to demonstrate that the chaos mock's fuzz campaign actually
/// finds this class of bug rather than just exercising the happy path.
contract PriceConsumerBuggy {
    FtsoV2Interface public immutable ftso;
    bytes21 public immutable feedId;

    constructor(FtsoV2Interface _ftso, bytes21 _feedId) {
        ftso = _ftso;
        feedId = _feedId;
    }

    function collateralValue(uint256 amount) external returns (uint256) {
        (uint256 price,) = ftso.getFeedByIdInWei(feedId);
        return (amount * price) / 1e18;
    }
}
