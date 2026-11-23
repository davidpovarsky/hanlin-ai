# Build and repair MiniApps with the installed host SDK

The Hanlin agent has five dedicated tools. They use the installed application's original SDK and compiler. The same validation service is called by import preflight in Hanlin AI and Hanlin MiniApps.

| Tool | Input | Result |
| --- | --- | --- |
| `get_miniapp_sdk` | Optional `engine`; optional SDK-relative `resource` | Exact installed package versions, actual declaration/documentation entry paths, compiler configuration, and host contract |
| `write_miniapp` | Optional absolute `project_path`; `files` array | Creates a project or updates its retained source; returns the writable `sourceRoot` |
| `validate_miniapp` | `engine`, absolute `project_path` | Whole-project TypeScript diagnostics with code, category, file, and one-based source locations |
| `build_miniapp` | `engine`, `project_path`; optional new `archive_path` | Revalidates, prepares runtime output, and creates an archive containing editable original source |
| `import_miniapp` | Exactly one of `archive_path` or `transfer_id` | Submits to the actual MiniApps importer or reads its durable import receipt |

Supported authoring engines are `expo`, `nativescript`, and `scriptwidget`. Legacy Scripting remains frozen. These tools do not add a custom home entrypoint.

## Author a project

1. Read `get_miniapp_sdk` for the intended engine. Read relevant original package declarations through `resource`. The compact default response includes a link to the full SDK inventory at `miniapp-sdk.json`; the complete inventory is available on request.
2. Call `write_miniapp` with source files. Omit `project_path` to create a dedicated writable project. Each file has a relative `path` and exactly one of `content` (UTF-8 text, including empty text) or `base64` (binary bytes).
3. Supply `script.json`, `package.json`, `tsconfig.json`, and `hanlin.authoring.json`. The latter declares the source entry, not the prepared JavaScript bundle:

```json
{
  "schemaVersion": 1,
  "engine": "expo",
  "entry": "index.tsx",
  "tsconfig": "tsconfig.json",
  "resources": ["data/catalog.json"]
}
```

4. Use a portable project tsconfig. The SDK's original declarations and compiler options are applied automatically; repository-relative paths to a developer's `node_modules` are unnecessary.
5. Validate, repair reported source locations, then build. Use the successful report's `archivePath` for import.
6. A `queued` receipt means delivery was queued. Query its `transfer_id` until the actual receiver reports `installed` or `failed`. Do not call a queued transfer installed.

`write_miniapp` preserves unrelated files and does not impose file-count or byte-count limits. Source paths are relative to the project. For an extracted source-bearing archive, it follows the archive's declared `sourceRoot` automatically, so a repair changes the original source rather than an unrelated file beside the compiled bundle.

## Original types and compiler policy

Module resolution is performed by the original TypeScript resolver, including package `exports`, conditional `types`, and exported subpaths. The SDK contains original installed dependency files and exact package versions used by the host build. SDK metadata distinguishes npm package versions from native bridge contract versions; those versions are not interchangeable.

The report records the effective `typecheck.strict`, `skipLibCheck`, and `dependencyDeclarationsChecked` values. Expo's checked template uses strict source checking and checks declaration bodies. NativeScript uses its original consumer configuration: strict source checking, original Core/platform globals, and `skipLibCheck: true`. This still typechecks project code against the original NativeScript and UIKit declarations. It does not certify that the upstream declaration packages are internally free of errors. An explicit project `skipLibCheck: false` remains honored and reports those library diagnostics.

ScriptWidget's environment includes the original component catalog and declarations tied to the actually embedded component implementations, plus separately identified Hanlin host globals. It is not an assertion that every service from the standalone upstream ScriptWidget application is embedded.

Type errors carry the original TypeScript code and source location. No successful archived validation receipt substitutes for a fresh import check.

## What each builder produces

### Expo

The builder invokes the original Metro and Babel packages from the installed SDK, including the host's original NativeScript/Worklets transforms. Metro runs with its Node filesystem crawler and one worker, without desktop Watchman or child worker processes. The original Metro result provides `bundle.js` and `bundle.js.map`. Assets are copied by React Native's original iOS asset packaging helper. Prepared version and bridge metadata comes from the actual SDK host contract.

### NativeScript

The original TypeScript compiler emits the project's ESM module graph and source maps. The canonical entry is `nativescript/app/bundle.mjs`. Actual installed JavaScript dependency packages are retained with their runtime dependency graph. The native host links its original shared Core and host-services modules; those shared runtimes are not duplicated into every package. Existing private package directories are preserved while missing shared modules are merged into their scopes.

A JavaScript package requiring an older patch of the same native runtime major/minor can run on a newer patch. This compatibility rule does not relax exact embedded native plugin requirements. New native frameworks still belong to the native application build; a JavaScript package build does not compile or install new native frameworks.

### ScriptWidget

The builder preserves the original JSX/TSX module closure, resources, and explicit widget ABI declaration. The actual import pipeline then invokes the original widget preparation/compiler route. The authoring build does not substitute another widget renderer.

## Import, diagnostics, and repair

Built archives retain `source/`, source maps, `hanlin.authoring.json`, and a compiler receipt. Source and compiled-file SHA-256 inventories bind the files to that build. Those inventories detect a changed/stale package; they are not a signature or proof of publisher identity.

Import preflight runs the actual compiler again when retained authoring source exists. The diagnostics sheet can send the original archive and structured diagnostics to a dedicated agent chat. The repair sequence is:

- Edit the returned `sourceRoot` with `write_miniapp`.
- Validate that source directory.
- Build a new archive from that source directory.
- Import the new archive and inspect its receiver receipt.

Editing retained source makes the old archive stale by design. Rebuilding creates a new consistent output and inventory. Existing bundle-only imports retain their compatibility path, with an explicit indication that original source typechecking is unavailable.

Compiler-used source files remain retained even when their path includes names such as `src/build` or `dist`. Generated authoring output directories are excluded. Binary resources and relative source links are materialized for reproducible repair.

## Desktop and CI

The same production Node module is used by the CLI:

```bash
node Scripts/MiniApps/stage-sdk.mjs --output=/absolute/MiniAppSDK
node Scripts/MiniApps/miniapp.mjs validate --sdk /absolute/MiniAppSDK --engine expo --project /absolute/project
node Scripts/MiniApps/miniapp.mjs build --sdk /absolute/MiniAppSDK --engine expo --project /absolute/project --report /absolute/build-report.json
```

Staging requires the exact original npm graphs installed by the host build and their declaration preparation steps. The desktop CLI archives with Python's standard ZIP library; the app uses its existing ZIPFoundation integration. Both invoke the same compiler/build implementation.

The modular text-search producer and its CI workflow use this source-preserving route. Portable compiler, archive, and Metro evidence is stored in `docs/miniapp-sdk/evidence/`. Native Apple runtime acceptance is recorded separately; portable test success is never reported as device installation or rendering success.
