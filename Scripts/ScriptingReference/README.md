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

Verify the portable repository snapshot without the source directory:

```powershell
node .\Scripts\ScriptingReference\verify-scripting-reference.mjs
node .\Scripts\ScriptingReference\build-scripting-inventory.mjs --check
node .\Scripts\ScriptingReference\validate-scripting-examples.mjs
```

`build-scripting-inventory.mjs` uses a deterministic Phase 0 declaration lexer.
It creates traceable obligations, not runtime-support claims. Compiler-backed
symbol analysis and executable fixture lanes are Phase 6 gates.
