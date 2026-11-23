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

Independent NativeScript UI instances require an upstream artifact change: move
the main runtime into each object, scope config/tasks/application cache to its
isolate, route presentation/host services by session, and isolate environment and
package-root ownership. Verify two independent controllers, timers, callbacks,
module loads, inputs and teardown. Rebuild and pin actual binary provenance.
Deleting only the Hanlin singleton guard cannot provide that behavior.

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
