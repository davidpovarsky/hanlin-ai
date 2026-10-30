# Pass 3 upstream source provenance

Expo is pinned to expo/expo@917a61b581baeb852aa4fe331da2c1395d824351, MIT. ScriptWidget is pinned to everettjf/scriptwidget@68f04194f00222558c44d5a832e7617a96f62574, Apache-2.0 with its retained historical notices. SwiftyJSON is 5.0.1, the exact version/revision found in pinned ScriptWidget's Package.resolved.

UPSTREAM_SOURCE_MANIFEST.json records original paths, Git blob IDs, local paths and SHA256, byte identity and adaptations. Expo license is retained beside its native source. ScriptWidget LICENSE/NOTICE are retained in ScriptWidget/Original. The original compiler guard visitor and runtime lifecycle/component-resolution code are adapted fragments, not an assertion that all editor, iCloud and system-service APIs were imported.

Expo native rendering preserves actual ExpoUI ViewProps/UIBaseView, native Text representation, slot children and original AnyChild identity. Hanlin changes widget source identity, injection of its typed AppIntent Button, widget-only context and visible diagnostics. The previous handcrafted AnyView switch has been removed. Actual extension-safe linkage has not yet been proven.

ScriptWidget's original native builders replace the handcrafted replicas. Narrow changes cover MainActor isolation, prepared-only context, Hanlin Button/Toggle intents, bounded image transport, native dynamic colors and safe malformed-gradient handling. Full parity requires rendered native semantic tests; source names are not evidence of parity.

The JS bundle uses original Expo stubs/decorators and a classic JSX createElement/key adapter. Both checked-in ExpoWidgets.bundle resources are produced by Scripts/Widgets/build-expo-bundle.mjs with the locked esbuild dependency and a fixed working root. No personal absolute path is an allowed bundle input/output annotation. Hanlin-only layout registry helper files are distinguished from copied upstream blobs in the manifest.
