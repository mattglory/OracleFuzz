// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9;

import {Test, console2} from "forge-std/Test.sol";
import {IFtsoFeedPublisher} from "@flarenetwork/flare-periphery-contracts/flare/IFtsoFeedPublisher.sol";

// OracleFuzz x SparkDEX integration
//
// Points OracleFuzz's chaos-injection approach at SparkDEX's real, deployed-on-
// Flare `FTSOv2.sol` utility contract (installed unmodified via `forge install`
// from SparkDEX/perp-smart-contracts), specifically its `getPrice()` path, which
// enforces staleness via voting-round arithmetic rather than a stored timestamp.
//
// Unlike Kinetic's oracle (which takes its FTSO dependency as a constructor
// argument, directly swappable for a drop-in ChaosMock) SparkDEX's FTSOv2
// resolves its oracle dependencies internally, at construction time, via
// Flare's live on-chain `ContractRegistry` (a fixed, well-known mainnet
// address). That can't be swapped for a mock before deployment without forking
// real chain state - so this test forks Flare mainnet, deploys the real
// FTSOv2.sol against the REAL, live `ContractRegistry` (getting back the real,
// live `FtsoFeedPublisher` address), and then uses Foundry's `vm.mockCall` to
// chaos-inject the specific `getCurrentFeed()` call FTSOv2 makes to that real
// address - a different, complementary technique to M1/M2's drop-in ChaosMock
// contracts, useful for any protocol that resolves Flare's oracles via the
// registry pattern rather than constructor injection.
//
// FTSOv2.sol is pinned to exactly `pragma solidity 0.8.22`, which can't be
// directly imported here (see _CompileTarget.sol for why) - deployed via
// forge-std's `deployCode` and driven entirely through low-level calls,
// matching the pattern in test/integration/kinetic/.
bytes21 constant FEED_ID = bytes21(uint168(uint256(keccak256("FLR/USD"))));
string constant FLARE_MAINNET_RPC = "https://flare-api.flare.network/ext/C/rpc";

contract Handler is Test {
    address public ftsov2;
    address public feedPublisher;
    uint32 public firstVotingRoundStartTs;
    uint8 public votingEpochDurationSeconds;
    uint256 public constant DEFAULT_STALE_PERIOD = 1800; // FTSOv2.MAX_RATE_STALE_PERIOD, used when unconfigured

    bool public everAcceptedInvalidOrStalePrice;
    uint256 public callCount;
    uint256 public revertCount;

    constructor(address _ftsov2) {
        ftsov2 = _ftsov2;
        (, bytes memory fp) = _ftsov2.staticcall(abi.encodeWithSignature("ftsoFeedPublisher()"));
        feedPublisher = abi.decode(fp, (address));
        (, bytes memory ts) = _ftsov2.staticcall(abi.encodeWithSignature("firstVotingRoundStartTs()"));
        firstVotingRoundStartTs = abi.decode(ts, (uint32));
        (, bytes memory dur) = _ftsov2.staticcall(abi.encodeWithSignature("votingEpochDurationSeconds()"));
        votingEpochDurationSeconds = abi.decode(dur, (uint8));
    }

    /// @notice Chaos-injects a feed reading `roundsAgo` voting rounds behind the
    /// round the current block timestamp would correspond to, with a fuzzed
    /// (possibly invalid, i.e. <= 0) price value, then queries getPrice() and
    /// checks - from OUTSIDE the contract - whether it was ever accepted despite
    /// being stale or invalid.
    function queryPrice(uint256 roundsAgo, int32 value, int8 decimals) public {
        uint32 currentRoundId =
            uint32((block.timestamp - firstVotingRoundStartTs) / votingEpochDurationSeconds);
        roundsAgo = bound(roundsAgo, 0, uint256(currentRoundId) + 100 days / votingEpochDurationSeconds);
        uint32 round = roundsAgo > currentRoundId ? 0 : currentRoundId - uint32(roundsAgo);

        uint256 timestamp = uint256(round) * votingEpochDurationSeconds + firstVotingRoundStartTs;
        bool isStale = timestamp < block.timestamp - DEFAULT_STALE_PERIOD;
        bool isInvalidValue = value <= 0;

        IFtsoFeedPublisher.Feed memory feed = IFtsoFeedPublisher.Feed({
            votingRoundId: round,
            id: FEED_ID,
            value: value,
            turnoutBIPS: 10000,
            decimals: decimals
        });
        vm.mockCall(
            feedPublisher, abi.encodeWithSelector(IFtsoFeedPublisher.getCurrentFeed.selector, FEED_ID), abi.encode(feed)
        );

        callCount++;
        (bool success,) = ftsov2.staticcall(abi.encodeWithSignature("getPrice(bytes21)", FEED_ID));
        if (success) {
            if (isStale || isInvalidValue) {
                everAcceptedInvalidOrStalePrice = true;
            }
        } else {
            revertCount++;
        }
    }
}

