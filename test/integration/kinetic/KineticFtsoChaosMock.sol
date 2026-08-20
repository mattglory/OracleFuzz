// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9;

/// @notice Chaos-injectable stand-in for Flare's FTSOv2, matching the exact
/// ABI selectors of Kinetic Market's own `IFTSOV2` interface (kinetic-market/
/// public-money-market-contracts, contracts/FTSO/IFTSOV2.sol, solc 0.5.17).
/// Deliberately NOT `is IFTSOV2` - that interface is pinned to solc 0.5.17 and
/// can't be imported into an 0.8.x file in the same compilation unit. Matching
/// the function selectors is sufficient: Kinetic's oracle calls this contract
/// through a low-level ABI-encoded external call, which only cares that the
/// selector and return encoding match, not which compiler produced either side.
contract KineticFtsoChaosMock {
    struct Feed {
        uint256 value;
        int8 decimals;
        uint64 lastUpdateTimestamp;
        bool exists;
    }

    mapping(bytes21 => Feed) internal feeds;

    error FeedDoesNotExist(bytes21 feedId);

    function setFeedData(bytes21 feedId, uint256 value, int8 decimals) external {
        feeds[feedId] = Feed(value, decimals, uint64(block.timestamp), true);
    }

    /// @notice Rewind a feed's last-update timestamp so it reads as stale.
    function setStale(bytes21 feedId, uint256 secondsStale) external {
        Feed storage f = feeds[feedId];
        if (!f.exists) revert FeedDoesNotExist(feedId);
        f.lastUpdateTimestamp = secondsStale >= block.timestamp ? 0 : uint64(block.timestamp - secondsStale);
    }

    /// @notice Matches IFTSOV2.getFeedById(bytes21) -> (uint256, int8, uint64).
    function getFeedById(bytes21 _feedId) external view returns (uint256 value, int8 decimals, uint64 timestamp) {
        Feed memory f = feeds[_feedId];
        if (!f.exists) revert FeedDoesNotExist(_feedId);
        return (f.value, f.decimals, f.lastUpdateTimestamp);
    }

    /// @notice Matches IFTSOV2.FTSO_PROTOCOL_ID() -> uint256 (sanity-check call
    /// made once by Kinetic's setFTSOV2()).
    function FTSO_PROTOCOL_ID() external pure returns (uint256) {
        return 100;
    }
}
