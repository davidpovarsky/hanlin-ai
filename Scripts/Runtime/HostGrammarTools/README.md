# Build-only Yarn grammar compiler

PEG.js 0.10.0 is the original compiler used by the pinned @yarnpkg/parsers 3.1.0
publication. This separate lock installs one build tool; it is never included in
RuntimeHostResources.zip or used to compile user code on the device.

`prepare-runtime-host.sh` installs it with `npm ci --ignore-scripts`, applies the
authenticated grammar patch and compiles its parser with the exact expected
output SHA-256. The archive validator rejects accidental compiler inclusion.
The original PEG.js MIT license is retained in the Host archive.

To reproduce the patch, install this lock with `npm ci --ignore-scripts
--workspaces=false`, then run `node Scripts/Runtime/generate-yarn-multiline-patch.mjs`
from the repository root. The generator first reproduces the entire original
published parser byte for byte. `--write` updates the authenticated manifest;
without it the command verifies reproducibility. Normal Host preparation also
performs this check. `--root` and `--compiler-root` support isolated build trees.

The extension handles LF/CRLF command boundaries, blank lines, comments, quoted
newlines, escaped line continuations, and continued pipelines/logical operators.
The original source reaches the existing Yarn interpreter; no AST stringify or
global newline substitution is used. This does not claim full Bash grammar.
