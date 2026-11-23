# Canonical original app extensions

The original extension implementations are shared SDK code. The original executable targets retain their OS entry points, bundle identifiers, entitlements and explicit Hanlin host policy. The shared implementation does not assume that an unrelated host owns Hanlin’s App Group.

## Products and implementation owners

| Public product | Package / canonical module | Direct implementation dependencies |
| --- | --- | --- |
| `HanlinExtensionContracts` | `HanlinPlatform` / same name | Foundation only |
| `HanlinShareExtensionUI` | `HanlinAppExtensionsSDK` / same name | ExtensionContracts, ScriptStore, Localization |
| `HanlinNotificationExtension` | `HanlinAppExtensionsSDK` / same name | ExtensionContracts |
| `HanlinTranslationUI` | `HanlinAppExtensionsSDK` / same name | ExtensionContracts, PlatformContracts, ScriptExtensions, ScriptUI, ChatCore, Localization |
| `HanlinWidgetUI` | `HanlinWidgetSDK` / facade re-exporting **HanlinScriptingWidgets** | Canonical widget module depends on ExtensionContracts, PlatformContracts, ScriptExtensions, ScriptUI, ExpoWidgetNative, Localization |

`HanlinScriptExtensions` now directly depends on `HanlinExtensionContracts`. The widget package is separate from the share/notification/translation package so a share-only consumer does not resolve the Expo runtime package. Product names in this table are abbreviated in dependency cells with the common `Hanlin` prefix omitted.

The share product exposes the original `HanlinShareViewController` UI with injected `HanlinExtensionHostConfiguration`. The notification product exposes the original `HanlinNotificationService`. The translation product exposes `TranslationProviderSession`, `TranslationProviderRootView`, all five original route/subview types and `HanlinTranslationHostServices`. The latter accepts either an existing compact client and snapshot loader or immutable host configuration and a credential resolver. It retains configuration and credential refresh on each request and the existing shared chat engine.

The widget product exposes the original widget, timeline, configuration, entity and intent types, plus reusable original `HanlinExtensionSnapshotView`, `HanlinPreparedExpoNativeView`, `HanlinLiveActivityLockScreenView` and `HanlinLiveActivityRegionView`. Existing rendering, queries, generation/owner validation and action execution remain canonical in their existing SDK owners.

## Required root Xcode wiring

| Original executable target | Required direct SDK products |
| --- | --- |
| `ChavrusaChatShare` | HanlinShareExtensionUI, HanlinExtensionContracts |
| `ChavrusaChatNotificationService` | HanlinNotificationExtension, HanlinExtensionContracts |
| `ChavrusaChatTranslationProvider` | HanlinTranslationUI, HanlinScriptExtensions, HanlinExtensionContracts |
| `HanlinScriptingWidgets` | HanlinWidgetUI, HanlinExtensionContracts |
| Full original app SDK / app tests | HanlinExtensionContracts; existing runtime products remain unchanged |
| MiniApps original-source closure | HanlinExtensionContracts; existing runtime products remain unchanged |

Register both new packages in the aggregate SDK generator. Register all four new extension UI products and the Foundation-only contracts product. The widget canonical target is **HanlinScriptingWidgets**, with a separate `HanlinWidgetUI` target containing only a re-export. Do not rename the canonical widget module.

Set **`PRODUCT_MODULE_NAME = HanlinScriptingWidgetsHost`** only for the original widget executable entry target in Debug and Release. Keep its `PRODUCT_NAME`, extension bundle identifier, widget kind, principal/entry behavior and entitlements. This makes the original persisted implementation type identities (`HanlinScriptingWidgets.HanlinWidgetConfigurationIntent`, `HanlinScriptingWidgets.HanlinScriptPackageEntity`, `HanlinScriptingWidgets.HanlinRunScriptActionIntent`, and `HanlinScriptingWidgets.HanlinScriptActionEntity`) remain the same after extraction. Existing parameter names and scoped entity identifiers are unchanged; the original `widgetEntityMigrations` and unique short-ID action migration algorithms are preserved.

A widget executable declaring `WidgetBundle` and `some Widget` directly imports both `SwiftUI` and `WidgetKit`, in addition to its selected Hanlin products. These Apple protocol names are not supplied by the SDK facade import.

The shared `HanlinGenericLiveActivityAttributes` already belonged to `HanlinScriptExtensions` and keeps that identity. The share and notification targets retain their original local principal subclass names; their inherited implementation moves to the SDK.

## Cold-start host configuration

Use one `HanlinExtensionHost` dictionary in **each participating executable’s** Info.plist. The immutable `HanlinExtensionHostConfiguration.load(from:)` reads that executable only. Missing or malformed configuration throws; it never falls back to Hanlin’s container or route. Explicit `.hanlin` is available only for wrappers choosing the original policy.

