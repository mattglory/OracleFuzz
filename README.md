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

## Roadmap

- **M1 (this prototype):** FTSO chaos-mock + invariant-template pattern, proven
  against a worked example.
- **M2:** FDC chaos-mock (`IFdcVerification` family — start with `IWeb2Json` and
  `IPayment`, the two most broadly used attestation types) with equivalent
  failure-mode injection (malformed proof, wrong round, stale attestation window).
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
