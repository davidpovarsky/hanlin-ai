# Install one selected Hanlin SDK in an original host

Each host keeps a small lock file and consumes a pinned checkout of the original SDK. Shared modules are not copied into separate vendor packages or forked for the host.

## Host contract

Commit `HanlinSDK.lock.json` at the host root:

```json
{
  "revision": "<full 40-character Hanlin commit SHA>",
  "products": ["HanlinAgentCore", "HanlinChatUI"]
}
```

The placeholder must be replaced by an actual published source commit. Branch names and shortened SHAs are rejected. The exact public product names are passed to the canonical manifest generator.

Run the shared installer from an available checkout of that SDK:

```sh
python3 /path/to/hanlin-ai/Scripts/SDK/install.py \
  --host-root /path/to/original-host
```

It performs these steps:

1. Fetches the canonical Hanlin repository and verifies the full locked commit.
2. Prepares the ignored `Vendor/HanlinSDK` sparse checkout with only canonical manifest metadata.
3. Runs `Scripts/SDK/generate_manifest.py --products ...` in that checkout.
4. Verifies the selected products and materializes only their original target source/resource paths.
5. Installs published native assets only if that product closure contains managed native binary targets.
6. Saves a receipt with the source revision, selected products and generated file hashes.

The generated files are only root `Package.swift` and `docs/agent-sdk/unified-package-manifest.json`. Their canonical source definitions remain in the SDK. SDK sources and prepared support retain their original implementation.

A host Swift package declares:

```swift
dependencies: [
    .package(name: "HanlinSDK", path: "Vendor/HanlinSDK")
]

// In the host target's dependencies:
.product(name: "HanlinAgentCore", package: "HanlinSDK"),
.product(name: "HanlinChatUI", package: "HanlinSDK")
```

For an Xcode application, add `Vendor/HanlinSDK` as the local package and select the same products. Commit the lock and host dependency declaration. The checkout and generated artifacts remain ignored.

## Updating and checking

Change the locked revision or product list, then run the same installer. It verifies ownership of generated outputs before replacing them and updates the existing canonical checkout. A source edit or manually changed generated manifest causes an explicit failure and is preserved.

A read-only CI preflight is available:

```sh
python3 /path/to/hanlin-ai/Scripts/SDK/install.py \
  --host-root /path/to/original-host --check
```

This checks the lock, pinned Git HEAD, generated profile hashes, source edits and presence of managed native assets. It does not rebuild, download, or claim a native execution pass.

The default native cache is shared across hosts under the user's platform cache directory. `--cache` can select a different shared location. `--destination` can select another relative directory inside the host; the default contract remains `Vendor/HanlinSDK`.

For a constrained development server, `--source-cache /path/to/existing/canonical-checkout-or-mirror` borrows the existing Git objects and preserves the canonical remote origin. The cache must belong to the Hanlin repository and remain available while that checkout uses it. The full locked SHA is still verified. This avoids a second network clone/object store; CI can use the normal canonical remote route.

## Native hosts

A pure source product profile does not read or install native assets. A native profile requires a published URL/checksum catalog. It fails explicitly while `docs/native-artifacts.json` is unpublished; no stub is substituted and no runtime is compiled as a fallback.

The native installer selects support archives by target. NodeMobile receives its original RuntimeHostResources archive, Python receives its original framework/stdlib and version record, Expo receives original modular headers, and NativeScript receives the original metadata build tool and launcher. See [Native artifact distribution](NATIVE_ARTIFACT_DISTRIBUTION.md) for the shared Xcode host-stage commands and publication contract.

`installed` in the receipt means the pinned source profile and required assets are installed. The original host's Apple compile, resource embedding, metadata and runtime checks remain separate acceptance gates.

## Evidence

Eight focused tests exercised real Git repositories and the actual Swift manifest loader. They passed for source-only installation without native preparation, selecting a different product, updating a pinned revision, preserving a source edit, preserving a manual profile edit, rejecting mutable revisions/path escapes, borrowing an existing canonical Git object cache, and requiring publication when a native target is selected.

The test generator is an explicitly isolated fixture for installer behavior. It does not substitute for the original Otzaria/Lorvex/Hanlin host integration gate. The original shared generator and original host checks are owned by the integration lane.

The measured remote SwiftPM fixtures also showed that unused binary declarations still affect lightweight consumers. Selected profile generation is therefore required even after binary URLs are published; the original target/source definitions remain shared.

Evidence is retained in [consumer-installation-2026-11-23](evidence/consumer-installation-2026-11-23/receipt.json).

## Selected source checkout

Before its first Git checkout, the installer enables sparse checkout for the
canonical module manifests, project dependency metadata and shared installer
scripts. It derives the requested product closure from those original manifests
and only then materializes the selected target source/resource directories.
Unselected application resources and native blobs are never written to disk
during this bootstrap. Remote clones use Git's blob filter; an Oracle
`--source-cache` installation reuses the existing object store without
copying it.

Full application selection materializes its original `AI_HLY` source tree and
then regenerates the app source/resource inventory. The same original source
files remain authoritative. NativeScript selection additionally includes the
original public-header inventory and metadata-tool provenance helpers used by
its packaged host launcher.

The receipt records `checkoutMode: "sparse"`, selected source paths, and sparse
patterns alongside the locked revision and generated manifest hash. Updating a
product or revision first checks for user source edits, then adjusts this managed
checkout. It does not replace edited files.

A focused bootstrap regression makes the pinned generator fail if an unrelated
app resource was ever materialized before product selection. That regression
passed, in addition to the eight existing Git/update/native-selection checks
rerun for this changed checkout path. See
`evidence/consumer-installation-2026-11-23/sparse-bootstrap-regression.txt` and
`sparse-installer-regressions.txt`. These checks verify installation mechanics;
the original host's acceptance remains separately recorded.


## Original auxiliary surfaces and system actions

`HanlinApplicationPanelView(context:panel:)` exposes the original provider,
model, MCP, Skills, runtime and MiniApps screens, plus `.prompts`, `.memory`,
`.translations`, `.knowledge`, `.diagnostics`, `.toolPermissions`, `.guide`,
`.costs` and `.support`. These are adapters around the existing screens, with
the same model container and lifecycle. They do not create separate view or
storage implementations. The host supplies the containing navigation and
placement; screens that already own a navigation stack keep that behavior.

`HanlinVisionView(context:onClose:)` embeds the original camera and visual
analysis screen. Its close callback is the same original workspace return
binding, routed to the host. Camera/photo privacy declarations and permissions
belong to the host application as usual.

The original `OpenVisionIntent`, `EnableChavrusaNotificationsIntent` and
`ScheduleChavrusaAlarmIntent` are public. Import `AppIntents` and `AI_Hanlin` in
the host application and register the package where the host indexes intents:

```swift
struct HostIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [HanlinApplicationIntentsPackage.self]
    }
}
```

Hanlin's own thin app target uses this registration. Its explicit `.hanlin`
configuration retains `chavrusachat://openVisionView`. Other hosts configure
`systemIntegrations.visionURL` and register/handle their own URL scheme, or present
`HanlinVisionView` from their own existing
routing action. Notification and alarm intents retain the original system
permission requests. Original intent translations now resolve from the shared
localization bundle without copying its catalogs into every app.

The registration follows Apple's
[AppIntentsPackage contract](https://developer.apple.com/documentation/appintents/appintentspackage)
and [Swift package support described at WWDC25](https://developer.apple.com/videos/play/wwdc2025/244/).
Native compilation, metadata extraction and system invocation remain separate
acceptance checks; a source or syntax check does not prove Siri invocation.
