# Pass 3 source and ABI closure

| Path / symbol | Actual implementation | Verification |
|---|---|---|
| HanlinExpoRuntime / HanlinExpoWidgetNative | New narrow product owning original WidgetsViewRenderer -> ExpoSwiftUI.AnyChild, WidgetsChildView and FragmentView. Uses existing ExpoUI/Core/Worklets/JSI binary declarations and injects Hanlin native Button intents. | Installed local swiftinterfaces were inspected; actual iPadOS link, Mach-O extension safety and transitive loaded frameworks await Xcode. No duplicate binary target was added. |
| HanlinScriptingWidgets Xcode target | Explicitly links HanlinExpoWidgetNative. Shared HanlinScriptExtensions has no native Expo binary dependency. | Project graph edited; compilation pending. |
| ScriptWidget/Original | Source-copied RuntimeElement JSExport, original 29-tag renderer, element builders, attributes and utilities. | Source/blob manifest records deltas; native semantic outcomes pending. |
| HanlinScriptWidgetRuntime | Original $element/util/$main/$render/component-resolution lifecycle adapted to execution-owned contexts and frozen value transfer. Typed storage commits outside JSC. | Apple JSC/JSExport execution pending; Node source-function checks passed separately. |
| HanlinWidgetCompiler | Dedicated widget install compiler, pinned Babel, declared source formats, original cooperative AST guard visitor, Expo module adapter. | Node compiler/JSX callbacks passed; actual Swift import/install tests pending. |
| Store/actions/provider | Checked immutable programs, canonical configured instances, cross-process transactions, historical v1 shadow, source callbacks, pure prepared presentation. | Semantic Swift tests added; Apple run pending. |

See UPSTREAM_SOURCE_MANIFEST.json for every copied file/blob and local hash. Compiler resource and source fragments are attributed separately from complete copied files. Mixed subtree is DEFERRED_OPTIONAL; no ScriptWidgetSubtree surrogate is advertised.
