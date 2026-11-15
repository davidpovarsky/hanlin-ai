# L durability correction after independent review of 053d1535

[איתן | ARCH+DEV] [MAIN_SESSION], primary `01a1dc79-6761-7463-a196-34771f7929bd`; active task L `1219656771460030`.
Review source: HQ `docs/hanlin/qa/Split_Durability_053d1535_2026-11-15.md`. This supersedes the affected recovery/budget/evidence claims in the previous author handoff, not the production acceptance gates.

## P2 recovery direction

The prior implementation selected `before` in memory and wrote its destination/journal before checkpointing. A restart during those writes could see the old apply intent and choose its `after`. That finding is accepted and corrected.

`SplitMigrationIntent` now carries an optional, durable `recoveryTarget`. Existing v1 intents decode with no selected target. Recovery validates known source/before/after state, preflights its entire write set, and **persists the selected target before changing destination or journal**. An existing selection wins over a later caller's contrary/default policy until it is checkpointed. The final checkpoint has identical before/after journals; subsequent recovery returns it without rewriting or changing direction. A new explicit apply/rollback is a distinct subsequent transaction.

The four injected recovery boundaries are after decision, destination, journal and checkpoint. Tests vary original apply/rollback, selected finish/restore and direct-next-transition versus explicit reopened recovery. They compare the entire **before journal of the next transaction**, not merely its final output, which could hide a reversal. Separate processes resume fixtures left at every restore recovery boundary for both original operation kinds, inspect the next transaction's before state, settle that new transaction and verify original source bytes.

A process interrupted before the first decision is durably stored has no acknowledged durable choice yet. Existing atomic-write and stale-lock limitations remain; this is not power-loss/fsync or production lock-liveness proof.

## P2 encoded slot budget

`SplitFixtureStore.maximumSlotBytes` remains exactly **16,777,216 encoded bytes**. `encodeBounded` uses the actual sorted-key JSON encoder and rejects an oversized buffer before any atomic replacement. Every slot uses this path; reads check both file size and bytes actually read.

Initialization preflights source, destination and journal before creating the first slot. A new transition preflights its intent, both possible durable recovery directions, their destination/journal and checkpoint representations before persisting its intent. Recovery preflights the chosen decision/destination/journal/checkpoint before replacing the old intent. Oversized legacy intent expansion therefore fails with old state intact rather than making a previously readable fixture unreadable.

Boundary cases exercise exactly-at-limit and one-byte-over ASCII JSON, multi-byte UTF-8 where character count is smaller than byte count, every slot's old byte preservation/readback, an exact-limit initial journal, one-byte-over initialization with no partial slots, expanded transaction intents, and near-limit recovery decision/checkpoint writes. The result artifact retains actual encoded byte measurements. No string-count estimate stands in for encoded size.

## Execution lineage retained for review

`py -3 Scripts/ProductSplit/run_portable.py --suite correction --rebuild-canonical` rebuilt the required real portable canonical inputs once. The unused SwiftPM `Bundle.module` resource helper remains excluded without a replacement stub. The runner did not run unrelated initial 55-case/inventory/Apple suites for a larger count.

The correction run includes the affected/unproven durable group and new regressions. Canonical reuse on a later correction attempt requires matching compiler/version/flags/source and dependency descriptors, hashes of every recorded library/module/import artifact, and hashes of the originating raw compile logs. Old source-only stamp files are not accepted as lineage.

Evidence includes:

- Actual verbose driver/frontend/link argument vectors, cwd and exit codes; no environment/credential dump.
- Byte-for-byte raw compiler stdout/stderr and test/child-process stdout/stderr, plus a timestamped command/spawn transcript.
- Compiler/Swift frontend executable digests, canonical source digests, imported artifact dependencies and resulting DLL/module/import-library digests.
- Per-test-executable source inputs captured before compilation and checked unchanged afterward, link event, linked canonical hashes and binary digest.
- Hash-linked retained module/binary provenance JSON and a raw-evidence file manifest; final source hashes and dirty commit-base identity are explicit.

`durable-correction-results.json` is the current result and points to `evidence/durability-fix/<run>/manifest.json`. The local binaries/modules stay in the owned ignored `.build` directory; their immutable digest/provenance/log records are retained in Git. Raw log files have a narrowly scoped byte-preserving attribute. These are actual author execution records for QA to inspect, not a claim that QA independently reran the suite.

One initial correction compile exposed a missing `Sendable` conformance on the immutable fixture slot enum; it was added without unsafe isolation suppression. That failed attempt and its diagnostic remain in the raw evidence. No failed attempt is labeled PASS. The final report identifies precisely which canonical outputs were freshly compiled and which later reused those verified output/origin hashes.

Final executed result: **76/76 EXECUTED_PASS** (30 durable cases reproduced with retained lineage, 38 new Swift regression cases and 8 fresh-process recovery continuations). Canonical contracts/catalog/request sources were freshly compiled in the first correction attempt; the final attempt reused only their verified output and originating-log hashes. The final source, binary, imported artifact, runner/compiler, provenance-manifest and raw-log hashes were checked against actual retained files. No source changed after this passing run. Actual measurements include 16,777,216-byte accepted JSON, 16,777,217-byte rejected JSON, and a 16,777,242-byte rejected recovery-decision expansion. The final report and raw evidence retain the exact values and commands, rather than treating the earlier 30-PASS JSON as independent proof.

## Scope and remaining gates

Only split-owned leaf/fixture sources/tests, local runner/provenance and this evidence changed. Tomer's app/target/manifest/registered-test/integration-report paths, runtime/authority policies and production stores were not edited. The same three fixture adapters remain excluded from production membership. No `.all`/`.allowed` policy or new permission engine was introduced.

Authenticated live transport/store, entitlement binding, actual foreground execution/return, real data migration, Apple SDK/app/device validation and H/I acceptance remain open. No CI, signing, release, main merge or production data action occurred. The corrected source tranche requires the requested focused QA re-review; L is not completed wholesale.
