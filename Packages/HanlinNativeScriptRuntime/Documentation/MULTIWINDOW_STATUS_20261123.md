# NativeScript multiwindow status — 2026-11-23

## Confirmed boundary

The pinned NativeScript/ios-spm 9.1.0 wrapper owns one process-global main VM.
Creating a second NativeScript object destroys the former VM. Concurrent independent
NativeScript MiniApp invocations remain BLOCKED_UPSTREAM; the existing guard stays.
This is a dependency architecture limitation, not a new user-facing permission.

## Source evidence

NativeScript/ios-spm 9.1.0 commit: a8e26efad02d792a62d2d015f0f7a632e336b2d1.
NativeScript/ios v9.1.0 commit: 5d4569c197810cdd4c1e02e7c16d42a01a77d5c0.
Pinned XCFramework SHA-256: 7fe4225faf085c61cef93d7faaa6c70fa3c97bf0631d53f4c868eea2d819c209.

- NativeScript.mm:42 declares one process-global unique_ptr runtime. Initialization
  at168–169 resets it before allocation; shutdown at143–145 clears global tasks
  and resets that same pointer.
- RuntimeConfig.cpp defines a global config. Initialization overwrites BaseDir,
  ApplicationPath and other values for the entire process.
- Tasks.cpp uses a static task collection; shutdown clears it.
- Runtime.mm has worker-isolate structures, but AppPackageJson/AppConfigCache
  remain global. Worker support does not make the main UIKit wrapper independent.
- NapiRuntime returns the current-thread environment. JSIRuntime caches a static
  runtime. Neither provides a separate main application-session constructor.

## A cooperating application's own windows

The shipped @nativescript/core application.ios.mjs implements
Application.ios.openWindow at1203 and keeps a NativeWindow scene registry.
One cooperating application can author multiple scenes within its existing VM.
That does not isolate arbitrary catalog packages or per-invocation input: the
embedded path still uses Application._rootView and one NativeScriptEmbedder
delegate, while configuration, module caches and globals remain shared.
No existing per-invocation view-factory contract turns this into independent apps.

## In-scope fixes

- Expose activeSessionIdentifier for preflight immediately before provider changes.
- Pass the actual runtime session ID to setActiveContainer.
- Guard clearActiveContainer(forSessionID:) by owner; unrelated and late-window
  teardown leaves the active bridge unchanged.
- Clear the legacy provider only when its object identity matches the caller.
- Preserve the live VM/environment/shared-runtime ownership; no implicit restart.

The caller must perform preflight, provider registration and start without an
intervening await. Only the owner should tear down its runtime.

## Minimum complete architecture

Keeping the current whole-application wrapper would require an upstream artifact
change: scope its main runtime, config, tasks and application cache per instance,
then route presentation, Host Services and package paths by session. The separate
Node-API interoperability APIs could instead underpin a host-owned application
runner, but that is a new engine/module/filesystem/bootstrap/presenter integration,
not a transparent dependency update. Either route needs actual two-window proof
for distinct roots, timers, callbacks, module loads, inputs and independent teardown.
Deleting only the Hanlin singleton guard cannot provide that behavior.

## Current supported runtime review

The official latest stable iOS release `v9.1.1` and published SPM prerelease
`9.1.2-next.2026-11-23-45255582945` were inspected without changing dependencies.
Both still hold one process-global main runtime. Their initialization writes the
shared configuration and destroys the previous main runtime before replacing it.
The current Node-API runtime repository at `8cdc398d30339e809fc2c491238e0af0deb3442d`
keeps the same single-main-wrapper architecture and a shared application path.

The Node-API bridge itself does expose per-environment native interoperability.
That provides useful building blocks for a separate host integration; it does not
provide an independent whole-package launch contract compatible with our current
`runMainApplication` entrypoints. Existing package entries call `Application.run`
and use its one embedded primary window. `NativeWindow` can support multiple
cooperating views of one application, but using it here would require an explicit
per-invocation view factory, bound services and a scene-aware presenter.

Exact release dates, official SPM checksum, source blob hashes, published npm
channels and source links are retained in
`multiwindow-current-upstream-20261123.json`. No runtime binary was downloaded,
no migration was applied, and no prior native tests were repeated for this review.

## Verification

The new Apple case unrelatedAndLateWindowCleanupPreservesNativeScriptOwner checks
unrelated and stale-owner teardown against actual bridge/provider classes.
Swift source parsing passed. Apple compilation/execution is NOT_RUN in this lane
and belongs to the integrated MiniApps gate. No baseline engine suite reran.

