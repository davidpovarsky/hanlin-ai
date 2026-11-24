# MiniApp SDK and original library authoring

## Active scope

The active engines are **Expo / React Native / Expo UI**, **NativeScript**, and **ScriptWidget**. Their original libraries, declarations, compilers and native host integrations are the implementation authority. Existing Hanlin facades connect these libraries to the two original products.

Dedicated legacy Scripting-JSC / ScriptUI development is frozen. Existing code, stored packages and shared services are retained. A custom home entrypoint and expansion of the optional full Apple SDK type generator are outside this work.

## Use the SDK installed with the host

Call `get_miniapp_sdk` with the desired engine before creating or changing a package. Its response identifies the actual compiler, package versions, host contracts, declaration entrypoints and documentation paths. Use `resource` to read the original declarations or documentation. The complete file inventory is available as `miniapp-sdk.json`; the ordinary response summarizes it so the agent can navigate it without receiving tens of thousands of file records.

The SDK is prepared from the same inputs as the native host. It includes original npm declarations and tooling, native types already supplied by those libraries, Hanlin's actual bridge declarations, and the installed ScriptWidget component/API declarations. A declaration is not proof that an arbitrary new native module is present in a shipped app. Consult the host contract returned for that engine.

Versions written in an older guide or historical audit are not the authority for a newly built host. Read the exact installed manifest. In particular, npm package versions, a bridge's public contract version and the native ABI identity are distinct values.

## Original-library updates during the app build

`Scripts/MiniApps/resolve-upstreams.mjs` resolves current original sources before native dependency preparation. Expo's own dependency matrix supplies the compatible React/React Native and related versions. Native source revisions, npm publications, native artifact inputs, generated host versions and declaration inputs are recorded together.

The source refresher preserves original implementations and the existing, explicit Hanlin namespace/host adapters. A real source conflict must be reconciled; reporting an old framework as a newer version is not a successful update. The build produces the native frameworks, original source bundles and SDK from those resolved inputs. See [Original upstream build](ORIGINAL_UPSTREAM_BUILD.md).

A new native dependency becomes available through a host build. A MiniApp archive contains its authored JavaScript/TypeScript, resources, engine contract and compiled bundle; its authoring operation does not invoke Xcode on the phone.

## Agent tools

| Tool | Input and result |
| --- | --- |
| `get_miniapp_sdk` | Optional `engine`, optional SDK-relative `resource`. Returns the current host's actual types, documentation and version contract. |
| `write_miniapp` | Optional `project_path`, and `files` with a relative `path` plus either UTF-8 `content` or binary `base64`. Creates a project when no path is given. Returns the editable `sourceRoot`. |
| `validate_miniapp` | `engine` and absolute `project_path`. Runs the original TypeScript compiler and package-consistency checks, with structured code/file/line/column diagnostics. |
| `build_miniapp` | `engine`, `project_path`, optional new `archive_path`. Validates, builds with the original engine toolchain, and retains sources, maps and resources in the resulting archive. |
| `import_miniapp` | Either `archive_path` to queue a package in Hanlin MiniApps, or `transfer_id` to read the actual installation receipt. |

The five tools use the original tool catalog and agent execution pipeline. They do not add a Hanlin approval prompt or a file-count/size quota.

### Authoring sequence

1. Read the selected engine's SDK contract and original declaration entrypoints.
2. Create `script.json`, `package.json`, `tsconfig.json`, the entry source, resources and `hanlin.authoring.json` with `write_miniapp`.
3. Validate the project. Correct the reported source locations using the returned `sourceRoot`.
4. Build. Expo uses original Metro/Babel; NativeScript emits the module graph for the original Core runtime; ScriptWidget retains source for its original widget compiler.
5. Import the returned `archivePath`.
6. Query the returned transfer ID until the receiver reports its actual result. `queued` or opening a URL does not mean `installed`.

A minimal authoring descriptor is:

```json
{
  "schemaVersion": 1,
  "engine": "nativescript",
  "entry": "index.ts",
  "tsconfig": "tsconfig.json"
}
```

Use `expo` with a TSX entry or `scriptwidget` for those engines. Engine-specific package fields and dependency versions come from the installed SDK. Source-bearing imported packages have an outer descriptor pointing at their retained `source/` directory. Passing that extracted archive root to the write tool targets its editable source; unrelated files are preserved.

