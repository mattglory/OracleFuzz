// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9;

import {IPaymentVerification} from "../../src/interfaces/fdc/IPaymentVerification.sol";
import {IPayment} from "../../src/interfaces/fdc/IPayment.sol";

/// @title PaymentCreditor
/// @notice Toy example: an on-ramp style contract that credits a balance once an
/// external-chain payment is proven via FDC. Structurally identical to what a
/// bridge, off-ramp, or RWA settlement contract on Flare would write against the
/// real `IPaymentVerification`. This CORRECT version checks both that the proof
/// verifies AND that the attestation isn't old enough to be a stale/replayed
/// fact by the time it's used - see PaymentCreditorBuggy for the omission this
/// is meant to catch.
contract PaymentCreditor {
    IPaymentVerification public immutable fdc;
    uint64 public immutable maxAttestationAge;

    mapping(bytes32 => bool) public processed;
    mapping(bytes32 => uint256) public credited;

    error VerificationFailed();
    error StaleAttestation(uint64 age, uint64 maxAge);
    error AlreadyProcessed(bytes32 transactionId);

    constructor(IPaymentVerification _fdc, uint64 _maxAttestationAge) {
        fdc = _fdc;
        maxAttestationAge = _maxAttestationAge;
    }

    function creditPayment(IPayment.Proof calldata proof) external returns (uint256) {
        bytes32 txId = proof.data.requestBody.transactionId;
        if (processed[txId]) revert AlreadyProcessed(txId);

        if (!fdc.verifyPayment(proof)) revert VerificationFailed();

        uint64 age = uint64(block.timestamp) - proof.data.lowestUsedTimestamp;
        if (age > maxAttestationAge) revert StaleAttestation(age, maxAttestationAge);

        processed[txId] = true;
        uint256 amount = uint256(int256(proof.data.responseBody.receivedAmount));
        credited[proof.data.responseBody.receivingAddressHash] += amount;
        return amount;
    }
}
