# Shared ScriptUI duplicate reorder admission — 2026-11-23

The public canonical `HanlinScriptUIReconciler.apply` accepted a reorder containing repeated requested keys. A valid root with children `a,b` followed by reorder `a,a,b` and then reorder `a,b` therefore reached the original `Dictionary(uniqueKeysWithValues:)` with duplicate child keys. Public Codable patches and the original `HanlinScriptUIModel` patch entry point admit this sequence.

## Actual original failure

The exact two-patch sequence was compiled against complete, unmodified original PlatformContracts and the complete original Foundation-only ScriptUI contracts/reconciler files. A separate child process reproduced **SIGTRAP, exit -5**, with `Fatal error: Duplicate values for key: 'a'`; the retained native stack points to the original reconciler line99. Core dumps were disabled. No product process or existing user data was involved.

The disposable SwiftPM envelope uses the canonical source bytes recorded in `plan.json`. It does not supply replacement model or reconciler declarations. Its deliberately partial ScriptUI target excludes Apple SwiftUI, Charts and WebKit sources; it is not a full SDK/native build. The baseline source is byte-identical to the audited root8538287f for the compiled original modules.

## Minimal shared repair

Four lines before the original dictionary now collect current child keys and reject a missing current key, duplicate current keys, and duplicate requested keys. The existing `keySetMismatch` and `duplicateKey` errors, original Set-based uniqueness convention, dictionary creation, key-set check, output order and node reconstruction are retained. The existing value-returning apply operation still throws before the caller can publish a partial batch. No UI, layout, timing, model schema or application routing changed.

## Focused execution

The actual new `HanlinScriptUIReorderAdmissionTests` source in the existing test target ran once against that canonical implementation on Oracle arm64 Linux, Swift6.4.3, Swift6 language mode and complete concurrency checking. **Six tests passed, zero compiler warnings**; total7.19s, build6.24s. Raw Swift Testing XML and build/test log are retained.

The cases cover the exact encoded two-patch failure sequence; malformed current children with duplicate or missing keys; missing/unknown requested key sets; valid full-node reordering followed by a property patch and the valid empty case; and a failed nested batch that keeps the previously published tree unchanged and permits a later valid reorder. No unrelated passed suite was replayed.

The original Apple `HanlinScriptUIModel` performs `root = try HanlinScriptUIReconciler.apply(...)`; the focused tests execute that same value-publication boundary. They do **not** execute SwiftUI, the full app, rendering, or a native host. No CI was dispatched.

## Reproduction and provenance

`reproduce.swift` contains only the public input sequence. `proof-Package.swift`, the original/fixed input manifests, exact commands, child result and raw stack make the before/after scope reviewable. The source hash receipt refers to the exact tested working-tree bytes; the enclosing commit supplies their repository identity. The ordinary package test target discovers the new regression file without a manifest change.
