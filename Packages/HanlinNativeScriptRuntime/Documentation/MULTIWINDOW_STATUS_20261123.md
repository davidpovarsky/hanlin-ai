# NativeScript windows — current status, 25 November 2026

## Supported architecture

The current integration uses the original NativeScript iOS **9.1.1** runtime and
the original Core **9.1.4** implementation. Packages that opt into
`hanlinNativeScript.windowFactory: 1` can create concurrent windows through
the original Core `NativeWindow` and the runtime's `ns:module`
`configureLoader` / `createPumpingRequire` APIs.

Each invocation receives a separate staged source namespace below a neutral,
host-owned application root. This covers multiple windows of one package as
well as windows belonging to different packages. The implementation binds
relative and dynamic imports, package-local bare dependencies, resource paths,
root CSS, window storage, host services and callbacks to the invocation.
Module-level mutable state is separated by the distinct module paths.

The process-level provider is neutral: it cannot silently inherit the first
window's capabilities or data directory. Closing one window retires its own
bridge, view and callbacks. Module files remain available while other windows
are live, including for late imports. The host tree is removed only after the
last window and the original VM have stopped.

Relevant implementation:

- [Window package staging](../Sources/HanlinNativeScriptRuntime/HanlinNativeScriptWindowPackage.swift)
- [Window session ownership](../Sources/HanlinNativeScriptRuntime/HanlinNativeScriptWindowSession.swift)
- [Native window factory](../Sources/HanlinNativeScriptCoreSupport/HanlinNativeScriptWindowFactory.mm)

## Shared-process boundary

This contract does **not** create independent JavaScript global objects or an
operating-system sandbox. Arbitrary writes to `globalThis`, native singleton
state, process-global `ApplicationSettings`, `Application.addCss`, and global
application configuration remain shared. Cooperative packages must use their
supplied services, storage, resources and root styling.

Whole-application entries using the original application bootstrap retain the
single-owner admission guard. Starting a second such application would replace
the existing upstream main VM. The new window factory is an explicit alternative
for cooperating packages; it is not permission to remove the whole-application
guard. Independent arbitrary main-thread NativeScript applications remain an
upstream architecture gap.

The public NativeScript 9.1.1 header offers one whole-application initializer.
`NativeScript.mm` owns a process-global main Runtime and resets it before
initializing another. Worker contexts provide separate background execution;
they do not provide independent main-thread UIKit application instances.
The recorded source review includes exact upstream blob IDs and SHA-256 values:

- [Current upstream review](../../../docs/product-split/evidence/cross-app-20261123/native-package-window-20261125/upstream-runtime-review.json)
- [NativeScript multi-window guide](https://docs.nativescript.org/guide/multi-window)
- [Original 9.1.1 public header](https://github.com/NativeScript/ios/blob/v9.1.1/NativeScript/NativeScript.h)
- [Original main-runtime implementation](https://github.com/NativeScript/ios/blob/v9.1.1/NativeScript/NativeScript.mm)
- [Original module APIs](https://github.com/NativeScript/ios/blob/v9.1.1/types/ns-module.d.ts)
- [Original worker APIs](https://github.com/NativeScript/ios/blob/v9.1.1/types/ns-worker-threads.d.ts)

Earlier observations for 9.1.0 remain in Git history and the retained upstream
review JSON. They must not be read as the version of the current shipped input.

## Corrections and coverage

The original window input package omitted the required `plugins: {}` declaration.
Commit `3e871e428` corrected admission without weakening the window assertions.
The production nonce check requires the real NativeScript parity view and its
actual JavaScript result. The SDK branch's original ESM loader and callback
run-loop corrections are incorporated in the current integrated candidate.

Closing a window previously set `closed = true` before invoking a setter that
ignores changes on a closed context. That retained the JavaScript lifecycle
block across VM shutdown. The native context now clears the ivar while the VM
is live. Its ownership regression retains the closed context and checks that
the captured lifecycle has been released.

The current standalone gate has **25 selected cases**. It includes the original
bridge/producer/preferences/runtime obligations, same-package reverse completion
and cancellation, distinct-package import/resource/style/storage isolation,
existing-scene selection, and native lifecycle ownership. Input fixtures seed
requests and inspect actual persisted results; they do not fabricate completion.

## Current verification boundary

The current integrated producer source is
`fe3f75d0638671c749225e9a8ddd487db70981cf`. It combines the exact reviewed
foreground-window and iPad orientation changes with PR19 through `dc53a6c8`.
The original multiscene implementation is retained. The complete `Packages`
tree is unchanged from `70eb9c2d`; the next actual full 25-case run is being
prepared on installed iOS 27.2. No previous-platform pass is relabeled.

The actual `70eb9c2d` run finished with **23 pass, 2 fail, 0 skip**. All three
original stopping-point failures passed: same-package reverse completion,
cancellation preserving the other prepared callback, and genuine NativeScript
JavaScript output with a nonce plus relaunch. All 13 host methods passed.

The two remaining failures have different causes. During different-package
reverse completion, backboardd aborted after Metal texture validation reported
an invalid pixel format at 14:49:09 UTC. Runningboardd then explicitly killed
the test runner for backboardd respawn. A separate existing-root test queried a
background scene's control for hittability; the actual first AX window and
Exposé screenshots identify the foreground and the preserved pending scene.
The new helper selects that actual foreground window before touching controls.

The new iPad-only Info.plist declaration includes all four supported orientations.
The existing-root method now requests four actual device orientations while the
original request remains prepared. It checks rendered landscape/portrait
geometry, process/request identity, edited text and callback state, then still
completes through the original return path. Width/height alone does not prove
the distinct scene angles for portrait and upside-down.

The preceding `27381e90` run remains **20 pass, 5 fail, 0 skip**. Its distinct-
package cases passed, but another authentic backboardd Metal assertion killed
the same-package runner. It also exposed the catalog localization regression
corrected in 70eb and verified by the actual EN/HE UI. The installed 27.2 runtime
is an empirical mitigation to evaluate; no documented Apple Metal fix is claimed.

Full raw attempts, screenshots, accessibility output, xcresults, verifiers and
OS diagnostics are retained, including an authenticated off-host readback of
the complete 70eb attempt. Sampling timeouts remain recorded separately. The
next scoped observer has a bounded 20-second process-query deadline and retains
all PID/image, missing-process and foreign-image semantic checks. It does not
change any test deadline or convert an incomplete old receipt to a pass.

Full independent globals, original consumer-app acceptance, signed device App
Group sharing and a physical iPad run are separate obligations. Their completion
is not implied by cooperating-window tests.