| Dictionary key | Original Hanlin value |
| --- | --- |
| `AppGroupIdentifier` | `group.com.itorah.chavrusachat` |
| `WidgetKind` | `com.hanlin.scripting.widget` |
| `NotificationCategoryIdentifier` | `CHAVRUSA_REMINDER` |
| `VisionURL` | Main Hanlin: `chavrusachat://openVisionView`; omit in MiniApps and extensions unless that host provides this route |

The four original extension Info.plists contain the first three values. Root integration must add the dictionary to the main app and MiniApps Info.plists and adapt `HanlinApplicationSystemIntegrations` to the canonical value. App Group entitlements must independently permit the supplied group.

The public configuration has optional immutable `appGroupIdentifier`, `widgetKind`, `notificationCategoryIdentifier`, and `visionURL` properties; its corresponding initializer arguments default to nil. It exposes `init(infoDictionary:)`, `load(from: Bundle = .main)`, `requireAppGroupIdentifier()` and `requireWidgetKind()`. No global mutable installation is added.

No-argument `HanlinScriptExtensionStore()` and `HanlinCompactAgentConfigStore()` now load this process-bundle configuration. Explicit store `appGroupIdentifier`, `root`, and config-store `customURL` initializers remain. `HanlinCompactAgentClient(configuration:credentialResolver:)` retains its API and does not load a store during initialization. Its new `configurationLoader:` initializer reads the supplied loader per request. Without an explicit configuration or loader, streaming loads the current host’s configuration store as before. Generic widget actions validate the host group and widget kind before mutation, then call the unchanged canonical executor and reload the configured widget kind.

Existing Lorvex and Maktabah chat integrations do not initialize these extension stores or clients in their selected source closure. They require no new App Group or dictionary merely to use chat. Mounting an extension is an explicit host integration.

## App Intents registration

The `HanlinScriptExtensions` module exposes **`HanlinScriptExtensionIntentsPackage`**, registering its existing generic script/widget actions. The original widget implementation module exposes **`HanlinWidgetIntentsPackage`**, which includes `HanlinScriptExtensionIntentsPackage` and registers all moved original widget configuration, entity/query, and script action types.

The translation executable already includes `HanlinScriptExtensionIntentsPackage` through its local `HanlinTranslationIntents`. The widget executable already includes `HanlinWidgetIntentsPackage` through its local `HanlinScriptingWidgetIntents`.

An app executing the same foreground script actions should import HanlinWidgetUI and include `HanlinWidgetIntentsPackage.self` in its own `AppIntentsPackage.includedPackages`; hosts exposing only the existing generic shared actions can include `HanlinScriptExtensionIntentsPackage.self`. Root must compose these with the existing `HanlinApplicationIntentsPackage` registration where appropriate. No alternate action executor is introduced.

Apple documents [AppIntentsPackage registration](https://developer.apple.com/documentation/appintents/appintentspackage) and demonstrates moving an existing entity into a shared package in [WWDC25, Get to know App Intents](https://developer.apple.com/videos/play/wwdc2025/244/). The implementation additionally preserves the original Swift module identity instead of relying on an unverified renamed-module migration.

## Canonical resources

The original widget target had byte-identical copies of `ExpoWidgets.bundle`, `support.bundle/util.js`, and `support.bundle/moment.min.js`. Their canonical copies already belong to `HanlinScriptExtensions/Resources`, whose standalone and aggregate manifests copy these resources for `Bundle.module` loading. Only the three duplicate app-target copies are removed. Their byte counts and SHA-256 provenance are recorded in the extraction receipt. No resources are reconstructed.

All moved labels use the canonical `HanlinLocalization` bundle where explicit routing is required. App Intent metadata titles use `LocalizedStringResource` with the shared resource bundle. Original text and interaction callbacks remain unchanged.

## Evidence and remaining gates

The checked-in [source receipt](../../docs/agent-sdk/evidence/extension-source-extraction-20261123.json) records **49/49 original function/computed-property bodies** preserved across **11 source owners**, after only declared localization and host-store adaptations. It also records **35/35 Swift syntax parses**, localization-transform idempotency, and exact resource provenance. The new constructors and access modifiers are explicit public seams; the body comparison does not claim to typecheck them.

`Scripts/Extensions/inspect_source_preservation.swift` and `verify_source_preservation.py` reproduce the pinned original-to-canonical source comparison. The localization transformer accepts repeated `--source-root` arguments for scoped application without changing other work lanes.

Apple compilation, App Intents metadata extraction, extension principal instantiation, saved-widget continuity, and original UI acceptance remain required native gates. Source parsing is not runtime or visual proof. The root-owned combined native run will validate the integrated graph; this lane dispatches no duplicate CI. No eligible-device FoundationModels tool capability is claimed here.
