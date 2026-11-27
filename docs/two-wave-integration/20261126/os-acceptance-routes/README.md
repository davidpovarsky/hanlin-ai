# Original OS acceptance routes — 26 November 2026

Audited product source: **c3f9076d3d8c5d0c29b002b6e20de2fb16f009bf**. This is a read-only route inventory. No native build, test, workflow dispatch, OS interaction or physical-device acceptance was performed by this audit. Exact selectors, original commands, prerequisites and source hashes are in [routes.json](routes.json).

## Existing routes on the Mac

| Route | Actual scope | Readiness and boundary |
|---|---|---|
| Three HanlinExpoProductionE2ETests widget methods | Shipping importer, real SpringBoard placement, original Expo source buttons and ScriptWidget Toggle with Hanlin terminated; screenshot/accessibility attachments | Existing original fixtures and setup are tracked. Use current source-qualified products. This is Hanlin's legacy identity/shared renderer, not standalone MiniApps or all new families. |
| HanlinEntrypointSystemSurfaceUITests — ten methods | MiniApps plus actual system apps: Expo/NativeScript × widget, Live Activity, Shortcut, share and translation; fresh challenge/five-engine durable completion | Original SurfaceExpo/SurfaceNativeScript fixture producer and external read-only observer remain unverified. Bare selector dispatch is not ready. |
| Original paired miniapp_complete route | Both products on one simulator, real AppGroup equality, runtime/authoring/native integration | Runner expects29 Hanlin and25 MiniApps cases; these are configuration counts, not an executed result. It does not drive the Shortcuts app. Separate product runs do not establish a paired pass. |
| Current package/MiniApps native suites | Queue/lease ownership, progress, cancellation, metadata, typed codec and runtime lifecycle | Useful bounded native evidence; actual Shortcuts indexing, saved Home Screen, Open When Run and snippet UI remain separate. |

The three existing SpringBoard selectors are:

- `AI_HLYUITests/HanlinExpoProductionE2ETests/testNativeLegacyWidgetWithHostTerminated`
- `AI_HLYUITests/HanlinExpoProductionE2ETests/testNativeExpoWidgetSourceActionsWithHostTerminated`
- `AI_HLYUITests/HanlinExpoProductionE2ETests/testNativeScriptWidgetBooleanWithHostTerminated`

The original producer is `node Scripts/Widgets/build-sample-packages.mjs`. The workflow `.github/workflows/validate-expo-runtime-spike.yml` supplies fixture staging, original test-without-building flags, attachments and authenticated state capture. Its preparation also invokes `resolve-upstreams.mjs --apply`; a fresh dispatch can change pins. To retain the current candidate, the native owner can use the existing exact test-without-building route, original fixtures and source-qualified products. This inventory introduces no workflow change or alternate harness.

## Ten-case companion prerequisites

The file-system-synchronized AI_HLYUITests group admits the existing source. It prepares a fresh challenge through the shipping UI and exchanges observation requests under the UI test runner's Documents/HanlinSystemSurfaceObservation/<runUUID>.

An external read-only observer must resolve actual installed package/generation/MCM identity and actual completion: fresh challenge, counter increment, invocation/receipt and all five original engines. The source forbids seeding grants, commands, queues or result receipts. No replacement observer or generated outcome was introduced.

Only the protected external owner `/Users/m1/builds/hanlin-current-entrypoints-20261126` is known. Neither the fixture producer/controller nor a terminal OS companion acceptance receipt was verified. Its unrelated product build failure is documented in the camera-conformance evidence.

The two Shortcut methods explicitly select **Run Script Action**, use legacy surface-intent/surface.run parameters, and force **en_US**. They do not test the new **Run MiniApp Action** intent or its saved toggle, typed output chaining, Home Screen launch or Hebrew layout.

## Remaining OS gates

