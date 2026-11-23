# Original MiniApps library in the shared SDK

The original standalone MiniApps search, catalog, detail, launch, package-management routing and transfer presentation are now public in `HanlinMiniAppsUI`. The executable uses aliases to these same implementations. Its existing `MiniAppsLibrary(services: .connected(to: provider))` call remains unchanged.

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

The source-preservation receipt compares all **12 original function/computed-property bodies** across the three original owners. Only the explicit shared localization routing and the two transfer injections are normalized. Public access, complete constructors and nonisolated immutable presentation identity are recorded separately. Seven changed Swift sources parsed successfully. The existing **15 graph controls passed**, including the original provider inventory and rejection of AgentCore leakage into MiniApps.

The older `IntegrationValidation/validate.py` whole-project historical identity assertion still rejects a pre-existing SDK source-ownership change in `D79AD5752DB545F9000646D4/files`; it is not used as a successful current SDK gate. The current `test_project_graph.py` controls verify the actual canonical graph.

The generated `HanlinChatUI` selected manifest and all **363 selected source/resource files** are byte-identical to native Motion run `45122303559` at `65fdc2ed`. That run stopped at Xcode's Equatable macro admission before compiling or executing tests; unchanged bytes are an impact proof, not a UI pass. The optional MiniApps product does not add a reverse dependency to ChatUI, ScriptUI or ApplicationRuntime. Native compilation and original MiniApps UI acceptance remain separate gates.

Evidence:

- [Original member-body preservation](../../docs/agent-sdk/evidence/miniapps-source-extraction-20261123.json)
- [Selected ChatUI closure comparison](../../docs/agent-sdk/evidence/miniapps-chatui-closure-20261123.json)
- [Focused verification receipt](../../docs/agent-sdk/evidence/miniapps-verification-20261123.json)
- Reproduce the body comparison with `Scripts/SDK/verify_miniapps_source_preservation.py` and the existing `Scripts/Extensions/inspect_source_preservation.swift` inspector.
