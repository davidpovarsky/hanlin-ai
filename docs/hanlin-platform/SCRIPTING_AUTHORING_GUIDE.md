# Authoring Hanlin Scripting packages

Hanlin accepts `.scripting` or `.zip` archives containing one unambiguous
`script.json`. Keep source and resources below one optional wrapper directory.
Use UTF-8 package-local `.ts`, `.tsx`, `.js`, `.jsx`, `.json`, and `.py` modules with
relative imports. Import the compatibility facade only as `scripting` and
Hanlin-specific additions only as `hanlin`.

Do not include npm dependencies, native addons, install scripts, symlinks,
absolute paths, encrypted entries, `eval`, dynamic imports, Node process APIs,
credentials, or generated secrets. Declare every capability needed by each
entrypoint. The user sees those requests before install, while the operating
system prompt appears only when the service is first used.

Original TS/TSX/JS entrypoints always use `scripting-jsc`; authors cannot ask
Hanlin to try another engine after failure. `index.py` uses `hanlin-python` and
requires a trust review. Hanlin-native manifests may explicitly choose
`hanlin-quickjs`, `hanlin-node`, or `hanlin-python`; Node/Python are trusted
worker profiles and do not render ScriptUI or execute in extensions.

Conventional entrypoints are `index.tsx`, `index.py`, `assistant_tool.tsx`, `widget.tsx`,
`app_intents.tsx` or `intent.tsx`, and `live_activity.tsx`. A package may expose
multiple assistant tools. Widgets and Live Activities render a bounded native
subset from extension-safe snapshots; they do not run Node or compile source.

## Troubleshooting

- **Archive rejected before Preview:** remove traversal, links, duplicate
  Unicode/case-normalized paths, encryption, excessive nesting, oversized
  entries, unsupported file types, or ambiguous manifests.
- **Unresolved module:** use a relative package-local import or the exact
  virtual module name. Arbitrary bare npm specifiers are denied.
- **API reported not yet implemented:** consult the generated compatibility
  matrix. Declaration/type presence is not a runtime support claim.
- **Permission denied:** verify the entrypoint declaration, local grant,
  context, origin, expiry, user gesture requirement, OS authorization and
  entitlement. Do not retry in a loop.
- **Widget shows “Open Hanlin”:** the node is outside the extension-safe
  subset and must continue in the foreground.
- **Compiler lane differs:** TypeScript 7.0.2 supplies host/CI compatibility
  typechecking. The pinned TypeScript 6.0.3 compiler supplies on-device project
  emission. Diagnostics disclose both; neither silently substitutes for the
  other and neither causes runtime fallback.

The current branch supports safe inspection and the host architecture but is
not yet an author-ready release: production on-device bundling, all worker
adapters, and the full acceptance suite remain mandatory.
