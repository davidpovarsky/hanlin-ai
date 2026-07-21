#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly HOST_SOURCE="${REPOSITORY_ROOT}/AI_HLY/Downstream/MCP/Runtime/Host"
readonly WORK_ROOT="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/hanlin-runtime-host"
readonly OUTPUT_ROOT="${REPOSITORY_ROOT}/build/runtime-host"

rm -rf "${WORK_ROOT}" "${OUTPUT_ROOT}"
mkdir -p "${WORK_ROOT}" "${OUTPUT_ROOT}"
cp "${HOST_SOURCE}"/*.mjs "${HOST_SOURCE}/package.json" "${HOST_SOURCE}/package-lock.json" "${WORK_ROOT}/"
cp -R "${HOST_SOURCE}/Tests" "${WORK_ROOT}/Tests"

(
  cd "${WORK_ROOT}"
  npm ci --omit=dev --ignore-scripts --ignore-workspaces --no-audit --no-fund
  npm test
  rm -rf Tests
  find . -type f -print | LC_ALL=C sort | zip -X -q "${OUTPUT_ROOT}/RuntimeHostResources.zip" -@
)

host_sha256="$(shasum -a 256 "${OUTPUT_ROOT}/RuntimeHostResources.zip" | awk '{print $1}')"
printf '%s  %s\n' "${host_sha256}" "RuntimeHostResources.zip" > "${OUTPUT_ROOT}/runtime-host.sha256"
node -e '
  const fs = require("node:fs");
  const [file, hash, nodeVersion] = process.argv.slice(1);
  fs.writeFileSync(file, `${JSON.stringify({
    nodeVersion, archiveSha256: hash, npmInstall: "npm ci --omit=dev --ignore-scripts --ignore-workspaces --no-audit --no-fund",
    tests: "passed",
  }, null, 2)}\n`);
' "${OUTPUT_ROOT}/host-metadata.json" "${host_sha256}" "$(node --version)"

rm -rf "${WORK_ROOT}"
echo "Prepared RuntimeHostResources.zip (${host_sha256})."