For an external development environment, `Scripts/MiniApps/miniapp.mjs` uses the same authoring module and staged original SDK as the application. It is not a separate typechecker or implementation of the engines.

## Typechecking and import diagnostics

The project is checked against actual original declarations. NativeScript's base configuration follows its upstream declaration-check policy while checking authored source strictly; projects can explicitly request declaration checking as well. The validation report identifies `strict`, `skipLibCheck` and whether dependency declarations were checked. Expo strict declaration validation and actual Metro production are separate operations.

An archive that carries source is checked again during import. A supplied success report is not accepted as a replacement for the current compiler. Source hashes and compiled hashes detect inconsistent package contents; they do not identify a trusted publisher.

The native diagnostic sheet groups package and compiler findings by file, with severity, stable error code, one-based source location and the original message. It retains malformed archives too. Its repair button sends the exact original archive and diagnostic report into a dedicated conversation in Hanlin AI. The original composer and agent then use the tools above to repair, rebuild and return the package. See [Import diagnostics and repair](IMPORT_REPAIR.md).

Compiled JavaScript without original TypeScript cannot reveal erased TypeScript types. Its manifest/runtime compatibility can still be checked, and the sheet describes which check actually ran.

## Entry points and native surfaces

The current integration connects ordinary launch, declared Share actions, App Intents/Shortcuts, package-defined native snippets and translation panels, widgets and Live Activities. The standalone MiniApps target includes its own Share, Translation and Widgets extensions using its own product storage namespace.

Declared native presentation programs are compiled during import with the original Expo Widgets or ScriptWidget compiler, published as immutable shared artifacts, and run with separate invocation state. Native snippets use real App Intents for their controls. The translation panel keeps editable input and native results inside the extension, and calls the original Apple context for expansion and text replacement. Foreground continuation remains available for packages without a native presentation. See [Current surface implementation](../miniapps/entrypoints-and-system-surfaces.md).

Original ScriptWidget Live Activities use the original component renderer for the Lock Screen and all seven `$dynamic_island` regions. From Expo or NativeScript, call `hostServices.liveActivities.start({scriptWidgetEntrypointID: "widget", state: {count: 1}})` (or the equivalent `createHostServices()` facade). The installed default instance is available without placing a widget on the Home Screen. Declared native button and toggle actions commit actual state and refresh the activity. Prepared trees are retained as immutable artifacts; ActivityKit carries their small content reference.

The imported modular-search sample retains its editable original logic modules, grouped results, text expansion, version selection and pagination. Its native system snippet uses an explicit Load more action in place of the original Scripting on-appear sentinel. Native code integration and native execution evidence are separate; consult the recorded Apple acceptance run before reporting a product pass.

## Guides and evidence

- [Expo authoring](../hanlin-expo-runtime.md)
- [NativeScript authoring](../hanlin-nativescript-guide.md)
- [ScriptWidget authoring](SCRIPTWIDGET_AUTHORING.md)
- [Hanlin Expo UI facade](../../Packages/HanlinExpoUI/README.md)
- [Original-library build and provenance](ORIGINAL_UPSTREAM_BUILD.md)
- [Diagnostic and repair contract](IMPORT_REPAIR.md)
- [Portable authoring evidence](evidence/2026-11-23-authoring-portable.json)
- [Executed portable transfer tests](evidence/authoring-repair-20261123/transfer-tests.json)

Native acceptance is defined by the `miniapp_authoring` scope of `validate-app-split.yml`. It builds both actual products and exercises original NativeScript/Expo controls, embedded authoring tools, a malformed archive, real source diagnostics, the sheet and repair/import handoff on one iPad Simulator. Its recorded run and xcresult determine PASS/FAIL; source wiring, portable tests and syntax parsing do not establish native success.

Older [source inventory](source-inventory.json), [reachability audit](extension-reachability.md), and dated handoffs remain historical snapshots. Their old version numbers and disconnected-surface findings must not override the installed SDK manifest or current source/evidence.

### Embedded Expo results

Declared Expo embedded-result entrypoints receive ordinary React Native root props typed as `HanlinExpoRootProps` from `@hanlin/expo-ui`. The optional `hanlin` object contains `kind: "embeddedResult"`, the declared handler, canonical package ID, actual installed ID/generation, original JSON payload, and an optional result reference. The original Expo session owns the React root for that presentation and shuts down when the embedded result is dismissed. Foreground Expo entrypoints continue to receive ordinary root props.