/// @notice FTSOv2.getPrice() enforces `revert StaleRate()` when the feed's
/// voting-round-derived timestamp is older than the configured stale period,
/// and `revert InvalidPrice()` when the feed value isn't positive. This fuzzes
/// both against the REAL, unmodified, live-registry-wired contract and asserts
/// neither guard is ever bypassed.
contract SparkDex_FTSOv2_InvariantTest is Test {
    address ftsov2;
    Handler handler;

    function setUp() public {
        vm.createSelectFork(FLARE_MAINNET_RPC);
        address addressStorage = deployCode("AddressStorage.sol:AddressStorage");
        ftsov2 = deployCode("FTSOv2.sol:FTSOv2", abi.encode(addressStorage));
        handler = new Handler(ftsov2);
        targetContract(address(handler));
        // Restrict the invariant fuzzer to a single, already-known sender. Against
        // a forked live chain, Foundry's default random-sender-per-call behavior
        // means an RPC account lookup for a brand new address on nearly every
        // call, which blows through the public RPC's rate limit almost
        // immediately. The property under test is about the fuzzed PRICE DATA
        // (via vm.mockCall), not about which address calls getPrice(), so fixing
        // the sender costs nothing real.
        targetSender(address(this));
    }

    /// forge-config: default.invariant.runs = 50
    /// forge-config: default.invariant.depth = 20
    function invariant_NeverAcceptsInvalidOrStalePrice() public view {
        assertFalse(
            handler.everAcceptedInvalidOrStalePrice(), "SparkDEX's FTSOv2.getPrice() accepted a stale or invalid price"
        );
    }
}

/// @notice Sanity check that the invariant above isn't vacuously passing because
/// every getPrice() call happens to fail. Confirms a real successful fresh-price
/// read, a real StaleRate() revert, and a real InvalidPrice() revert each occur
/// against the actual live-forked contract.
contract SparkDex_FTSOv2_DiagnosticTest is Test {
    address ftsov2;
    address feedPublisher;

    function setUp() public {
        vm.createSelectFork(FLARE_MAINNET_RPC);
        address addressStorage = deployCode("AddressStorage.sol:AddressStorage");
        ftsov2 = deployCode("FTSOv2.sol:FTSOv2", abi.encode(addressStorage));
        (, bytes memory fp) = ftsov2.staticcall(abi.encodeWithSignature("ftsoFeedPublisher()"));
        feedPublisher = abi.decode(fp, (address));
    }

    function _mockFeed(uint32 round, int32 value, int8 decimals) internal {
        IFtsoFeedPublisher.Feed memory feed = IFtsoFeedPublisher.Feed({
            votingRoundId: round,
            id: FEED_ID,
            value: value,
            turnoutBIPS: 10000,
            decimals: decimals
        });
        vm.mockCall(
            feedPublisher, abi.encodeWithSelector(IFtsoFeedPublisher.getCurrentFeed.selector, FEED_ID), abi.encode(feed)
        );
    }

    function _currentRound() internal returns (uint32) {
        (, bytes memory ts) = ftsov2.staticcall(abi.encodeWithSignature("firstVotingRoundStartTs()"));
        (, bytes memory dur) = ftsov2.staticcall(abi.encodeWithSignature("votingEpochDurationSeconds()"));
        return uint32((block.timestamp - abi.decode(ts, (uint32))) / abi.decode(dur, (uint8)));
    }

    function test_FreshPriceSucceeds() public {
        _mockFeed(_currentRound(), 12345, 5);
        (bool success, bytes memory data) = ftsov2.staticcall(abi.encodeWithSignature("getPrice(bytes21)", FEED_ID));
        assertTrue(success, "fresh price should succeed");
        console2.log("price:", abi.decode(data, (uint256)));
    }

    function test_StaleRoundReverts() public {
        _mockFeed(0, 12345, 5); // round 0 -> timestamp = firstVotingRoundStartTs, ancient
        (bool success, bytes memory data) = ftsov2.staticcall(abi.encodeWithSignature("getPrice(bytes21)", FEED_ID));
        assertFalse(success, "ancient round should revert");
        assertEq(bytes4(data), bytes4(keccak256("StaleRate()")));
    }

    function test_InvalidValueReverts() public {
        _mockFeed(_currentRound(), 0, 5); // value <= 0
        (bool success, bytes memory data) = ftsov2.staticcall(abi.encodeWithSignature("getPrice(bytes21)", FEED_ID));
        assertFalse(success, "non-positive value should revert");
        assertEq(bytes4(data), bytes4(keccak256("InvalidPrice()")));
    }
}
