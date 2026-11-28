# Current concrete SDK consumer input

This is a pinned **monorepo/local-package compile input**, not a root Git package,
published SDK release, Anytype adoption, canonical ChatUI entry or numeric model
execution approval. SDK preview is `0.1.0-preview.1`, host API major 1.

Use monorepo commit `6e8dd11dc5c6be78f04d787890b8e09b799631a3` from
`https://github.com/davidpovarsky/hanlin-ai.git`. Its consumer source changes match independently accepted
`b82b851a6a728c88dcd39315ae96048bca3d4112` (production d74/58de);
the integration manifests consistently request corrected producer
`e7bf34111e603ca977becd007dd4e5bb109af857`. The test-only host conformance correction is exactly
`03fa0191b35ae015071cd4acb3ea315550b4ff85`. Actual Mac proof and six
resolved lock files are now available at this source checkpoint. Preserve this actual layout:

```text
hanlin-sdk-input/
  Packages/
    HanlinAgentSDK/Package.swift
    HanlinAgentSDK/Package.resolved
    HanlinAgentSDK/Sources/...
    HanlinPlatform/Package.swift
    HanlinPlatform/Sources/...
    HanlinPlatform/Tests/...
```

The SDK's existing `../HanlinPlatform` dependency is literal. Do not copy its
modules into the host, invent a different manifest/provider or register the
monorepo root URL as a standalone Swift package: the manifest is nested.
The initial consumer can use Xcode's local package at
`hanlin-sdk-input/Packages/HanlinAgentSDK` or a corresponding local `.package(path:)`
from its own package manifest. Host project/DI/minimum changes stay host-owned.

| Product | Role |
| --- | --- |
| HanlinHostContracts | Typed namespace/context/catalog/request/result/host ports |
| HanlinAgentCore | Existing-engine facade, scoped dispatcher, Apple provider source |
| HanlinPersistenceAdapters | Optional explicit private/ephemeral transcript stores |
| HanlinFixtureHost | Headless synthetic example; not a real host or UI product |

No `HanlinChatUI` product or confirmed canonical UI entry exists in this input.
`#if canImport` may keep unwired source optional; it is not evidence of working
linkage, API compatibility or a lower supported deployment target.

Platforms remain **iOS 27.0 / macOS 26**, Swift tools **6.2**, language mode **6**.
Both existing manifests now pin SwiftAISDK to
`e7bf34111e603ca977becd007dd4e5bb109af857`. Committed input SHA256:

| Input | SHA256 |
| --- | --- |
| SDK Package.swift | 8a0846341234f25127f1625547cf7c2a0ca23047e32f9ae2d7d9e1c91070029e |
| SDK Package.resolved | 0b190b1d589a67422f7c7847c3a9c70533d89dd82e4ee7589b73836d277ce2f6 |
| Platform Package.resolved | 7882ef847a4aaa1bfa2ee128122393cf718f393485d9658bb93f402f740f2c17 |
| Platform Package.swift | 3f8cbcbad6b07b509a7976fe0577315481f25358ce34a01e505f2d1b04821066 |

Actual Apple proof is split honestly across two immutable runs:

- [43688388938](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43688388938)
  at this source: **10 unique SDK cases PASS**, including all seven Session tests,
  two context tests and one persistence test. Whole real packages, Xcode27.2
  build27B52 / Apple Swift6.4.2 / macOS SDK27.2. No producer/core/iOS rerun here.
- [43686294717](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43686294717)
  at `e233bffcef77080295656dceac71b04b1b5d4528`: **48 producer +20 core PASS**
  and actual iOS AgentCore compile PASS. Its SDK bundle did not compile before
  the test-only correction; its ten SDK obligations were NOT_RUN.

The relevant SDK/Core production, fixture support, core tests and both manifests
have identical Git object identities across those runs. All three actual raw
locks (producer/SDK/Platform) have identical SHA256 in the two artifacts; Xcode
27.2 build27B52 and swift-driver1.168.6 identities match. The second run's whole
251-file source inventory is separately verified at its OWN source commit,
not relabeled as unchanged from the first 250-file inventory. Ten passes are new;
68 older passes are reused only for their unchanged target closures. This is
synthetic model/fixture-host regression, not real host/native model/UI acceptance.

