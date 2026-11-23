# Original MiniApps library in the shared SDK

The latest original rich catalog, cards, search, hide/restore, package details, photo-study action and companion transfer presentation are shared by Hanlin and MiniApps through the canonical SDK. `NativeAppsCatalogView` and `HanlinMiniAppsCatalogView` are public in the runtime-aware `HanlinApplication` product (`AI_Hanlin`). The original lightweight navigation-split library and services remain available independently in `HanlinMiniAppsUI`.

## Independent original UI

Select the `HanlinMiniAppsUI` product and import its module. Its complete selected graph is four targets: `HanlinMiniAppsUI`, `HanlinLocalization`, `HanlinMiniAppCore` and `HanlinPlatformContracts`. It has no remote package, AI engine, JavaScript runtime, NativeScript, Expo or native binary target. It uses the canonical localization bundle automatically.

`HanlinMiniAppsServices` exposes the original catalog, launch and package-management closures. Its public initializer can accept either an existing `HanlinMiniAppDiscovery` or the existing asynchronous catalog closure. The discovery initializer continues to use `HanlinCanonicalMiniAppCatalog`; no registry or launch implementation is copied.

```swift
import HanlinMiniAppsUI
import SwiftUI

// These services are supplied by the host's existing catalog and launch owners.
HanlinMiniAppsLibrary(
    services: services,
    transferView: { originalTransferView },
    isTransferringProductData: { originalTransferOwner.isBusy }
)
```

`originalTransferView` is an `AnyView`, matching the existing host presentation seam. The busy callback is read while building the original toolbar, so an observable transfer owner retains its live disable behavior. The library retains the original navigation split, search ordering, error state, refresh tasks, sheets, fullscreen presentations, accessibility identifiers and control layout. Hosts place and style the original view using SwiftUI composition.

## Latest original rich catalog

The later original source at `bcb1a2954c8cfbd36035c08aafb4acbca7a6a5fb` separated the rich catalog from its Hanlin-only model-context composition. That original implementation is now canonical in `AI_HLY/NativeAppPlatform/AppsHub/NativeAppsCatalogView.swift`; `NativeAppsHubView` consumes it, and the MiniApps executable aliases the shared `HanlinMiniAppsCatalogView` composition.

`NativeAppsCatalogView` exposes complete public initialization for preparation, refresh, item launch, installed-package launch, source-reader presentation and additional toolbar content. It renders the original cards, menus, editable hide controls, hidden-app restoration, package sheets and photo-study entry. These runtime-aware surfaces use the existing canonical platform/catalog owners; choose `HanlinMiniAppsUI` when supplying an independent host's catalog and launch services to the original lightweight library.

After preparing the original application runtime, the complete original companion composition is available directly:

```swift
import HanlinApplication
import SwiftUI

@MainActor
struct OriginalMiniAppsScreen: View {
    var body: some View {
        HanlinMiniAppsCatalogView()
    }
}
```

This view retains its original provider for the SwiftUI view lifetime. The first-party executable continues to inject its retained provider. It publishes the canonical companion catalog before showing the catalog as ready, preserves the original launch fence and presents the exact existing transfer screen. The provider's additive `refreshCatalog` and installed-package launch path retain the original bootstrap, enabled-package, engine-output and authorization checks. Foreground requests resolve against canonical registrations; catalog visibility remains a preference.

`TorahPhotoStudyCaptureView(presentsSourceReader: true)` preserves the later original local source-reader sheet and visible identification/error feedback. The default remains the original navigation-router behavior. The companion declares the original `maktabah` query scheme for that existing handoff. Bundle IDs, entitlements, saved schemas and release configuration are unchanged.

The companion's single-key local catalog from the later branch is already represented identically in the shared 1,118-key localization catalog. No resource copy is added. All labels use the canonical bundle through the existing SwiftSyntax routing.

## Existing Hanlin runtime composition

The original `HanlinMiniAppsProvider` remains the catalog and launch authority in `AI_HLY/Downstream/ProductSplitIntegration`. The canonical file now owns the moved `connected(to:)` composition and a public `HanlinMiniAppsServices.connectedToHanlin()` factory. After the host has prepared the original application runtime, importing `AI_Hanlin` and `HanlinMiniAppsUI` also exposes:

