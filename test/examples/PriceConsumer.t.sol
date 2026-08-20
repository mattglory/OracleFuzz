// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9;

import {Test} from "forge-std/Test.sol";
import {FtsoV2ChaosMock} from "../../src/mocks/FtsoV2ChaosMock.sol";
import {PriceConsumer} from "./PriceConsumer.sol";
import {PriceConsumerBuggy} from "./PriceConsumerBuggy.sol";

bytes21 constant FEED_ID = bytes21(uint168(uint256(keccak256("FLR/USD"))));
uint64 constant MAX_STALENESS = 300; // 5 minutes, matches PriceConsumer's threshold below

/// @title Handler
/// @notice Drives the chaos mock's failure-mode surface (staleness, price jumps,
/// forced reverts) against a target consumer, and records whether the consumer ever
/// returned a value computed from a stale price - which is the property under test.
contract Handler is Test {
    FtsoV2ChaosMock public mock;
    address public target; // either the correct or the buggy consumer

    bool public everReturnedStaleValue;
    uint256 public callCount;
    uint256 public revertCount;

    constructor(FtsoV2ChaosMock _mock, address _target) {
        mock = _mock;
        target = _target;
        mock.setFeedData(FEED_ID, 100_000, 5); // arbitrary sane starting price
    }

    function updatePrice(int32 newValue, int8 decimals) public {
        newValue = int32(uint32(bound(uint256(uint32(newValue)), 1, uint256(uint32(type(int32).max)))));
        decimals = int8(uint8(bound(uint256(uint8(decimals)), 0, 18)));
        mock.setFeedData(FEED_ID, newValue, decimals);
    }

    function jumpPrice(uint256 bps, bool up) public {
        bps = bound(bps, 0, 50000); // up to +/-500% in one jump
        mock.jumpPrice(FEED_ID, bps, up);
    }

    function goStale(uint64 secondsStale) public {
        secondsStale = uint64(bound(secondsStale, 0, 3650 days));
        mock.setStale(FEED_ID, secondsStale);
    }

    function warp(uint256 secondsForward) public {
        secondsForward = bound(secondsForward, 0, 30 days);
        vm.warp(block.timestamp + secondsForward);
    }

    /// @notice Calls the target consumer and checks, from OUTSIDE the consumer,
    /// whether the price it must have used was stale at call time. This is the
    /// ground-truth check - it does not trust the consumer's own revert behavior.
    function queryConsumer(uint256 amount) public {
        (,, uint64 tsBefore) = mock.getFeedById(FEED_ID);
        bool wasStaleAtCallTime = (block.timestamp - tsBefore) > MAX_STALENESS;

        callCount++;
        try PriceConsumer(target).collateralValue(amount) returns (uint256) {
            if (wasStaleAtCallTime) {
                everReturnedStaleValue = true;
            }
        } catch {
            revertCount++;
        }
    }
}

/// @notice The CORRECT consumer must never return a value from a stale price -
/// the fuzzer should never find a counterexample.
contract PriceConsumer_Correct_InvariantTest is Test {
    FtsoV2ChaosMock mock;
    PriceConsumer consumer;
    Handler handler;

    function setUp() public {
        mock = new FtsoV2ChaosMock();
        consumer = new PriceConsumer(mock, FEED_ID, MAX_STALENESS);
        handler = new Handler(mock, address(consumer));
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 500
    /// forge-config: default.invariant.depth = 50
    function invariant_NeverUsesStalePrice() public view {
        assertFalse(handler.everReturnedStaleValue(), "correct consumer accepted a stale price");
    }
}

/// @notice The BUGGY consumer (no staleness check) SHOULD fail this invariant -
/// this test is expected to fail, and its failure is the proof the harness works.
/// Run with: forge test --match-contract PriceConsumer_Buggy -vv
contract PriceConsumer_Buggy_InvariantTest is Test {
    FtsoV2ChaosMock mock;
    PriceConsumerBuggy consumer;
    Handler handler;

    function setUp() public {
        mock = new FtsoV2ChaosMock();
        consumer = new PriceConsumerBuggy(mock, FEED_ID);
        handler = new Handler(mock, address(consumer));
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 500
    /// forge-config: default.invariant.depth = 50
    function invariant_NeverUsesStalePrice() public view {
        assertFalse(handler.everReturnedStaleValue(), "buggy consumer accepted a stale price (expected - proves the harness catches it)");
    }
}
