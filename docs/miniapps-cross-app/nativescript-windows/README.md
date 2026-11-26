# Cooperating NativeScript invocation windows

This lane implements a same-package cooperating window factory while retaining one existing NativeScript main VM. Each window has a fresh view tree, Host-owned container, provider-bound facade, and independent request/result lifetime. Legacy whole-application entries retain their owner guard.

## App API

`HanlinNativeScriptWindowSession.supportsWindowFactory(applicationRoot:)` reads `hanlinNativeScript.windowFactory: 1` from the prepared package.json.
`open(applicationRoot:environment:makeRuntimeProvider:makeWindowProvider:configureRuntime:releaseRuntime:)` reuses only the exact application-root generation and environment. The neutral runtime provider survives until the final lease closes. Every lease creates its own provider and bridge.

`configureRuntime` runs BEFORE explicit neutral-provider registration, because the existing Host container helper also installs a provider. `releaseRuntime` runs once on final teardown. Individual closes must not independently clear that shared runtime container.

Legacy active runtimes and different package generations remain intact. The new API rejects incompatible owners before changing their providers. This lane does not claim arbitrary old module globals or unrelated whole-package roots are independent.

## Package interface

Import `registerWindowFactory` from `@hanlin/window-factory`, then return a fresh root for each supplied `{id, window, services}` context. Capture that context in async callbacks. Package-wide caches may remain shared deliberately; request state belongs in the factory closure. Promise-returning factories and later content installation are supported. A root already owned by another live window is never moved away silently.

The Hanlin helper subclasses the pinned IOSNativeWindow lifecycle and routes embedded presentation to an explicit native context. It never changes the global embedder delegate for a new window. Actual scene events drive detach/reattach; temporary nil view.window, including a covering full-screen modal, does not close the invocation.

Native registry callbacks are released while the VM lives. Per-window bridges/providers are invalidated before final runtime shutdown.

## Fixtures

Existing fresh-root Core controller fixtures A/B/C declare factory mode. Core-package, SwiftUI and direct-UIKit fixtures remain legacy; their module-wide state has not been called independent.

New artifact: `Scripts/NativeScript/Fixtures/window-factory.hanlinNativeScript`. Canonical app ID: `hanlin.nativescript.window-factory` through explicit hanlinAppID. Display name: `Hanlin NativeScript Window Factory E2E`. Read installed packageID from the actual importer result.

| Accessibility ID | Meaning |
| --- | --- |
| hanlin-ns-window-request | Actual request.id |
| hanlin-ns-window-input | Editable input text |
| hanlin-ns-window-status | Loading / Ready / Prepared / Returned / actual error |
| hanlin-ns-window-counter | Independent count, initially 0 |
| hanlin-ns-window-increment | Increment this window only |
| hanlin-ns-window-prepare-return | Capture text, request metadata and bound facade |
| hanlin-ns-window-return | Execute captured completion through a Promise |

Output uses replaceSelection and one text item with the captured text. Metadata contains windowSessionID (native lease/provider ID), requestID, documentID and counter, captured at Prepare. Root native acceptance seeds real A/B/C/D requests: B returns before A, then C cancels while D remains interactive.

## Evidence

helper-tests.txt records seven passing JavaScript cases: five new factory lifecycle/context cases and two existing sharing cases impacted by extracting explicit bridge construction. Unrelated passing suites were retained. TypeScript 5.9.3 strict facade generation, helper generation parity, new fixture JS syntax and Swift parser checks passed.

These checks do not execute UIKit or the NativeScript VM. Apple compilation and actual two-window iPad journeys remain NOT_RUN in this lane and belong to the parent producer gate. No signed physical-sharing success is implied.
