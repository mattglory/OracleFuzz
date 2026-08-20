// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9;

import {IWeb2JsonVerification} from "../../src/interfaces/fdc/IWeb2JsonVerification.sol";
import {IWeb2Json} from "../../src/interfaces/fdc/IWeb2Json.sol";

/// @title Web2JsonDataConsumerBuggy
/// @notice Same as Web2JsonDataConsumer, but missing the round-monotonicity
/// check - a realistic omission (`votingRound` is simply never inspected once
/// the proof cryptographically verifies). Used by Web2JsonDataConsumer.t.sol to
/// demonstrate the fuzz campaign actually finds this class of bug: an old,
/// still-valid proof can be replayed to roll `latestValue` backward after newer
/// data has already been accepted.
contract Web2JsonDataConsumerBuggy {
    IWeb2JsonVerification public immutable fdc;

    uint256 public latestValue;

    error VerificationFailed();

    constructor(IWeb2JsonVerification _fdc) {
        fdc = _fdc;
    }

    function submitData(IWeb2Json.Proof calldata proof) external returns (uint256) {
        if (!fdc.verifyWeb2Json(proof)) revert VerificationFailed();

        uint256 value = abi.decode(proof.data.responseBody.abiEncodedData, (uint256));
        latestValue = value;
        return value;
    }
}
