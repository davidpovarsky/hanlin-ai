# NativeScript package/window source checkpoint

Owner: ChatGPT native runtime lane; Oracle worktree
`hanlin-miniapps-final-native-20261125`.

This checkpoint preserves the existing source work after continuation.
It does not certify native application acceptance. The native contract is
23 cases: original20, two added distinct-package UI cases, and one lifecycle
capture regression. No prior passing case is automatically reused: the runtime,
loader, package preparation and new Apple toolchain changes affect the scope.

Lightweight validation performed on Oracle:
- git diff --check: exit0.
- Node --check on seven modified host/factory/fixture scripts: all exit0.
- ast.parse on four modified preparation/export/acceptance Python scripts: pass.
- All three prepared NativeScript archives exactly match their source trees.

Fresh Apple syntax verification on commit8557d605c passed at2026-11-25T05:17:12Z:
nine Swift files parsed, and the actual Objective-C++ lifecycle implementation
passed clang syntax against iOSSimulator27.0, using Xcode27.0(27A266a).
The complete source hashes and commands are retained in
`apple-syntax-8557d605c.json`. This is syntax-only evidence. The full23-case
real producer acceptance was subsequently dispatched on integrated571a1ab7;
its separate original app result is still pending. The original 45325776062 artifact evidence remains historical,
not a pass for this changed source.


## Actual integrated Mac attempts through 9ef80-03

The original native helper was executed on integrated571a and9ef80. No
application test case has executed yet: dependency/cache admission and local ABI
contamination prevented a complete app build. The real compiler logs, xcresults,
source identities, screenshots and preserved-cache inventories are archived on
Oracle with exact hashes in `native-build-attempts-through-9ef80-03.json`.

The169 passing Host controls and successful SDK example/source-graph checks do
not replace the23 required native cases. No producer export, distribution
signing success or TestFlight delivery is claimed by this checkpoint. A new
exact-source run is required after the owned local compiler products are
invalidated. Original third-party binaries and source work remain preserved.
