# Flare Grants Program — Application Draft

Fields marked **[YOU FILL IN]** need your own input — I don't have this information
and won't guess it. Everything else is drafted from the validated research and
working prototype in this repo.

---

### Project Name
**OracleFuzz** (working name — repo is currently `flare-oracle-fuzz`; rename either
the project or the repo to match before submitting, your call)

### Contact First Name / Last Name
**[YOU FILL IN]**

### Email
mattglory14@gmail.com (confirm this is the one you want on file — it's what I have
from this session's context, not something you told me directly)

### Links
- GitHub: **[push the repo to a public GitHub URL and put it here — it's currently
  only local, at `scratchpad/flare-oracle-fuzz`]**
- Website / pitch deck / demo / LinkedIn: **[YOU FILL IN, or leave blank — a
  dev-tooling grant from a solo builder doesn't need these to be credible; the
  working repo carries the weight]**

### Project Description

> OracleFuzz is a Foundry testing library that lets Flare builders fuzz-test their
> protocols against realistic FTSO and FDC failure modes — stale price feeds,
> extreme single-block price jumps, oracle-system reverts, and failed FDC
> attestations — instead of only ever testing the happy path.
>
> Every FTSO/FDC-consuming project on Flare today writes its own one-off mock:
> set a value, read it back. That covers normal operation but not the failure
> modes that actually cause DeFi incidents — a stale feed is the single most
> common root cause of oracle-related exploits industry-wide, and it's exactly
> the case a "set value, read value" mock can't exercise.
>
> The M1 prototype is built and working: a full drop-in implementation of Flare's
> real `FtsoV2Interface` with a configurable chaos-injection surface, proven
> against a worked example — two structurally identical "price my collateral"
> contracts, one correct and one with a missing staleness check. A 25,000-call
> Foundry invariant campaign passes clean against the correct contract and
> automatically finds and shrinks a minimal failing case against the buggy one.
> That's the actual value proposition demonstrated in code, not just proposed.

### Legal Entity & Domicile
**[YOU FILL IN]** — if you're applying as an individual rather than through a
registered entity, say so plainly; Flare's form doesn't require an LLC/corp to apply.

### Unique Traits

> Verified before building: Flare's own official `flare-foundry-periphery-package`
> contains zero fuzzing or invariant-testing utilities anywhere in the repo — only
> interfaces. Individual live protocols (e.g. CreditGate, a confidential lending
> protocol on Flare) have built their own internal FTSO/FDC mocks, but explicitly
> as project-specific fixtures, never published for reuse. The `Thanas Flare
> Builders Toolkit` — the closest existing ecosystem project by name — is
> documentation and AI-assistant prompts, and explicitly states it does not include
> mock contracts or fuzzing utilities for oracle failure scenarios.
>
> OracleFuzz is the first published, installable library that treats oracle
> *failure* as the thing under test, not an afterthought bolted onto a happy-path
> mock.

### Flare Ecosystem Value Add

> Oracle-consumption bugs are the highest-leverage bug class in DeFi — one missing
> staleness check can drain an entire protocol. Every current and future Flare
> protocol that touches FTSO or FDC (lending, perps, vaults, RWA products) is
> exposed to this class of bug today, with no shared tooling to catch it before
> mainnet. OracleFuzz turns "does my protocol handle a stale/manipulated/failed
> oracle correctly" from a manual audit question into an automated Foundry
> invariant test any builder can add to their existing suite in an afternoon.
> Lower the cost of catching this bug class ecosystem-wide, not just for one
> protocol.

### Growth Strategy

> - Publish as a standard `forge install`-able package (README, NatSpec, semver)
>   immediately after M2, not held back to a big-bang launch.
> - Direct outreach to existing Flare DeFi teams (SparkDEX, Kinetic, RainDEX-style
>   protocols) once FDC coverage (M2) lands — these teams already have FTSO/FDC
>   integration code today that this can be pointed at directly.
> - Write up the "correct vs. buggy consumer" demo as a short technical post —
>   it's a concrete, shareable proof point, not an abstract pitch.
> - Propose inclusion/reference in Flare's own developer docs and the Foundry
>   starter kit as the recommended testing pattern for oracle-consuming contracts.

### Flare Native Protocol Integrations

> FTSO (v2) and FDC. Both are the direct subject of the library, not a peripheral
> integration.

### Milestones

> Costs and timelines below are a **proposed starting structure** — adjust to your
> actual rate/availability before submitting; these are placeholders reflecting
> reasonable solo-builder scope, not a number I'm authorized to commit you to.

| # | Milestone | Deliverable | Timeline | Cost |
|---|---|---|---|---|
| 1 | FTSO chaos-mock (prototype complete) | `FtsoV2ChaosMock.sol` + worked correct-vs-buggy invariant demo, proven passing/failing as intended | Complete (2 weeks) | $4,400 |
| 2 | FDC chaos-mock | Mock covering `IWeb2JsonVerification` and `IPaymentVerification` (the two most broadly used FDC attestation types) with equivalent failure injection: malformed proof, wrong round, stale attestation window | 3 weeks | $6,600 |
| 3 | Package publication + docs | Versioned `forge install`-able release, full README/NatSpec, a second worked example against a more realistic primitive (small lending or perps-style contract) | 2 weeks | $5,100 |
| 4 | Ecosystem adoption push | Direct outreach + integration support for 1–2 existing Flare protocols adopting the library in their own test suites; iterate on API based on real feedback | 4 weeks | $8,000 |
| 5 | Invariant template library | Reusable, documented invariant assertion templates (e.g. "never accept a price older than N seconds," "never proceed on a failed attestation") builders can import directly rather than writing from scratch | 3 weeks | $5,900 |

**Total ask: $30,000** across 5 milestones / ~14 weeks (~$2,140/week — a more
realistic market rate for security-focused smart contract work than the original
draft, while staying proportionate to the stated scope; costs scaled uniformly
across milestones rather than inflating one line item, so the relative weighting
of each milestone is unchanged from the original draft).

### Other Integrations
None required — this is a standalone Foundry library with no external service
dependencies beyond Flare's own oracle contracts.

### Other Partnerships
None yet. Open to conversations with Flare ecosystem teams once M2 (FDC coverage)
is public — premature to claim partnerships that don't exist yet.

### How did you find the Flare grants program?
**[YOU FILL IN]**

### Other Requirements
> Technical point of contact for FDC integration questions during M2 (the
> attestation-type surface is broad; guidance on which types the Grants Committee
> considers highest-priority for ecosystem coverage would sharpen scope). Optional:
> a listing/reference in Flare's official dev docs once M3 ships, to support the
> adoption goal in the growth strategy above.

### Can you commit to developing and supporting this project on Flare for at least 1 year?
**[YOU FILL IN — this is your commitment to make, not mine.]**
