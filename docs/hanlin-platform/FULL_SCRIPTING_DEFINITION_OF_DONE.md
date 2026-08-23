# Full Scripting platform definition of done

Status: multi-runtime core implemented; end-to-end and release gates remain open.

This checklist is the repository traceability companion to
`canonical-contracts/SCRIPTING_INTEGRATION_GATES.md`. A checked item requires
code plus deterministic test or explicitly requested Xcode/runtime evidence.
UI presence, a placeholder, or a declaration-only binding is not completion.

## Engine and fixtures

- [x] Original TS/TSX/JS entrypoints select typed `scripting-jsc`; original
  Python entrypoints select `hanlin-python`; selection has no fallback.
- [x] JSC and QuickJS declare different, truthful hard-limit capabilities.
- [ ] JSC imports/source maps/ScriptUI/lifecycle conformance pass under Xcode.
- [ ] QuickJS runtime-v2 async host calls, events, streams, modules, handles,
  cleanup and backpressure pass shared conformance.
- [ ] Trusted Node and Python worker adapters pass Hybrid conformance.
- [x] QuickJS C bridge exposes typed memory and stack failures.
- [x] Swift does not parse engine messages to classify resource failures.
- [x] Timeout, memory, stack, output, cancellation, and disposal are separate tests.
- [x] Test fixtures are bundled and have no checkout-path fallback.
- [ ] Targeted Xcode 26 engine tests pass on the exact implementation commit.

## Package, compiler, and runtime

- [ ] `.scripting` and `.zip` support copy, inspect, preview, install, relaunch,
  update, rollback, uninstall, and recovery.
- [ ] Safe extraction rejects traversal, links, bombs, collisions, malformed
  manifests, encrypted entries, and policy limit violations.
- [ ] TypeScript 7.0.2 host/CI typecheck and TypeScript 6.0.3 on-device emitter
  record separate versions, hashes, options, diagnostics, maps and cache inputs.
- [ ] Multi-file TS/TSX/JS/JSON and the virtual `scripting` module compile into
  a deterministic closed module graph without arbitrary npm or package scripts.
- [ ] Untrusted Hanlin code runs only in package-isolated QuickJS sessions with typed
  async wire, handles, streams, cancellation, backpressure, quotas, and cleanup.

## SDK, UI, and services

- [x] SDK bindings and compatibility matrix are generated deterministically
  from the immutable authorized baseline.
- [ ] ScriptUI provides TSX, typed virtual nodes, reconciliation, hooks, events,
  effects, native SwiftUI rendering, navigation, presentation, RTL, Dynamic
  Type, accessibility, keyboard/pointer, and multiwindow behavior.
- [ ] Storage, VFS/files, network/fetch, Assistant, dialogs, device, navigation,
  open URL, pasteboard, location, notifications, HealthKit, and approved
  baseline families use capability, grant, OS authorization, quota,
  cancellation, and redacted audit enforcement.
- [x] Every approved symbol is classified as Implemented+tested, Partial with
  exact limits, Unsupported-by-platform with evidence, or Not-yet-implemented;
  no approved symbol remains planned or unknown.

## Product integration and extensions

- [ ] `Apps -> + -> Import Script Package -> Files -> Preview -> Install` is
  wired to one Native/Script/Hybrid catalog.
- [x] Startup restores installed packages and publishes Script tools to
  `HanlinCanonicalToolAuthority` before model tool schemas are prepared.
- [ ] Multiple assistant tools support schemas, approval, invocation, progress,
  structured results, cancellation, update, removal, identity, and capability
  enforcement.
- [ ] Generic precompiled Widget, App Intent, and Live Activity targets use
  versioned extension-safe App Group artifacts and never Node/Python/shell.

## Acceptance and release evidence

- [ ] Every supplied acceptance package has analyzer/compile snapshots,
  install/relaunch/catalog, launch/render/events, allow/deny/revoke,
  entrypoint, update/rollback, and uninstall coverage.
- [ ] SG-0 through SG-10 are closed with code and test links.
- [x] Performance budgets, migrations, corruption recovery, authoring guide,
  diagnostics, and troubleshooting are documented.
- [ ] After explicit authorization, targeted CI passes first and one full CI
  run passes on the same or documented successor commit.

## Immutable acceptance inputs

The source packages remain outside production source control until the safe
fixture-import policy is implemented. Their bytes must not be normalized or
edited.

| Supplied file | SHA-256 |
| --- | --- |
| `FileManager 2.zip` | `f47b0f07ad4da57c03aebfb797a4e6426ed7cb9edcf95de10f5df65914c12548` |
| `טקסטים ספריא רב מנועי .scripting` | `bb4c9ff48cebf6a13a3322324bf3150ea86890808d7e2ba608ef7332095ee5a0` |
| `nativ ai 9.zip` | `e5712c0fb098bd3bc037bd4861a5abf7a49a789bb3738b1104c97e296369750a` |
| `סוכן חדש 21.scripting` | `b6dc61e6ca8fd736fdbef55b62e5d48bcf8e452c72d0d36b153d107ad1a94b9a` |
| `אכילה חכמה מעודכן 7.zip` | `6846c3eff7f40740c79116f8845389bfdfc48a0b1457bdf3c46531f112f87356` |
| `זמני היום ולוח לימוד יומי 3.zip` | pending user attachment |

The missing file was searched once in the workspace and attachment directory
on 2026-08-24. Its row alone is `blocked-by-missing-input`; no substitute
fixture or digest is authorized.