```swift
import AI_Hanlin
import HanlinMiniAppsUI
import SwiftUI

// Construct after preparing the original runtime. Keep one services value for
// the library lifetime so the original provider's launch fence stays alive.
@MainActor
struct MiniAppsHostView: View {
    @State private var services = HanlinMiniAppsServices.connectedToHanlin()

    var body: some View {
        HanlinMiniAppsLibrary(services: services)
    }
}
```

That convenience initializer supplies the exact original `HanlinMiniAppTransferView(mode: .receive)` and the exact `HanlinScriptingPlatform.shared.isTransferringProductData` observation. Catalog refresh, stale-selection checks, grants, package registry, engine selection and launch ownership remain in their original provider. The convenience API does not prepare or replace the runtime on behalf of the host.

## Original companion lifecycle

`HanlinMiniAppsForegroundBridge` is public in the full `HanlinApplication` product (`AI_Hanlin`). It preserves the existing first-party Hanlin companion contract. The standalone executable compiles that same canonical source through its existing explicit provider-source inventory and uses a type alias at the old path.

The public entry exposes the original observable presentation, error and privacy-safe failure code, plus `open`, `cancelAndClose` and `returnToOrigin`. URL opening can still be injected through the existing callback. The trusted mailbox, live target validation, authorization, expiry, generation, cancellation, terminal receipt and unknown-outcome handling are unchanged. This first-party composition is not a general authorization policy for arbitrary companion apps; the generic durable receiver and route contracts remain in `HanlinProductSplit`.

The executable retains its `@main`, bundle identity, entitlements, storage preparation and OS URL delivery. Existing saved request and receipt schemas and the original accessibility IDs are unchanged.

## Verification and impact

The later catalog replay preserves **51/51 original function/computed-property bodies** from `bcb1a295` across the catalog, Hub, photo capture, provider and companion composition. Normalization is limited to canonical localization routing and the public type name. Public constructors, retained provider storage and immutable identity isolation are separate integration seams. All 17 affected Swift files parsed; the existing 15 graph controls and both manifest/project idempotence checks passed. The production target validator now checks 75 shared source files and the original independent MiniApps target.

Existing native test selectors follow the later original rich catalog. The current stronger consent original-request review assertions are retained, even though the later branch removed them. The previously queued paired run `45128030798` at `199b8c99` was cancelled once before any job steps, compilation or tests because these source changes invalidated that planned gate. Fresh native acceptance of the integrated source remains required. Historical `bcb1a295` successes retain their original source/platform scope.

The first lightweight extraction separately established the following evidence:


The source-preservation receipt compares all **12 original function/computed-property bodies** across the three original owners. Only the explicit shared localization routing and the two transfer injections are normalized. Public access, complete constructors and nonisolated immutable presentation identity are recorded separately. Seven changed Swift sources parsed successfully. The existing **15 graph controls passed**, including the original provider inventory and rejection of AgentCore leakage into MiniApps.

The older `IntegrationValidation/validate.py` whole-project historical identity assertion still rejects a pre-existing SDK source-ownership change in `D79AD5752DB545F9000646D4/files`; it is not used as a successful current SDK gate. The current `test_project_graph.py` controls verify the actual canonical graph.

The generated `HanlinChatUI` selected manifest and all **363 selected source/resource files** are byte-identical to native Motion run `45122303559` at `65fdc2ed`. That run stopped at Xcode's Equatable macro admission before compiling or executing tests; unchanged bytes are an impact proof, not a UI pass. The optional MiniApps product does not add a reverse dependency to ChatUI, ScriptUI or ApplicationRuntime. Native compilation and original MiniApps UI acceptance remain separate gates.

Evidence:

- [Latest original catalog preservation](../../docs/agent-sdk/evidence/latest-original-miniapps-catalog-20261123.json)
- [Latest original catalog verification](../../docs/agent-sdk/evidence/latest-original-miniapps-verification-20261123.json)
- [Original member-body preservation](../../docs/agent-sdk/evidence/miniapps-source-extraction-20261123.json)
- [Selected ChatUI closure comparison](../../docs/agent-sdk/evidence/miniapps-chatui-closure-20261123.json)
- [Focused verification receipt](../../docs/agent-sdk/evidence/miniapps-verification-20261123.json)
- Reproduce the body comparison with `Scripts/SDK/verify_miniapps_source_preservation.py` and the existing `Scripts/Extensions/inspect_source_preservation.swift` inspector. Pass `--catalog` to verify the later rich-catalog source.
