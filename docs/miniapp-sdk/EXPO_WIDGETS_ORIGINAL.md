# Original Expo Widgets in Hanlin

The foreground package imports the real `expo-widgets` package. The native host registers the original `WidgetsModule` in the real Expo AppContext. The original `Widget`, `LiveActivityFactory`, `LiveActivity`, WidgetKit renderer, JavaScriptCore runtime, layout registry and ActivityKit attributes are compiled in the `ExpoWidgets` Swift module, exposed by the `HanlinExpoWidgetsOriginal` product.

## Exact build identity

`Scripts/MiniApps/resolve-upstreams.mjs` resolves Expo's published dependency matrix, records the exact npm publications, refreshes original Swift/JavaScript sources by a three-way merge, updates the native locks and regenerates the host versions. `Scripts/Expo/prepare-ios-dependencies.mjs` produces the actual corresponding native frameworks and original widget JavaScript runtime. It does not reuse an older native framework under a newer version label.

`Scripts/Expo/build-original-widget-runtime.mjs` invokes the installed upstream `expo-widgets/scripts/build-bundle.mjs` and `build-layout-registry.mjs`. Its receipt binds the resource to the package lock, original producer and native source hashes. The prepared native artifact catalog retains this genuine resource bundle as host support.

The authoring SDK copies the exact installed original package, declarations, Expo Babel preset, Expo Metro transformer and transitive JavaScript closure. The `'widget'` directive is transformed by the original Expo Widgets Babel plugin. Both the source and the original Expo declaration bodies are checked. When an original modifier acquires the same name as a Hanlin addition, `sync-original-ui-exports.mjs` explicitly selects the original implementation and types.

The source inventory and extension-reachability audit files are historical snapshots with their own recorded commit. The generated `miniapp-sdk.json`, native source manifest, dependency locks and `upstream-resolution.json` describe the exact current host build.

## Installed-package identity

Public widget names remain the names authored by the package. Native storage names are derived from the product, actual installation ID, widget/activity kind and public name. Two installed MiniApps can use the same public name without overwriting one another. Concurrent foreground and embedded sessions of the same installation generation share their original widget state.

The host calls `reconcileRegistrations(installedIDs:activeGenerations:productIdentifier:)` after package changes. Disabled installations retain configuration but stop rendering; uninstalled installations remove their own registry, timeline, layout, configuration and image directory. An update retains the stable WidgetKit selection while the old generation remains inactive until the new code registers its layout. Native events and ActivityKit methods use the same current-installation identity.

The generic WidgetKit picker selects a registered original widget. `WidgetsEntryView(entry:configuration:)` passes the selected configuration into the original `environment.configuration` object. `widgetConfigurationOptions(name:parameter:fallback:)` and `setConfigurationParameterEnum` retain the original option storage and original names/value/subtitle types.

The original `WidgetLiveActivity` renders original `LiveActivityAttributes`. `HanlinExpoWidgetsIntentsPackage` exposes the original interaction intents to the apps and extensions. Existing other widget engines and their distinct ActivityKit attribute types remain separate products.

## Runtime boundaries

Expo's widget layout is evaluated in its original isolated synchronous JavaScriptCore environment. Its original Expo UI components, pure functions, environment, timeline data and interaction handlers are available there. Foreground React Native APIs and asynchronous app operations execute in the MiniApp's foreground Expo runtime. This follows the upstream renderer architecture.

Native operation errors are returned by the original module and appear in the probe and normal authoring/runtime diagnostics. ActivityKit authorization and platform support are determined by the actual operating system.

## Verification

`node Scripts/Expo/build-probe.mjs --widgets-only` runs strict positive and negative original API checks and produces two real Metro bundles. The packages call the original widget constructor, timeline round-trip, configuration options, snapshot and reload APIs. Their Live Activity button calls the original start, instance query, update, token and end methods. Both packages deliberately share public names, and each checks prior timeline ownership before writing.

A JavaScript/TypeScript build is not an Apple runtime pass. The native acceptance suite separately imports both packages, relaunches the first to check retained ownership, executes the original ActivityKit path, and checks the actual original WidgetKit storage/parser/provider and packaged JavaScript resource.

Original references:
- https://docs.expo.dev/versions/latest/sdk/widgets/
- https://github.com/expo/expo/tree/main/packages/expo-widgets