[43687551868](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43687551868)
resolved all six existing package roots on Apple, with zero builds/tests. All270
source/workflow hashes and each raw lock were checked before exact import.
Existing argument-parser1.8.2, ZIPFoundation0.9.19 and SwiftyJSON5.0.1 revisions
remain fixed. Four stale Mini App locks now include already-declared SwiftyJSON.
The SDK/Platform locks match the actual regression build locks above.

## Reproducible Apple source layout

Run in a **new empty location** on a Mac with the actual supported stable Xcode:

```sh
git clone --no-checkout https://github.com/davidpovarsky/hanlin-ai.git hanlin-sdk-input
git -C hanlin-sdk-input checkout --detach 6e8dd11dc5c6be78f04d787890b8e09b799631a3
swift package --package-path hanlin-sdk-input/Packages/HanlinAgentSDK resolve
swift build --package-path hanlin-sdk-input/Packages/HanlinAgentSDK --target HanlinAgentCore
swift test --package-path hanlin-sdk-input/Packages/HanlinAgentSDK \
  --filter 'AgentSessionTests|ContextTests|StoreTests'
swift test --package-path hanlin-sdk-input/Packages/HanlinPlatform \
  --filter 'HanlinInjectedProviderTests|HanlinAISDKProviderFactoryTests|HanlinAISDKAgentEngineTests'
```

The authorized CI uses the same whole packages with discovered Xcode schemes,
Mac tests and a separate actual iOS 27 simulator SDK build. There is no Windows
`String(localized:)` shim, alternate dependency pin or copied renderer.

## Anytype host minimum and remaining execution boundary

Read-only inspection at host base
`84e132c5e8e04d09c3fd7badbf8f5a7c202fa204` found `Anytype.xcodeproj` configurations
with iOS **17.0** and its separate `PinkhaStage1Acceptance` project with **18.0**;
these are below this SDK's iOS 27 minimum. This input is therefore not a drop-in
dependency for those current targets. The Anytype lead must choose a compatible
target/minimum/linkage arrangement; no host project or source was changed here.
SwiftPM requires dependency platform minima compatible with the consumer's
deployment target: [official SwiftPM platform contract](https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html#supportedplatform).

The latest independent SDK06 review, `COMBINED_REPLAY_REVIEW_18081a1a.md`,
accepts the combined P2 replay correction as SOURCE ONLY: full17 manifest
`901883ea225e8d74e03f4bc5efa7d8d154412f6421aed2c4f4f837d1607b2975`,
repair `18081a1a98cb17c3291f3ddd3d1983c94106d3d8aaa550064965f9ad6b6e753b`.
That other owner's source remains uncommitted/unstaged at the host base above;
it was not imported here. Original identity/effect receipts are protected across
awaited freshness/consent/catalog checks, according to the independent source
review. Existing grammar-only `-D DEBUG` parse passed; read22, write10 and
combined17 authored cases are all NOT_RUN. No active-iOS typecheck or native
runtime/storage/security/UI acceptance follows from parsing or this SDK proof.

The composed host port remains source-compatible with unchanged SDK host
contracts, but its real lifetime/account-removal/metadata-retention/UI-receipt
installation barrier is UNINSTALLED. Its current catalog is READONLY. Proposed
title-only write helpers do not expose native create/journal/prompt operations
through the SDK or fulfill permitted native-WRITE acceptance. Empty-object read
schemas remain distinct from numeric business operations and write/CAS guarantees.
Actual linkage/minimum/lifetime/retention/UI/native validation stays host-owned.

The former producer 43eb lost raw numeric representation through Double before
the host. Corrected producer e7bf and the consumer guard/session source now have actual
Apple regression evidence for the tested numeric subset: Int64 identity, supported
decimal/exponent category, nested values, unsupported precision rejection before
pending/host effects, revocation and receipt retention. This is not arbitrary
precision, a real writable host, native effects or general numeric parity approval.
Unverified/missing original numeric input is fail-closed in source; the portable
guard proof is distinct from the actual seven Session methods. Parent SDK and
host-specific acceptance remain open; the old25-case43eb result is historical.
Cancellation/invalidation is terminal for a presentation Session. A later send
needs a new host-authorized session identity and current context/permissions;
a view cannot issue authority. Normal completion may reuse a still-valid session.
Unresolved pending/uncertain effects survive conversation reuse and need host
reconciliation.

No temporary local linkage is a shipped pin, and no SDK/root URL distribution or
real host, UI, device, native tools or TestFlight acceptance is claimed.
