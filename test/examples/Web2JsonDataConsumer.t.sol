// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9;

import {Test} from "forge-std/Test.sol";
import {FdcVerificationChaosMock} from "../../src/mocks/FdcVerificationChaosMock.sol";
import {IWeb2Json} from "../../src/interfaces/fdc/IWeb2Json.sol";
import {Web2JsonDataConsumer} from "./Web2JsonDataConsumer.sol";
import {Web2JsonDataConsumerBuggy} from "./Web2JsonDataConsumerBuggy.sol";

/// @title Handler
/// @notice Fuzzes FDC's "wrong round" failure mode: since verification is
/// stateless (no persistent "current attestation" the way FTSO has), the round
/// number lives entirely in the caller-supplied proof, so it's fuzzed directly
/// here rather than via a mock setter. Rounds are drawn from a deliberately
/// small range so replays of an already-seen round actually happen often within
/// a fuzz campaign, instead of a huge random space almost never colliding.
contract Handler is Test {
    FdcVerificationChaosMock public mock;
    address public target;

    uint64 public highestRoundEverAccepted; // ground truth, tracked externally
    bool public everAcceptedInvalidOrReplayedRound;
    uint256 public callCount;
    uint256 public revertCount;

    constructor(FdcVerificationChaosMock _mock, address _target) {
        mock = _mock;
        target = _target;
    }

    function setVerifyResult(bool result) public {
        mock.setVerifyResult(result);
    }

    /// @notice Submits a proof for a fuzzed round (small range, so replays of an
    /// already-accepted round are common) and a fuzzed data value, then checks -
    /// from OUTSIDE the consumer - whether it was ever accepted despite failing
    /// verification or replaying a round no newer than one already accepted.
    function submitData(uint256 roundSeed, uint256 valueSeed) public {
        uint64 round = uint64(bound(roundSeed, 1, 20));
        uint256 value = bound(valueSeed, 0, type(uint256).max);
        bool verifyWouldSucceed = mock.verifyResult();
        bool wouldBeReplay = round <= highestRoundEverAccepted;

        IWeb2Json.Proof memory proof;
        proof.data.attestationType = bytes32("Web2Json");
        proof.data.sourceId = bytes32("WEB2");
        proof.data.votingRound = round;
        proof.data.lowestUsedTimestamp = uint64(block.timestamp);
        proof.data.responseBody.abiEncodedData = abi.encode(value);

        callCount++;
        try Web2JsonDataConsumer(target).submitData(proof) returns (uint256) {
            if (!verifyWouldSucceed || wouldBeReplay) {
                everAcceptedInvalidOrReplayedRound = true;
            } else if (round > highestRoundEverAccepted) {
                highestRoundEverAccepted = round;
            }
        } catch {
            revertCount++;
        }
    }
}

/// @notice The CORRECT consumer must never accept a proof that fails
/// verification, nor one whose round doesn't exceed the highest round it has
/// already accepted - the fuzzer should never find a counterexample.
contract Web2JsonDataConsumer_Correct_InvariantTest is Test {
    FdcVerificationChaosMock mock;
    Web2JsonDataConsumer consumer;
    Handler handler;

    function setUp() public {
        mock = new FdcVerificationChaosMock();
        consumer = new Web2JsonDataConsumer(mock);
        handler = new Handler(mock, address(consumer));
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 500
    /// forge-config: default.invariant.depth = 50
    function invariant_NeverAcceptsInvalidOrReplayedRound() public view {
        assertFalse(
            handler.everAcceptedInvalidOrReplayedRound(),
            "correct consumer accepted an unverified proof or replayed an old round"
        );
    }
}

/// @notice The BUGGY consumer (no round check) SHOULD fail this invariant - this
/// test is expected to fail, and its failure is the proof the harness works.
/// Run with: forge test --match-contract Web2JsonDataConsumer_Buggy -vv
contract Web2JsonDataConsumer_Buggy_InvariantTest is Test {
    FdcVerificationChaosMock mock;
    Web2JsonDataConsumerBuggy consumer;
    Handler handler;

    function setUp() public {
        mock = new FdcVerificationChaosMock();
        consumer = new Web2JsonDataConsumerBuggy(mock);
        handler = new Handler(mock, address(consumer));
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 500
    /// forge-config: default.invariant.depth = 50
    function invariant_NeverAcceptsInvalidOrReplayedRound() public view {
        assertFalse(
            handler.everAcceptedInvalidOrReplayedRound(),
            "buggy consumer replayed an old round (expected - proves the harness catches it)"
        );
    }
}

/// @notice Sanity check that the invariant above isn't vacuously passing because
/// every submission happens to be rejected. Confirms a real accepted round, a
/// real rejected replay, and a real rejected failed-verification each occur.
contract Web2JsonDataConsumer_DiagnosticTest is Test {
    FdcVerificationChaosMock mock;
    Web2JsonDataConsumer consumer;

    function setUp() public {
        mock = new FdcVerificationChaosMock();
        consumer = new Web2JsonDataConsumer(mock);
    }

    function _proof(uint64 round, uint256 value) internal view returns (IWeb2Json.Proof memory proof) {
        proof.data.attestationType = bytes32("Web2Json");
        proof.data.sourceId = bytes32("WEB2");
        proof.data.votingRound = round;
        proof.data.lowestUsedTimestamp = uint64(block.timestamp);
        proof.data.responseBody.abiEncodedData = abi.encode(value);
    }

    function test_AcceptsNewerRound() public {
        uint256 v = consumer.submitData(_proof(5, 42));
        assertEq(v, 42);
        assertEq(consumer.lastAcceptedRound(), 5);
    }

    function test_RejectsReplayedRound() public {
        consumer.submitData(_proof(5, 42));
        vm.expectRevert(abi.encodeWithSelector(Web2JsonDataConsumer.RoundNotNewer.selector, uint64(5), uint64(5)));
        consumer.submitData(_proof(5, 99));
    }

    function test_RejectsFailedVerification() public {
        mock.setVerifyResult(false);
        vm.expectRevert(Web2JsonDataConsumer.VerificationFailed.selector);
        consumer.submitData(_proof(1, 1));
    }
}
