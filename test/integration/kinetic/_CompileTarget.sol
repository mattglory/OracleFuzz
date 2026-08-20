// SPDX-License-Identifier: MIT
pragma solidity 0.5.17;

// No-op import. Its only job is to pull ProtocolFTSOV3Oracle.sol (and its
// dependency tree) into the build graph so `forge build` produces an artifact
// for it. It's never referenced by the 0.8.x test file directly - see the
// version-mismatch note in KineticOracleFuzz.t.sol for why - and is instead
// deployed there via forge-std's `deployCode`.
import "kinetic/FTSO/ProtocolFTSOV3Oracle.sol";
