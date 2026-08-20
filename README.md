# flare-oracle-fuzz

A Foundry library of "chaos mocks" for Flare's enshrined oracles (FTSO, FDC), built
for fuzz/invariant testing — not just unit testing.

## The gap this fills

Every Flare-based protocol that consumes FTSO price feeds or FDC attestations
currently writes its own one-off mock for testing: set a value, read it back. That
covers the happy path. It does not cover the failure modes that actually cause
incidents in production:

- a feed going **stale** (the oracle stops updating, but the last value still reads
  fine — the single most common class of oracle bug)
- a feed **jumping** by an extreme amount in one update (real crash or manipulation)
- the oracle system **reverting entirely** (partial outage, one feed down)
- `FeedData.decimals` being genuinely **negative** (allowed by the real FtsoV2
  interface; routinely mishandled in normalization math)
- an FDC attestation **failing verification** (malformed proof, wrong Merkle root)

Checked before building this: Flare's own official
[`flare-foundry-periphery-package`](https://github.com/flare-foundation/flare-foundry-periphery-package)
ships interfaces only — zero fuzzing or invariant-testing utilities anywhere in the
repo. Individual live protocols (e.g. CreditGate) have built their own internal
`MockFtsoV2`/`MockFdcVerification` mocks, but explicitly as project-specific test
fixtures, not published for reuse. Nobody has packaged this as installable
infrastructure other builders can `forge install` and extend.

## What's here (M1 prototype)

- `src/mocks/FtsoV2ChaosMock.sol` — a full, drop-in implementation of Flare's
  `FtsoV2Interface` with a chaos-injection surface: `setStale`, `jumpPrice`,
  `setForceRevert`, configurable per-feed read fees, and a controllable
  `verifyFeedData` result (no real Merkle proof construction needed in tests).
- `test/examples/` — a worked demonstration: two structurally-identical "value my
  collateral" consumer contracts (`PriceConsumer`, correct; `PriceConsumerBuggy`,
  missing its staleness check) driven by the same fuzzing `Handler`, proving the
  mock actually catches the bug class it targets:

  ```
  PriceConsumer_Correct_InvariantTest  [PASS]  (runs: 500, calls: 25000, reverts: 0)
  PriceConsumer_Buggy_InvariantTest    [FAIL]  shrunk to: warp(huge) -> queryConsumer(946)
  ```

  The buggy contract's failure is *expected* — it's the proof the harness works.
  Foundry's shrinker reduces the failing sequence to two calls automatically.

## Proven against a real, live Flare protocol

Not just the toy example above. `test/integration/kinetic/` points the same
chaos-injection approach at [Kinetic Market's `ProtocolFTSOV3Oracle`](https://github.com/kinetic-market/public-money-market-contracts/blob/main/contracts/FTSO/ProtocolFTSOV3Oracle.sol) -
the actual FTSO price oracle a live Flare money market uses to value collateral -
installed unmodified as a `forge install` dependency, not copied or rewritten.

```
Kinetic_FTSOV3Oracle_InvariantTest    [PASS]  invariant_NeverReturnsStalePrice()
                                                (runs: 500, calls: 25000, reverts: 0)
Kinetic_FTSOV3Oracle_DiagnosticTest   [PASS]  test_HappyPathReturnsRealPrice()
                                                (fresh price computed correctly: 1e18)
Kinetic_FTSOV3Oracle_DiagnosticTest   [PASS]  test_StalePriceReverts()
                                                (reverts with the real "stale price" reason string)
```

25,000 fuzzed calls across price updates, staleness injection, and time warps found
Kinetic's staleness guard holds - it's a genuine, useful validation of live ecosystem
code, not a hypothetical. (The two diagnostic tests exist to rule out a vacuous
pass: they confirm the harness actually reaches both a real successful price read
*and* a real staleness-triggered revert, not every call silently failing.)

Kinetic's contract is pinned to `pragma solidity 0.5.17`; this repo's own code is
`>=0.8.19`. The two can't share a single `solc` invocation, so the old contract is
compiled into its own artifact (via a same-version anchor import,
`test/integration/kinetic/_CompileTarget.sol`) and deployed into the 0.8.x test
through forge-std's `deployCode`, then driven entirely through low-level ABI calls
- the standard Foundry pattern for testing across incompatible pragma versions,
and useful on its own for anyone trying to point modern fuzzing tooling at an
older Compound-fork-style codebase.

## M2: FDC chaos-mock

- `src/mocks/FdcVerificationChaosMock.sol` — implements the real
  `IWeb2JsonVerification` and `IPaymentVerification` interfaces (vendored
  unmodified from Flare's official periphery package under
  `src/interfaces/fdc/`) with a chaos-injection surface: `setVerifyResult`
  (simulate a malformed/unverifiable proof) and `setForceRevert` (simulate the
  FDC verification contract itself being unavailable).
- `test/examples/PaymentCreditor.sol` / `PaymentCreditorBuggy.sol` — the same
  correct-vs-buggy pattern as M1, this time for an on-ramp-style contract that
  credits a balance off a verified `IPayment` attestation. The buggy version
  checks verification but not attestation freshness - a realistic omission:

  ```
  PaymentCreditor_Correct_InvariantTest  [PASS]  (runs: 500, calls: 25000, reverts: 0)
  PaymentCreditor_Buggy_InvariantTest    [FAIL]  shrunk to: warp(huge) -> queryCreditor(...)
  ```

- `test/examples/Web2JsonDataConsumer.sol` / `Web2JsonDataConsumerBuggy.sol` —
  the second worked example, against `IWeb2JsonVerification`. FDC verification
  is stateless (no persistent "current attestation" the way FTSO has), so a
  cryptographically valid proof from an OLD round is just as verifiable as a
  fresh one - the "wrong round" failure mode. The buggy version checks
  verification but never checks round recency, so an old-but-valid proof can be
  replayed to roll accepted state backward:

  ```
  Web2JsonDataConsumer_Correct_InvariantTest  [PASS]  (runs: 500, calls: 25000, reverts: 0)
  Web2JsonDataConsumer_Buggy_InvariantTest    [FAIL]  shrunk to a 2-call replay
  ```

## Roadmap

- **M1 (complete):** FTSO chaos-mock + invariant-template pattern, proven against
  a worked example, and against a real, live Flare protocol (Kinetic Market's
  `ProtocolFTSOV3Oracle` - see above).
- **M2 (complete):** FDC chaos-mock covering `IWeb2JsonVerification` and
  `IPaymentVerification`, with two worked examples covering both attestation-
  freshness failure modes named in the original scope: stale attestation window
  (`PaymentCreditor`) and wrong round / replay (`Web2JsonDataConsumer`).
- **M3:** Publish as a proper `forge install`-able package, worked integration
  against a second, more realistic example (a small lending or perps primitive),
  and documentation aimed at existing Flare ecosystem teams (SparkDEX, Kinetic,
  RainDEX-style protocols) to seed adoption.

## Try it

```
forge install
forge test --match-contract PriceConsumer_Correct_InvariantTest -vv
forge test --match-contract PriceConsumer_Buggy_InvariantTest -vv   # expected to fail
```
