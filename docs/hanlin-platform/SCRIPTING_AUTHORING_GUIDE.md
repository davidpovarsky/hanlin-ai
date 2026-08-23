# Authoring Hanlin Scripting packages

Hanlin accepts `.scripting` or `.zip` archives containing one unambiguous
`script.json`. Keep source and resources below one optional wrapper directory.
Use UTF-8 package-local `.ts`, `.tsx`, `.js`, `.jsx`, and `.json` modules with
relative imports. Import the compatibility facade only as `scripting` and
Hanlin-specific additions only as `hanlin`.

Do not include npm dependencies, native addons, install scripts, symlinks,
absolute paths, encrypted entries, `eval`, dynamic imports, Node process APIs,
credentials, or generated secrets. Declare every capability needed by each
entrypoint. The user sees those requests before install, while the operating
system prompt appears only when the service is first used.

Conventional entrypoints are `index.tsx`, `assistant_tool.tsx`, `widget.tsx`,
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
- **Install reports TypeScript 7 unavailable:** this is the current closed
  compiler gate, not a package error. Hanlin will not silently compile with
  TypeScript 6 or a one-shot transpiler.

The current branch supports safe inspection and the host architecture but is
not yet an author-ready release: exact TypeScript 7 compilation on iOS and the
full acceptance suite remain mandatory.
