// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9;

import {IPaymentVerification} from "../../src/interfaces/fdc/IPaymentVerification.sol";
import {IPayment} from "../../src/interfaces/fdc/IPayment.sol";

/// @title PaymentCreditorBuggy
/// @notice Same as PaymentCreditor, but missing the attestation-freshness check -
/// a realistic omission (`lowestUsedTimestamp` is simply never inspected once the
/// proof cryptographically verifies). Used by PaymentCreditor.t.sol to
/// demonstrate the fuzz campaign actually finds this class of bug rather than
/// just exercising the happy path. Note: still checks verify() and still guards
/// against replay via `processed` - it isolates the ONE omission under test.
contract PaymentCreditorBuggy {
    IPaymentVerification public immutable fdc;

    mapping(bytes32 => bool) public processed;
    mapping(bytes32 => uint256) public credited;

    error VerificationFailed();
    error AlreadyProcessed(bytes32 transactionId);

    constructor(IPaymentVerification _fdc) {
        fdc = _fdc;
    }

    function creditPayment(IPayment.Proof calldata proof) external returns (uint256) {
        bytes32 txId = proof.data.requestBody.transactionId;
        if (processed[txId]) revert AlreadyProcessed(txId);

        if (!fdc.verifyPayment(proof)) revert VerificationFailed();

        processed[txId] = true;
        uint256 amount = uint256(int256(proof.data.responseBody.receivedAmount));
        credited[proof.data.responseBody.receivingAddressHash] += amount;
        return amount;
    }
}
