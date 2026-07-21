#!/usr/bin/env bash
set -euo pipefail

cat >&2 <<'MESSAGE'
The production RuntimeCore bundle is assembled by the split GitHub Actions jobs in
.github/workflows/build-runtime-bundle.yml. This wrapper intentionally does not run
the device and simulator Node/V8 builds sequentially.

For local diagnostics, run prepare-node-source.sh once, then run one invocation of
build-node-slice.sh per isolated build machine. Use assemble-runtime-bundle.sh only
after both slice artifacts, the Python artifact, and RuntimeHostResources.zip exist.
MESSAGE
exit 64
