# Scripting acceptance and performance

Status: local infrastructure complete; end-to-end acceptance blocked.

## Immutable inputs

`Reference/ScriptingCompatibility/Acceptance/acceptance-packages.json` records
the six owner-supplied inputs, expected hashes, required API families, and the
seven mandatory stages for each package. The verifier reads external files
without copying or normalizing them. Five attached packages match their locked
SHA-256 values. `זמני היום ולוח לימוד יומי 3.zip` has not been supplied and
therefore has no authorized digest.

## End-to-end matrix

Every cell must contain an artifact or test reference before release. A
successful Import Preview does not imply compile, install, or execution.

| Stage | Required evidence | Current result |
| --- | --- | --- |
| Import/analyzer | deterministic preview JSON and zero execution | blocked locally: Swift toolchain cannot run; production analyzer exists |
| Compile | TS 7.0.2 host typecheck plus TS 6.0.3 device emission, graph, JS, maps and fingerprint | contract implemented; production NodeMobile adapter and Xcode proof pending |
| Install/relaunch | atomic record, generation, catalog restoration | store fault tests exist; real package blocked by compile |
| Launch/render/events | JSC compatibility or QuickJS secure session plus ScriptUI snapshots/patches | persistent JSC and QuickJS component tests exist; real package blocked by install |
| Permissions | allow, deny, expiry and revoke with audit | broker tests exist; real package blocked by compile/install |
| Entrypoints | app, tools, widget, intent and live activity | generic host infrastructure exists; Xcode/device verification pending |
| Update/removal | diff, rollback generation, uninstall and cleanup | atomic store tests exist; real package blocked by compile |

## Release performance budgets

These are pass thresholds, not measured claims. Measurements use release
builds, signposted wall time, resident-memory deltas, fixed package bytes, and
at least 30 iterations after five warmups on the CI simulator/device class.

| Operation | Budget |
| --- | ---: |
| 10 MiB archive copy + inspect + preview, p95 | <= 3.0 s |
| Warm deterministic compile of 250 modules, p95 | <= 2.0 s |
| Cold deterministic compile of 250 modules, p95 | <= 6.0 s |
| Installed Script app cold launch to first native frame, p95 | <= 1.0 s |
| ScriptUI event-to-applied-patch latency, p95 | <= 33 ms |
| Foreground QuickJS session memory limit | 16 MiB engine heap |
| Foreground JSC bridge input/output | <= 1 MiB each; no claimed hard engine heap limit |
| Widget snapshot file | <= 4 MiB |
| Widget timeline load and decode, p95 | <= 100 ms |
| Assistant tool cancellation acknowledgement, p95 | <= 250 ms |

A result over budget fails SG-10; limits are not raised without recording the
fixture, device, regression cause, and product decision.

## Migration and recovery

The Scripting store uses versioned metadata, sibling staging, a journal,
verified hashes, atomic promotion, retained generations and deterministic
startup recovery. Unknown schemas stop rather than downgrade. Corrupt payloads
do not become empty success. Grants are identity/integrity scoped and must be
re-evaluated on update. Extension snapshots are reconstructible; resume
commands are durable until the main runtime acknowledges delivery.

No migration deletes owner data. Uninstall removes installed artifacts only
through the store's validated package identity; namespaced user data and grants
require an explicit retention choice in a future product UX.
