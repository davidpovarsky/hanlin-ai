# Pass 3 source and ABI closure

| Path / symbol | Actual implementation | Verification |
|---|---|---|
| HanlinExpoRuntime / HanlinExpoWidgetNative | New narrow product owning original WidgetsViewRenderer -> ExpoSwiftUI.AnyChild, WidgetsChildView and FragmentView. Depends only on the source-built HanlinExpoWidgetSubset and injects Hanlin native Button intents. Foreground binary declarations remain owned by the existing package. | Real arm64 iOS 27 Simulator source compile/link of BOTH modules passed in 41239669157 at 5bfcf03b. Source subset has APP_EXTENSION_SAFE and Apple-only load commands. Old binary audit is retained as a rejected design; final appex closure/OS results remain open. |
| HanlinScriptingWidgets Xcode target | Explicitly links HanlinExpoWidgetNative. Shared HanlinScriptExtensions has no native Expo binary dependency. | Actual app/appex build-for-testing passed in 41239679485 at 5bfcf03b; final native test/audit outcomes remain pending. |
| ScriptWidget/Original | Source-copied RuntimeElement JSExport, original 29-tag renderer, element builders, attributes and utilities. | macOS source and native chart/grid/date assertions passed in 41242542513; broad 29-tag raster evidence is PARTIAL. |
| HanlinScriptWidgetRuntime | Original $element/util/$main/$render/component-resolution lifecycle adapted to execution-owned contexts and frozen value transfer. Typed storage commits outside JSC. | Actual JSC source actions, typed Boolean state and cold timeline storage passed in 41242542513. Helper JSON assertion and GIF visible-pixel rerun passed in 41239674500. |
| HanlinWidgetCompiler | Dedicated widget install compiler, pinned Babel, declared source formats, original cooperative AST guard visitor, Expo module adapter. | Seven Node checks and real seven-archive analysis/five positive installations passed in 41242542513. |
| Store/actions/provider | Checked immutable programs, canonical configured instances, cross-process transactions, historical v1 shadow, source callbacks, pure prepared presentation. | Matching macOS state/identity/rollback/concurrency tests passed in 41242542513; SpringBoard execution remains open. |

See UPSTREAM_SOURCE_MANIFEST.json for every copied file/blob and local hash. Compiler resource and source fragments are attributed separately from complete copied files. Mixed subtree is DEFERRED_OPTIONAL; no ScriptWidgetSubtree surrogate is advertised.

## ScriptWidget API context

| API | Actual bounded extension contract | Executed evidence / limit |
|---|---|---|
| `$render`, `$element`, JSX custom components | Original JSExport element/props/children and util.js; freeze only after execution | Real Dashboard/Actions imports and preparation passed in 41242542513. Native body never holds JSValue. |
| `$storage` | Typed get/set/remove, string/JSON, keys/clear and CAS; identity-scoped atomic state revision in action AND timeline transactions | Boolean source actions and cold timeline writes/removal passed in 41242542513. |
| `$file` | Read-only exists/read/readJSON from verified immutable packaged bytes | Helper test exercises JSON read; canonical number assertion passed in 41239674500. Mutable filesystem/iCloud APIs are outside this subset. |
| `$import` | Install-compiled local helpers only, at most 64 evaluations per invocation | Real JSExport helper execution passed with JSON/file/storage assertions in 41242542513. No arbitrary runtime paths. |
| `$getenv` | Selected family/timestamp, published environment and authoritative instance settings | Hanlin context adapter; this is not the full foreground device environment. |
| `$widget` | Read-only Hanlin environment object | Hanlin addition, not a claim of an upstream global with this name. |
| `$fetch`, `fetch`, `$http` | Original text/base64 or getResponse `{body,status,headers}` Promise shape; HTTP(S), ephemeral session, four requests, five-second invocation deadline, <=2.5 seconds/request, 1 MiB body/response | Native transport source compiles. HTTP transport/redirect semantic tests remain NOT_TESTED; no external network success is claimed. |
| Images/GIF, moment, date | Verified packaged resources, original native pipelines, pinned moment resource and original date semantics | Date/grid and native chart assertions passed. GIF frame/visible-pixel assertions passed in the latest package run. OS animation cadence remains an OS/device gate. |
| XML, system/device/contact/location/calendar/Health/iCloud services | Not installed in this widget subset; scripts get a controlled preparation failure if they require them | No fabricated success or new Hanlin approval UI. Host-only service parity is not claimed. |

The runtime target no longer depends on the install-time compiler and no longer embeds unused Babel core.js copies. The importer owns HanlinWidgetCompiler; the extension contains only the execution resources it reads. Cooperative JSC deadlines do not imply preemption of every native built-in.
