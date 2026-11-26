# Widget wave 2: implementation and validation boundary

Base: c34dd6ae752b3ab3ebc001743fc62c72fc48a203.
This branch adds capabilities to the original Expo Widgets/ScriptWidget adapters and shared widget SDK.
It introduces no separate renderer or foreground JavaScript runtime.

## Implemented surface

| Capability | Source behavior | Evidence and remaining gate |
| --- | --- | --- |
| Original Expo Toggle | The existing original Toggle component keeps its props/children/modifiers. A small widget-only adapter preserves the callback return; native SwiftUI Toggle uses SetValueIntent and the intended Boolean. | Both retained original runtime bundles execute true/true/false sequences, isolation, duplicate-target, disabled, failure and asynchronous-return cases. Apple macro compilation and SpringBoard taps remain pending. |
| Prepared Expo Toggle | The same JavaScript adapter feeds the existing prepared renderer; declared expoCallback actions carry the intended value through HanlinSetWidgetValueIntent and the original action executor. | Original/prepared JavaScript behavior tested together. Native action execution remains a requested gate. |
| Buttons and Refresh | Original event-only and props-returning Buttons remain supported. widgetRefresh: true on the original Button uses WidgetReload. A prepared refresh uses a declared reload target. LiveActivityButton remains on its original path. | Existing Button callback checks run beside Toggle. WidgetKit schedules refresh requests; an exact update time is not promised. |
| Families | Shared program validation, TypeScript contracts, timeline provider and both widget configurations accept systemSmall, systemMedium, systemLarge, systemExtraLarge, systemExtraLargePortrait, accessoryCircular, accessoryRectangular and accessoryInline. | New original SDK fixture renders all eight through both actual runtime bundles. Picker availability and physical layouts require the OS/device that supports each family. |
| Native components | Original Label, ProgressView and Gauge receive their actual child slots. Chart, stacks, links, image/SF Symbol and original modifiers remain native. | The responsive interactive matrix fixture combines these controls, clear container background and tinted image mode. Existing native renderer test now imports that real archive. |
| Container transparency | ScriptWidget root background is passed to its existing widget container modifier. The host no longer covers an authored Expo container background with an unconditional opaque container. App preview use remains explicit. Both widget configurations allow the system to remove their container background. | Installed iOS 27.0 headers verify the public WidgetKit APIs. Actual light/dark/tinted wallpaper screenshots remain pending. No iOS 27.2 or widget glassEffect visual result is claimed. |
| Original Expo timeline/LKG | Installation namespace, generation, layout digest, timeline and successful rendered node are stored under a cross-process lock with atomic hashed envelopes and one verified previous record. Last successful content is keyed by family/appearance/configuration and its controls are disabled while retained. | Native regression methods cover concurrent intended values, callback rollback, invalid timeline, cross-widget/configuration isolation, changed layout, identical-layout generation upgrade and disabled installation. They are prepared, not reported executed here. |

## Timeline identity and storage rules

Timeline props and an opaque namespace/generation/layout proof are captured in the same locked transaction.
Entries retain this proof. Rendering and native interaction validate it against the current record before executing source.
Reusing the same layout string after a package upgrade cannot make old captured props current.

A corrupt or superseded versioned record cannot migrate unqualified legacy UserDefaults state.
Legacy migration is allowed only when no versioned record exists and the current registration is in its first generation.
The original UserDefaults wire is still mirrored for the original public API, under the transaction lock.

The state directory is opened from the OS App Group container through descriptor-relative no-follow directory traversal.
Lock/current/previous files cannot be symlinks. Temporary writes use exclusive creation, file sync and descriptor-relative rename.
Failed callbacks do not commit desired values. Failed refresh/render may use only a matching retained successful node.
Removal, disabled installation, a new generation, changed layout or changed appearance/configuration cannot use another identity's retained node.

The parallel prepared-engine LKG implementation is a separate integration commit owned by the Shortcuts/lifetime worker.
This report does not count that worker's native tests as executed evidence.

## Executed portable gates

- node --test Scripts/Widgets/Tests/interactive-toggle.test.mjs: 10 methods, using both actual retained original runtime bundles, the real Babel/compiler resources, and the single shared adapter.
- Strict TypeScript consumer against the retained original @expo/ui/swift-ui declarations: valid Toggle/Refresh/portrait contracts compile; non-Boolean Toggle and an unknown family are expected type errors.
- swiftc -frontend -parse on changed Swift sources: syntax only on Linux. This is not Apple SDK type checking.
- node Scripts/Widgets/build-sample-packages.mjs: deterministic real package generation. Existing samples retain their intentionally scoped home-screen families; the new matrix declares all eight.

Raw command results and exact source hashes are stored beside this report. The source hash manifest excludes evidence files to avoid a recursive digest.

## Requested native gate

Reuse the root-owned original app build/controller and its compatible native dependency cache.
Affected modules: ExpoWidgets, HanlinScriptContracts, HanlinScriptExtensions, HanlinExpoWidgetNative, HanlinScriptingWidgets.
ExpoWidgets now depends on HanlinScriptContracts for the single shared adapter resource.
Regenerate the canonical SDK source inventory/export at integration, with that dependency and resource included.

Focused methods:

- AI_HLYTests/HanlinOriginalExpoWidgetTests (three methods).
- AI_HLYTests/HanlinNativeWidgetRendererTests/testInstalledExternalSourceRendersThroughAnyChild (now includes the interactive matrix archive).
- Existing affected component methods testOriginalChartAndGaugeReceiveTheirTypedNativeData and testOriginalLabelAndProgressKeepTheirPreparedChildren.

Required system acceptance remains real widget placement/picker, intended true/false taps without opening the app,
two independent installations/configurations, cold launch/restart, VoiceOver and native failure restoration,
plus light/dark/tinted screenshots including supported portrait/landscape and accessory placements.
A preview raster, a compiled target or portable JavaScript test does not substitute for these device/system results.
