// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9;

import {IWeb2JsonVerification} from "../../src/interfaces/fdc/IWeb2JsonVerification.sol";
import {IWeb2Json} from "../../src/interfaces/fdc/IWeb2Json.sol";

/// @title Web2JsonDataConsumer
/// @notice Toy example: a contract that ingests an off-chain data point (e.g. a
/// score, an API-sourced value) via FDC's generic `IWeb2Json` attestation type
/// and stores the latest one. Unlike FTSO's persistent, push-style feed state,
/// FDC verification is stateless - `verify()` checks whatever proof the caller
/// hands it, with no notion of "current." That means a cryptographically valid
/// proof from an OLD voting round is just as verifiable as a fresh one, and a
/// consumer that only checks verification (not round recency) is exposed to a
/// replay: an attacker resubmitting an old-but-valid proof to roll accepted
/// state backward after newer data has already landed. This CORRECT version
/// rejects any proof whose round isn't strictly newer than the last one it
/// accepted - see Web2JsonDataConsumerBuggy for the omission this is meant to
/// catch.
contract Web2JsonDataConsumer {
    IWeb2JsonVerification public immutable fdc;

    uint64 public lastAcceptedRound;
    uint256 public latestValue;

    error VerificationFailed();
    error RoundNotNewer(uint64 proofRound, uint64 lastAccepted);

    constructor(IWeb2JsonVerification _fdc) {
        fdc = _fdc;
    }

    function submitData(IWeb2Json.Proof calldata proof) external returns (uint256) {
        if (!fdc.verifyWeb2Json(proof)) revert VerificationFailed();

        uint64 round = proof.data.votingRound;
        if (round <= lastAcceptedRound) revert RoundNotNewer(round, lastAcceptedRound);

        uint256 value = abi.decode(proof.data.responseBody.abiEncodedData, (uint256));
        lastAcceptedRound = round;
        latestValue = value;
        return value;
    }
}
