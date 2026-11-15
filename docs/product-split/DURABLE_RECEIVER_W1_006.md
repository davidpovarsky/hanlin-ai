# L continuation: durable receiver and fixture recovery

[איתן | ARCH+DEV] [MAIN_SESSION], primary `01a1dc79-6761-7463-a196-34771f7929bd`.
Parent source tranche: `fb90d670e05f282405327466d07b1ff81a95addb`. Active task L `1219656771460030`; K assembly belongs to Tomer.

This continuation changes only owned leaf sources/tests, the portable runner and this evidence. It does not edit `HanlinMiniAppsApp/**`, `RegisteredIntegrationTests/**`, `INTEGRATION_W1_006.md`, manifests, existing authority/runtime or any app wiring. Initial W1-003 documentation describes the earlier snapshot; the receiver and fixture transaction gaps below are now implemented within this limited scope. App transport binding and production migration remain open.

## Receiver contract

`SplitDurableReceiver` consumes an untrusted reference and an injected `SplitTrustedRequestSource`. Without that source it throws `transportUnavailable` before creating a reservation. A live source must resolve a trusted, integrity-verified record; a URL, its asserted bundle ID, or a caller-supplied identity is not sufficient. Only synthetic test code implements that source in this branch.

`SplitReceiverContext` carries current canonical caller/app/package/session/chat/generation, route availability, online state and the existing host/OS authorization result. All origin fields are compared against the verified record. This is a consumer of current authority, not a new grant database or permission/sandbox engine. Personal-host `.all`/`.allowed` behavior is unchanged. The existing canonical request/launch adapter is reused; no Runtime API changed.

| Durable phase | Behavior on repeated delivery / restart |
| --- | --- |
| `reserved` | Repeated identical verified requests return the same reservation. One `start` can atomically persist a unique attempt before returning an execution permit. |
| `executing` | Another `start` fails; it never grants a second attempt. Loss of executor ownership/restart interruption marks `outcomeUnknown`, retaining the request and attempt. |
| `outcomeUnknown` | No automatic retry or conclusion that a side effect did not happen. A trusted canonical operation result must be reconciled with the same attempt and current authority. |
| `completed` | Stored outcome and exact original chat/session are replayed. Repeating the same completion is idempotent; a different outcome conflicts. |

Pre-execution cancellation, denial, offline and timeout produce a terminal failure without an attempt and retain exact origin correlation. Interruption after execution began stays unknown rather than reporting that cancellation undid an external action. A late ordinary completion cannot silently resolve unknown state; `reconcile` is explicit. Context/generation mismatches fail without replacing the stored record. Corrupt state is preserved and reported, never reset to an empty receiver.

`SplitReceiverPersistence.transaction` is the required atomic boundary: serialize read/validate/update/persist across instances/processes, authenticate and integrity-protect both request and lifecycle state, retain replay tombstones, and return only after persistence succeeds. The production implementation is **not provided**. Its security must cover phase/attempt/result transitions as well as the initial envelope; otherwise tampering could turn a completed request back into an executable reservation.

The receiver does not call the live broker. Integration may consume the successful `start` attempt only after the mailbox/entitlement binding and current authority/OS checks are real. The external side-effect gap remains: an executor may act, then die before its result is saved. This implementation exposes that uncertainty; it does not claim exactly-once side effects.

## Fixture persistence and actual process test

`SplitFixtureStore` uses a deliberately marked synthetic directory, fixed slots, path/symlink checks and a 16 MiB read bound. `SplitReceiverFixturePersistence` persists the validated receiver database with atomic replacement and readback. Database version, request/key correlation, phase invariants, attempt/outcome consistency and a 128-record limit are validated; there is no silent eviction.

An exclusive-create file lock serializes separate store instances and OS processes. Only its matching transient lock token is removed on normal exit; source/backup data is never deleted. A process dying while holding the lock leaves a visible `busy` state. There is no automatic stale-lock stealing or invented proof that an old writer died. Production lock ownership/liveness, entitlement binding, data protection and fsync/power-failure behavior remain unverified.

The focused suite runs 16 competing store/receiver instances. The runner also launches two separate Windows processes against one persisted reservation, requires exactly one execution attempt, then starts a third process and requires replay rejection. This exercises owned file/state behavior, not a fabricated counter or an Apple app process. Other cases reopen actual fixture files after logical crash boundaries and inject loss of acknowledgement **after the real persistence transaction** for reservation, execution start and saved result. Unknown outcomes never gain a second attempt.

## Migration write-ahead recovery

`SplitMigrationIntent` retains validated before/after journals, operation kind and version. Its transition is reconstructed from the actual snapshot/journal implementation before it is trusted. The fixture adapter performs:

1. Validate current source/destination/journal and resolve any prior intent.
2. Atomically persist the intent containing both known states.
3. Atomically write the destination snapshot.
4. Atomically write the corresponding journal and verify readback.

Recovery compares the actual destination and journal to the known before/after states and confirms source provenance. It can finish the intent or explicitly restore the before state, then persist a stable checkpoint. Restoring the before state does not cause a later restart to apply the abandoned operation automatically. Repeated recovery is idempotent. Unknown destination edits, changed source, invalid intent or journal conflict are preserved and rejected.

Apply and rollback are each interrupted after intent, destination and journal writes in actual disk fixtures. No source/backup deletion occurs. Initialization refuses existing partial or complete fixture state rather than overwriting it. A partially failed initialization is not silently repaired; recovery requires the recorded valid plan/journal. This remains snapshot-copy logic for synthetic fixtures, not a SwiftData/CloudKit/Keychain migration or a promise of power-loss durability.

## Integration exclusions and verification

Tomer's production package registration must exclude all three fixture adapters:

- `SplitFixtureStore.swift`
- `SplitReceiverFixturePersistence.swift`
- `SplitMigrationFixturePersistence.swift`

`DurableReceiver.swift`, `DurableMigration.swift`, `SplitMigration.swift`, the foreground codec and canonical adapters have no dependency on those fixture implementations. No fixture executable `@main` belongs to a production or registered XCTest target. Tomer owns any registered wrappers; this continuation supplies separate `DurableSplitTests.swift` only.

Run `py -3 Scripts/ProductSplit/run_portable.py --suite durable`. Actual results, named cases, source digests, dependency compilation/cache provenance and child-process outcomes are in `durable-results.json`. The runner hashes compiler/options/canonical inputs before reusing its scoped local module cache; changed owned sources/tests are compiled and executed again. Build products and per-run unique fixtures stay in the owned `.build` tree. This suite does not rerun the unchanged 278 inventory audit or claim the historical 55-case result as a current whole-app pass.

Executed result: **30/30 EXECUTED_PASS** with Windows Swift 6.3.3, Swift 6 language mode, complete strict concurrency and warnings-as-errors. Twenty-nine Swift cases exercised owned disk state; the thirtieth ran separate competing/restarted processes. Real canonical module inputs were unchanged and reused from the source-hashed local cache; all changed leaf/test sources were compiled. A prior attempt exposed an exclusive-create error/stat race on Windows; classifying the original Cocoa file-exists error as `busy` fixed it, and the final suite passed. Source hashes in the final report were compared with the delivered files. No Apple SDK or app/device result is implied.

Remaining gates: authenticated production transport/store, AppGroup/Keychain/entitlement binding, live broker dispatch, real foreground app return/cold launch, production migration, SDK/SwiftUI compile, independent installed apps and signed device acceptance. H/I remain open; K assembly is Tomer's lane. No production data, signing, CI, release or main merge occurred.
