// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9;

import {IWeb2JsonVerification} from "../interfaces/fdc/IWeb2JsonVerification.sol";
import {IWeb2Json} from "../interfaces/fdc/IWeb2Json.sol";
import {IPaymentVerification} from "../interfaces/fdc/IPaymentVerification.sol";
import {IPayment} from "../interfaces/fdc/IPayment.sol";

/// @title FdcVerificationChaosMock
/// @notice Chaos-injectable stand-in for Flare's real FDC verification contract,
/// covering the two most broadly used attestation types (`IWeb2JsonVerification`,
/// `IPaymentVerification`). Real Merkle-proof checking is Flare protocol
/// infrastructure and out of scope to reimplement here - what actually needs
/// fuzzing is how a CONSUMING contract reacts when verification fails or the
/// attestation itself is old, which mirrors exactly what M1's FtsoV2ChaosMock
/// does for price feeds: it's not the oracle's internal math under test, it's
/// the caller's handling of a result it can't fully control.
/// @dev Every published Flare FDC mock the ecosystem currently has (the official
/// periphery package included) implements the happy path only: construct a
/// proof, verify() returns true. None of them make it cheap to simulate a
/// failed/malformed proof or a genuinely stale attestation being replayed - the
/// two failure modes that actually matter for a contract crediting real value
/// off the back of an attestation.
contract FdcVerificationChaosMock is IWeb2JsonVerification, IPaymentVerification {
    /// @notice What verify() returns when not forced to revert. Chaos: flip this
    /// to false to simulate a malformed/unverifiable proof.
    bool public verifyResult = true;

    /// @notice If true, every verify() call reverts - simulates the FDC
    /// verification contract itself being unavailable (mid-outage, paused).
    bool public forceRevert;

    error VerificationForcedRevert();

    function setVerifyResult(bool result) external {
        verifyResult = result;
    }

    function setForceRevert(bool shouldRevert) external {
        forceRevert = shouldRevert;
    }

    function verifyWeb2Json(IWeb2Json.Proof calldata) external view override returns (bool _proved) {
        if (forceRevert) revert VerificationForcedRevert();
        return verifyResult;
    }

    function verifyPayment(IPayment.Proof calldata) external view override returns (bool _proved) {
        if (forceRevert) revert VerificationForcedRevert();
        return verifyResult;
    }
}
