// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9;

import {Test} from "forge-std/Test.sol";
import {FdcVerificationChaosMock} from "../../src/mocks/FdcVerificationChaosMock.sol";
import {IPayment} from "../../src/interfaces/fdc/IPayment.sol";
import {PaymentCreditor} from "./PaymentCreditor.sol";
import {PaymentCreditorBuggy} from "./PaymentCreditorBuggy.sol";

uint64 constant MAX_ATTESTATION_AGE = 3600; // 1 hour, matches both consumers' threshold below

/// @title Handler
/// @notice Drives the FDC chaos mock's failure-mode surface (verification result,
/// forced revert is exercised separately, attestation aging via warp) against a
/// target payment consumer, and records whether it was ever credited off the back
/// of an attestation that was either unverified or stale at call time.
contract Handler is Test {
    FdcVerificationChaosMock public mock;
    address public target; // either the correct or the buggy consumer

    uint64 public currentAttestationTimestamp;
    bool public everCreditedInvalidOrStale;
    uint256 public callCount;
    uint256 public revertCount;

    constructor(FdcVerificationChaosMock _mock, address _target) {
        mock = _mock;
        target = _target;
        currentAttestationTimestamp = uint64(block.timestamp);
    }

    function newAttestation() public {
        currentAttestationTimestamp = uint64(block.timestamp);
    }

    function setVerifyResult(bool result) public {
        mock.setVerifyResult(result);
    }

    function warp(uint256 secondsForward) public {
        secondsForward = bound(secondsForward, 0, 30 days);
        vm.warp(block.timestamp + secondsForward);
    }

    /// @notice Constructs a payment proof using the CURRENT chaos state (whatever
    /// the mock's verify() is set to return, however old currentAttestationTimestamp
    /// has become) and calls the target consumer, checking - from OUTSIDE the
    /// consumer - whether the attestation it must have used was invalid or stale
    /// at call time. This is the ground-truth check; it does not trust the
    /// consumer's own revert behavior.
    function queryCreditor(uint256 nonceSeed, uint256 amountSeed) public {
        bool verifyWouldSucceed = mock.verifyResult();
        bool isStale = (block.timestamp - currentAttestationTimestamp) > MAX_ATTESTATION_AGE;

        bytes32 txId = keccak256(abi.encode("tx", nonceSeed, block.timestamp, callCount));
        bytes32 receiver = keccak256(abi.encode("receiver", nonceSeed));
        int256 amount = int256(bound(amountSeed, 0, 1e30));

        IPayment.Proof memory proof;
        proof.data.attestationType = bytes32("Payment");
        proof.data.sourceId = bytes32("BTC");
        proof.data.votingRound = 1;
        proof.data.lowestUsedTimestamp = currentAttestationTimestamp;
        proof.data.requestBody.transactionId = txId;
        proof.data.responseBody.receivingAddressHash = receiver;
        proof.data.responseBody.receivedAmount = amount;
        proof.data.responseBody.status = 0;

        callCount++;
        try PaymentCreditor(target).creditPayment(proof) returns (uint256) {
            if (!verifyWouldSucceed || isStale) {
                everCreditedInvalidOrStale = true;
            }
        } catch {
            revertCount++;
        }
    }
}

/// @notice The CORRECT consumer must never credit a payment from an attestation
/// that failed verification or has aged past maxAttestationAge - the fuzzer
/// should never find a counterexample.
contract PaymentCreditor_Correct_InvariantTest is Test {
    FdcVerificationChaosMock mock;
    PaymentCreditor consumer;
    Handler handler;

    function setUp() public {
        mock = new FdcVerificationChaosMock();
        consumer = new PaymentCreditor(mock, MAX_ATTESTATION_AGE);
        handler = new Handler(mock, address(consumer));
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 500
    /// forge-config: default.invariant.depth = 50
    function invariant_NeverCreditsInvalidOrStaleAttestation() public view {
        assertFalse(
            handler.everCreditedInvalidOrStale(), "correct consumer credited an invalid/stale payment attestation"
        );
    }
}

/// @notice The BUGGY consumer (no freshness check) SHOULD fail this invariant -
/// this test is expected to fail, and its failure is the proof the harness works.
/// Run with: forge test --match-contract PaymentCreditor_Buggy -vv
contract PaymentCreditor_Buggy_InvariantTest is Test {
    FdcVerificationChaosMock mock;
    PaymentCreditorBuggy consumer;
    Handler handler;

    function setUp() public {
        mock = new FdcVerificationChaosMock();
        consumer = new PaymentCreditorBuggy(mock);
        handler = new Handler(mock, address(consumer));
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 500
    /// forge-config: default.invariant.depth = 50
    function invariant_NeverCreditsInvalidOrStaleAttestation() public view {
        assertFalse(
            handler.everCreditedInvalidOrStale(),
            "buggy consumer credited an invalid/stale payment attestation (expected - proves the harness catches it)"
        );
    }
}
