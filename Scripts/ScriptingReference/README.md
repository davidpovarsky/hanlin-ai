# Scripting reference tooling

These offline Node.js tools import and verify the user-authorized Scripting
compatibility baseline. They never modify the source workspace and never copy
`node_modules`, platform executables, archives, caches, editor artifacts,
temporary files, or detected secrets.

The explicit mapping in `source-map.json` selects the canonical root-level
`dts/`, `docs/`, `scripts/`, `tsconfig.json`, `package.json`, and
`package-lock.json`. This resolves the byte-identical backup subtree found
during Phase 0 without depending on its Unicode/RTL folder name.

Import from the currently authorized developer source:

```powershell
node .\Scripts\ScriptingReference\import-scripting-reference.mjs `
  --source "C:\Users\DAVID\Code\ScriptingProjects"
```

The environment variable `HANLIN_SCRIPTING_REFERENCE_ROOT` can replace
`--source`. The absolute path is local provenance only; app and package runtime
code must use repository or bundle-relative resources.

Verify source-to-repository drift without writes:

```powershell
node .\Scripts\ScriptingReference\import-scripting-reference.mjs `
  --source "C:\Users\DAVID\Code\ScriptingProjects" `
  --check
```

Update only the five declarations from a current app export while retaining the
authorized compiler, documentation, and example snapshot:

```powershell
node .\Scripts\ScriptingReference\update-scripting-types.mjs `
  --source "C:\Users\DAVID\dts" `
  --exported-at "2026-08-25T02:00:21+03:00"
```

The updater reads the export directory without modifying it, records byte-level
provenance in `CURRENT_TYPE_EXPORT.json`, and gives the combined baseline a new
identity. Add `--check` to verify drift without writes.

Verify the portable repository snapshot without the source directory:

```powershell
node .\Scripts\ScriptingReference\verify-scripting-reference.mjs
node .\Scripts\ScriptingReference\build-scripting-inventory.mjs --check
node .\Scripts\ScriptingReference\validate-scripting-examples.mjs
```

Typecheck extracted acceptance packages against all five current declarations:

```powershell
node .\Scripts\ScriptingReference\typecheck-acceptance-packages.mjs `
  --directory .\artifacts\real-scripting-inputs
```

Verify the byte-for-byte copies of the five captured user projects:

```powershell
node .\Scripts\ScriptingReference\verify-user-provided-projects.mjs
```

Their immutable archives, inventory, source-project classifications, and staged
runtime results live under
`Reference/ScriptingCompatibility/Acceptance/UserProvided/`. Extract originals
only into a temporary or ignored build directory; never edit them in place.

`build-scripting-inventory.mjs` uses a deterministic Phase 0 declaration lexer.
It creates traceable obligations, not runtime-support claims. Compiler-backed
symbol analysis and executable fixture lanes are Phase 6 gates.

## Fast runtime validation

The JavaScriptCore application session and its native service adapters are in
the `HanlinScriptingApplicationRuntime` SwiftPM target. The extension-safe
Widget and Live Activity renderer is compiled by `HanlinScriptExtensions`.
Neither target requires building the full application.

On macOS with the repository Xcode toolchain selected:

```bash
swift build --package-path Packages/HanlinPlatform --target HanlinScriptingApplicationRuntime
swift build --package-path Packages/HanlinPlatform --target HanlinScriptExtensions
swift test --package-path Packages/HanlinPlatform --filter HanlinScriptingApplicationRuntimeTests
node --test Scripts/ScriptingReference/Tests/*.test.mjs
```

The manually dispatched `Validate Scripting Runtime` GitHub Actions workflow
runs this lane and restores a SwiftPM compiler cache keyed by Xcode and the
isolated runtime inputs. Use the full iOS workflow only for meaningful app,
Simulator, extension, archive, or IPA checkpoints.
