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

Actual Swift/UIKit parsing and Objective-C++ syntax from the preceding lane
were reported before the lifecycle correction. Fresh Apple verification and
the full 23-case real producer acceptance remain to execute after current
PR19 integration. The original 45325776062 artifact evidence remains historical,
not a pass for this changed source.
