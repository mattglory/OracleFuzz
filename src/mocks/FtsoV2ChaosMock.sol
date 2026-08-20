// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9;

import {FtsoV2Interface} from "../interfaces/FtsoV2Interface.sol";

/// @title FtsoV2ChaosMock
/// @notice A drop-in mock of Flare's FtsoV2Interface, purpose-built for fuzz/invariant
/// testing of contracts that consume FTSO price feeds.
/// @dev Every published Flare FTSO mock the ecosystem currently has (Flare's own
/// periphery package, and individual project test suites) implements the HAPPY PATH
/// only: set a value, read it back. None of them let a test author cheaply simulate
/// the failure modes that actually cause DeFi incidents:
///   - a feed going stale (oracle stops updating, but the last value still reads fine)
///   - a feed jumping by an extreme amount between reads (manipulation or real crash)
///   - the FTSO system reverting entirely (partial outage, one feed down)
///   - the FeedData struct's `decimals` field being genuinely negative (the real
///     interface allows int8 decimals, and this is a case protocols routinely forget
///     to handle correctly in normalization math)
/// This contract makes all four cheap to trigger from a fuzzer, so a Foundry invariant
/// test can assert things like "this protocol never accepts a price older than N
/// seconds" and have the fuzzer actually go find the counterexample if the protocol's
/// staleness check is missing, inverted, or off-by-one.
contract FtsoV2ChaosMock is FtsoV2Interface {
    struct Feed {
        int32 value;
        int8 decimals;
        uint64 lastUpdateTimestamp;
        uint32 votingRoundId;
        bool exists;
    }

    /// @notice Per-feed stored state, set via setFeedData / the chaos setters below.
    mapping(bytes21 => Feed) public feeds;

    /// @notice If true, any read of this feed reverts (simulates the FTSO system
    /// being fully unavailable for that feed - e.g. mid-outage, or a feed removed).
    mapping(bytes21 => bool) public forceRevert;

    /// @notice Flat fee (in wei) charged per feed on the payable read functions,
    /// mirroring FtsoV2's real fee-for-read model. Configurable per feed.
    mapping(bytes21 => uint256) public feeById;

    bytes21[] private _supportedFeedIds;
    uint256 public protocolId = 200;

    error FeedDoesNotExist(bytes21 feedId);
    error FeedForcedRevert(bytes21 feedId);
    error InsufficientFee(uint256 required, uint256 provided);

    // ------------------------------------------------------------------
    // Test-author configuration surface (not part of FtsoV2Interface)
    // ------------------------------------------------------------------

    /// @notice Set a feed's "current" happy-path state, as if it had just updated.
    /// @dev Registers the feed in getSupportedFeedIds() if new.
    function setFeedData(bytes21 feedId, int32 value, int8 decimals) public {
        if (!feeds[feedId].exists) {
            _supportedFeedIds.push(feedId);
        }
        feeds[feedId] = Feed({
            value: value,
            decimals: decimals,
            lastUpdateTimestamp: uint64(block.timestamp),
            votingRoundId: feeds[feedId].votingRoundId + 1,
            exists: true
        });
    }

    /// @notice Chaos: make a feed's last-update timestamp `secondsStale` seconds in
    /// the past, without changing its value. This is the single most realistic and
    /// most commonly mishandled oracle failure mode - the price LOOKS fine, it's just
    /// old, and many protocols never check `block.timestamp - _timestamp` at all.
    function setStale(bytes21 feedId, uint64 secondsStale) external {
        require(feeds[feedId].exists, "set value first");
        if (secondsStale > block.timestamp) {
            feeds[feedId].lastUpdateTimestamp = 0;
        } else {
            feeds[feedId].lastUpdateTimestamp = uint64(block.timestamp) - secondsStale;
        }
    }

    /// @notice Chaos: jump a feed's value by `bps` basis points (can exceed 10000 for
    /// a >100% move) in one update, same-block, no intermediate price. Simulates both
    /// a genuine crash/spike and a manipulation-style single-block price jump.
    /// @param up if true, increases value by bps/10000; if false, decreases (floored at 1).
    function jumpPrice(bytes21 feedId, uint256 bps, bool up) external {
        Feed storage f = feeds[feedId];
        require(f.exists, "set value first");
        int256 delta = (int256(f.value) * int256(bps)) / 10000;
        int256 newValue = up ? int256(f.value) + delta : int256(f.value) - delta;
        if (newValue < 1) newValue = 1;
        f.value = int32(newValue > type(int32).max ? type(int32).max : newValue);
        f.lastUpdateTimestamp = uint64(block.timestamp);
        f.votingRoundId += 1;
    }

    /// @notice Chaos: force every read of this feed to revert, simulating the FTSO
    /// system being unavailable (protocol outage, feed deregistered mid-flight, etc.)
    /// so callers that don't handle a failed oracle read (e.g. no try/catch, no
    /// fallback price, no pause) get caught by an invariant instead of in production.
    function setForceRevert(bytes21 feedId, bool shouldRevert) external {
        forceRevert[feedId] = shouldRevert;
    }

    /// @notice Set the read fee for a feed, to test fee-handling logic (protocols
    /// that under-fund `calculateFeeById` and pass a fixed msg.value will revert).
    function setFee(bytes21 feedId, uint256 fee) external {
        feeById[feedId] = fee;
    }

    // ------------------------------------------------------------------
    // FtsoV2Interface implementation
    // ------------------------------------------------------------------

    function getFeedById(bytes21 _feedId)
        public
        payable
        override
        returns (uint256 _value, int8 _decimals, uint64 _timestamp)
    {
        Feed memory f = _read(_feedId);
        return (uint256(uint32(f.value)), f.decimals, f.lastUpdateTimestamp);
    }

    function getFeedsById(bytes21[] memory _feedIds)
        external
        payable
        override
        returns (uint256[] memory _values, int8[] memory _decimals, uint64 _timestamp)
    {
        _values = new uint256[](_feedIds.length);
        _decimals = new int8[](_feedIds.length);
        for (uint256 i = 0; i < _feedIds.length; i++) {
            Feed memory f = _read(_feedIds[i]);
            _values[i] = uint256(uint32(f.value));
            _decimals[i] = f.decimals;
            _timestamp = f.lastUpdateTimestamp;
        }
    }

    function getFeedByIdInWei(bytes21 _feedId)
        external
        payable
        override
        returns (uint256 _value, uint64 _timestamp)
    {
        Feed memory f = _read(_feedId);
        _value = _toWei(f.value, f.decimals);
        _timestamp = f.lastUpdateTimestamp;
    }

    function getFeedsByIdInWei(bytes21[] memory _feedIds)
        external
        payable
        override
        returns (uint256[] memory _values, uint64 _timestamp)
    {
        _values = new uint256[](_feedIds.length);
        for (uint256 i = 0; i < _feedIds.length; i++) {
            Feed memory f = _read(_feedIds[i]);
            _values[i] = _toWei(f.value, f.decimals);
            _timestamp = f.lastUpdateTimestamp;
        }
    }

    function getFtsoProtocolId() external view override returns (uint256) {
        return protocolId;
    }

    function getSupportedFeedIds() external view override returns (bytes21[] memory) {
        return _supportedFeedIds;
    }

    function getFeedIdChanges() external pure override returns (FeedIdChange[] memory) {
        return new FeedIdChange[](0);
    }

    function calculateFeeById(bytes21 _feedId) public view override returns (uint256) {
        return feeById[_feedId];
    }

    function calculateFeeByIds(bytes21[] memory _feedIds) external view override returns (uint256 _fee) {
        for (uint256 i = 0; i < _feedIds.length; i++) {
            _fee += feeById[_feedIds[i]];
        }
    }

    /// @notice Chaos-mode `verifyFeedData`: rather than checking a real Merkle proof,
    /// this returns whatever the test author last configured via `setVerifyResult`,
    /// so tests can cheaply cover both "attestation accepted" and "attestation
    /// rejected" without constructing a real Merkle tree.
    mapping(bytes21 => bool) public verifyResult;

    function setVerifyResult(bytes21 feedId, bool result) external {
        verifyResult[feedId] = result;
    }

    function verifyFeedData(FeedDataWithProof calldata _feedData) external view override returns (bool) {
        return verifyResult[_feedData.body.id];
    }

    // ------------------------------------------------------------------
    // Internal
    // ------------------------------------------------------------------

    function _read(bytes21 feedId) internal returns (Feed memory f) {
        if (forceRevert[feedId]) revert FeedForcedRevert(feedId);
        f = feeds[feedId];
        if (!f.exists) revert FeedDoesNotExist(feedId);
        uint256 fee = feeById[feedId];
        if (msg.value < fee) revert InsufficientFee(fee, msg.value);
    }

    function _toWei(int32 value, int8 decimals) internal pure returns (uint256) {
        uint256 v = uint256(uint32(value));
        if (decimals >= 0) {
            uint8 d = uint8(decimals);
            return d <= 18 ? v * (10 ** (18 - d)) : v / (10 ** (d - 18));
        } else {
            // Real FeedData.decimals is int8 and CAN be negative - a protocol that
            // assumes decimals is always >= 0 will underflow/misnormalize here.
            uint8 d = uint8(-decimals);
            return v * (10 ** (18 + uint256(d)));
        }
    }
}