| Gate | Existing bounded proof | Required actual OS work |
|---|---|---|
| New Run MiniApp Action and typed result chain | HanlinMiniAppsTests/MiniAppsShortcutIntentTests; HanlinMiniAppsTests/NativeScriptShortcutConcurrencyTests; HanlinPlatformContractsTests/HanlinShortcutValueCodecTests | Use actual Shortcuts UI on an available owned iOS27.2 simulator or signed device; native metadata/codec tests are not OS indexing/chaining proof. |
| Open When Run default, off/on behavior and saved persistence | New standalone supportedModes=[background,foreground(immediate)] and systemContext.currentMode branch; legacy Run Script Action remains foreground(immediate). | Actual new and saved Shortcuts UI action required. Inspect off/on behavior, save/reopen and process restart. Never infer a user foreground request from canContinueInForeground. |
| Saved Home Screen shortcut | Prepared saved package/action admission; expiring mailbox deep link remains an invocation link. | Actual Shortcuts Details > Add to Home Screen, then launch saved shortcut after process restart. Possible simulator UI coverage only if the real OS operation is available; final requested device acceptance remains separate. |
| Native snippet and legacy Wait result UI | AI_HLYTests/HanlinNativePresentationTests/testNativeSnippetHasIndependentDurableSessionsWithoutWidgetInstances; HanlinShowMiniAppSnippetIntent; HanlinInvocationSnippetIntent; HanlinAwaitInvocationResultIntent | Actual Shortcuts Show MiniApp Snippet and Run/Wait result chain interaction needed. Original legacy system-surface suite does not assert snippet controls. |
| Long-running OS progress and cancellation | HanlinScriptExtensionsTests/HanlinInvocationQueueTests plus MiniApps native ownership/executor tests | Actual running shortcut cancellation and progress, foreground close, background no-UI, terminal receipt and no late replay must be observed. Existing tests exercise the owner/store, not OS cancellation. |
| All8 widget families, new Expo Toggle, transparency and LKG OS refresh | Fixtures/Widgets/Hanlin-Expo-Widget-Interactive-Matrix.hanlinExpo; AI_HLYTests/HanlinOriginalExpoWidgetTests and renderer/package regressions | Place actual standalone widgets in supported OS families/surfaces and observe appearance, desired-value interaction and refresh. Accessory placement uses the actual lock-screen/gallery interaction; fixture compilation does not prove placement. |
| Live Activity and Dynamic Island | AI_HLYTests/HanlinOriginalScriptWidgetLiveActivityTests/actualActivityKitStartsUpdatesAndEndsTheOriginalProgram(); AI_HLYTests/HanlinNativePresentationTests/testOriginalDynamicIslandCapturesAllSevenNativeRegionsAndFunctionComponents | Native case invokes real ActivityKit API but is not a visual OS proof. Companion selects notification-centre/lock-screen UI; compact/minimal/expanded Dynamic Island still needs actual supported surface and screenshots. |
| HE/RTL system surfaces | MiniAppsShortcutIntentTests language cases en/he/zh-Hans; MiniAppsCrossAppPreferencesUITests/testPreferencesUsesEnglishAndHebrewNativeToolbarLayouts; HanlinNativeWidgetRendererTests/testOriginalShapesStacksImagesLinksAndModifiersMatchNativeReferences | Language strings/app toolbar/native RTL raster are bounded proof. Existing system companion forces en_US, so actual Hebrew Shortcuts/snippet/widget/foreground OS layouts remain open. |
| Locked physical device and background lifecycle | Native tests/Simulator provide bounded code and UI proof. | The authorized task's real-device, locked/background and signed extension acceptance remains a physical-device gate even when parts can be simulated. No fresh device inventory or physical pass is claimed by this audit. |

No verified automated selector for a gate does not mean the feature is impossible in Simulator. The actual Shortcuts/system app and surface must be observed on the selected runtime. The companion requires an OS-availability observation before marking an absent system app blocked; absent product registration on an available surface remains a product failure.

Where no existing automated path was found, an authorized operator can use the ordinary system UI and retain screenshots plus actual durable results. The requested signed physical-device and locked/background acceptance remains separate, even if portions can be demonstrated in Simulator. This audit does not claim a fresh physical-device inventory.

## Apple semantics

Apple documents [supported execution modes](https://developer.apple.com/documentation/appintents/appintent/supportedmodes.md), [immediate foreground execution](https://developer.apple.com/documentation/appintents/intentmodes/foregroundmode/immediate.md) and [actual current mode](https://developer.apple.com/documentation/appintents/intentmodes/current.md). Transition capability is not itself a recorded user request; the current implementation uses the actual selected mode.

Apple's [Home Screen shortcut guide](https://support.apple.com/en-mide/guide/shortcuts/apd735880972/ios) adds a saved Shortcut from its Details menu. [Widget debugging](https://developer.apple.com/documentation/widgetkit/debugging-widgets.md) distinguishes extension debugging from manual accessory placement. [Previews](https://developer.apple.com/documentation/widgetkit/previewing-widgets-and-live-activities-in-xcode.md) use supplied timeline/content states and do not establish installed OS execution. [ActivityKit guidance](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities.md) distinguishes Lock Screen and Dynamic Island presentations; the system chooses their actual presentation.

No raw inline-JavaScript route, frozen runtime activation, new harness, native job or dependency change was introduced.
