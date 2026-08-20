// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

// No-op import, same technique as test/integration/kinetic/_CompileTarget.sol:
// pulls FTSOv2.sol (and AddressStorage/Governable) into its own build group so
// `forge build` produces an artifact for it, without creating a direct import
// edge from this repo's >=0.8.19 <0.9 files into SparkDEX's exactly-pinned
// 0.8.22 file - Foundry's version-compatibility check treats that mix as
// incompatible even where the ranges numerically overlap. Deployed from the
// test via forge-std's `deployCode` instead.
import "sparkdex/utils/FTSOv2.sol";