Sources:

- https://github.com/NativeScript/ios-spm/blob/9.1.0/Package.swift
- https://github.com/NativeScript/ios/blob/v9.1.0/NativeScript/NativeScript.mm
- https://github.com/NativeScript/ios/blob/v9.1.0/NativeScript/runtime/RuntimeConfig.cpp
- https://github.com/NativeScript/ios/blob/v9.1.0/NativeScript/runtime/Tasks.cpp
- https://github.com/NativeScript/ios/blob/v9.1.0/NativeScript/runtime/Runtime.mm
- https://github.com/NativeScript/ios/blob/v9.1.0/NativeScript/NapiRuntime.mm
- https://github.com/NativeScript/ios/blob/v9.1.0/NativeScript/JSIRuntime.m

## Cooperating package namespace implementation — 2026-11-25

The current implementation uses the original pinned NativeScript 9.1.1 runtime,
its original `ns:module` `configureLoader` / `createPumpingRequire`, and the
original Core `NativeWindow`. It stages a distinct source namespace for each
window under a neutral, host-owned application root. Relative/static/dynamic
module identities, package-local bare dependencies, resources, root CSS,
window storage, Host Services and callbacks are explicitly bound to that window.
A neutral process-global provider cannot silently acquire the first window's
capabilities or data paths. Closing a window retains module files needed by live
windows and retires only its own bridge, view and callbacks. The host tree is
removed after the last window and the original VM stop.

This is cooperating package support, not independent V8 global objects or a
native security sandbox. Packages opt into `hanlinNativeScript.windowFactory: 1`
and use their supplied services, storage and resource context. Arbitrary writes
to `globalThis`, native singleton state, process-global ApplicationSettings,
`Application.addCss`, or global application configuration remain shared. Whole
application entries retain the original singleton guard. No wrapper reset,
monkey-patched evaluator, or cloned original engine is introduced.

The v9.1.1 public NativeScript header still offers one whole-application
initializer; NativeScript.mm owns a process-global main Runtime pointer and
destroys it before initializing another. The original Worker API creates
separate background runtime/isolate contexts and copies loader policy; it does
not supply independent main-thread UIKit application instances. Exact upstream
file blob IDs and SHA-256 values are recorded in
`../../../docs/product-split/evidence/cross-app-20261123/native-package-window-20261125/upstream-runtime-review.json`.
Official references:
- https://docs.nativescript.org/guide/multi-window
- https://github.com/NativeScript/ios/blob/v9.1.1/NativeScript/NativeScript.h
- https://github.com/NativeScript/ios/blob/v9.1.1/NativeScript/NativeScript.mm
- https://github.com/NativeScript/ios/blob/v9.1.1/types/ns-module.d.ts
- https://github.com/NativeScript/ios/blob/v9.1.1/types/ns-worker-threads.d.ts

### Runtime and acceptance corrections

The original NativeScript fixture lacked the required `plugins: {}` declaration;
commit 3e871e428 fixed that admission failure without changing the original
window assertions. The nonce production check now also requires the real
NativeScript parity root. The later SDK/metadata correction belongs to PR19
and must be integrated before current native execution.

A separate retained-lifecycle defect was found in the real Objective-C++
window context: closing set `closed = true`, then used a setter that ignores
changes when closed, leaving the JavaScript lifecycle block retained across
VM shutdown. Close now clears the ivar directly while the VM is still live.
A native ownership regression explicitly holds the closed context and verifies
its lifecycle capture is released before the runtime ends.

The original twenty obligations remain. Two real package-window UI cases add
different packages, module-name collisions, late imports, resource bytes,
computed root CSS, storage readback, reverse completion and cancellation.
The original same-package fixture now also uses module-level mutable state and
identical storage filenames, preserving its original callback assertions.
One lifecycle ownership case brings the current affected gate to 23 cases.
These input packages run in the real producer app; the Foundation fixture only
seeds incoming requests and independently checks persisted actual outputs.
No fixture synthesizes a completion result.

Current source checkpoint: JavaScript syntax, Python parsing, archive/source
byte identity and diff whitespace have passed. Original-runtime acceptance for
this source is still NOT_RUN; the separate native gate must compile and run on
the actual Mac with retained xcresult and source-bound receipts. Independent
global isolation and physical iPad acceptance are not claimed.
