#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly HOST_SOURCE="${REPOSITORY_ROOT}/AI_HLY/Downstream/RuntimeCore/Node/Host"
readonly WORK_ROOT="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/hanlin-runtime-host"
readonly OUTPUT_ROOT="${REPOSITORY_ROOT}/build/runtime-host"

readonly NODE_FINGERPRINT="$(node -p 'JSON.stringify({ versions: process.versions, platform: process.platform, arch: process.arch })')"
readonly SOURCE_INPUTS_HASH="$(python3 "${SCRIPT_DIR}/runtime_host_archive.py" fingerprint --source-root "${HOST_SOURCE}" --node-fingerprint "${NODE_FINGERPRINT}")"
if python3 "${SCRIPT_DIR}/runtime_host_archive.py" reuse "${OUTPUT_ROOT}" --source-root "${HOST_SOURCE}" --node-fingerprint "${NODE_FINGERPRINT}"; then
  echo "Reusing verified current RuntimeHostResources.zip and its completed Host/JITless checks."
  exit 0
fi

rm -rf "${WORK_ROOT}" "${OUTPUT_ROOT}"
mkdir -p "${WORK_ROOT}" "${OUTPUT_ROOT}"
cp \
  "${HOST_SOURCE}"/*.mjs \
  "${HOST_SOURCE}/package.json" \
  "${HOST_SOURCE}/package-lock.json" \
  "${HOST_SOURCE}/runtime-dependency-overrides.json" \
  "${WORK_ROOT}/"
cp -R "${HOST_SOURCE}/Tests" "${WORK_ROOT}/Tests"

(
  cd "${WORK_ROOT}"
  npm ci --omit=dev --ignore-scripts --workspaces=false --no-audit --no-fund
  npm test
  rm -rf Tests
  find . -type f -print | LC_ALL=C sort | zip -X -q "${OUTPUT_ROOT}/RuntimeHostResources.zip" -@
)

# Validate the actual packed payload, not just the unarchived npm work tree.
python3 "${SCRIPT_DIR}/runtime_host_archive.py" validate "${OUTPUT_ROOT}/RuntimeHostResources.zip" --source-root "${HOST_SOURCE}"
readonly VERIFY_ROOT="$(mktemp -d)"
cleanup_verify() { rm -rf "${VERIFY_ROOT}"; }
trap cleanup_verify EXIT
python3 -m zipfile -e "${OUTPUT_ROOT}/RuntimeHostResources.zip" "${VERIFY_ROOT}"
mkdir -p "${VERIFY_ROOT}/Tests/Fixtures"
cp "${HOST_SOURCE}/Tests/Fixtures/fetch-compatibility-probe.mjs" "${VERIFY_ROOT}/Tests/Fixtures/"
node --jitless "${VERIFY_ROOT}/Tests/Fixtures/fetch-compatibility-probe.mjs"

host_sha256="$(shasum -a 256 "${OUTPUT_ROOT}/RuntimeHostResources.zip" | awk '{print $1}')"
printf '%s  %s\n' "${host_sha256}" "RuntimeHostResources.zip" > "${OUTPUT_ROOT}/runtime-host.sha256"
node -e '
  const fs = require("node:fs");
  const [file, hash, nodeVersion, sourceInputsHash] = process.argv.slice(1);
  fs.writeFileSync(file, `${JSON.stringify({
    nodeVersion, archiveSha256: hash, sourceInputsHash, jitlessArchiveSmoke: "passed", npmInstall: "npm ci --omit=dev --ignore-scripts --workspaces=false --no-audit --no-fund",
    tests: "passed",
  }, null, 2)}\n`);
' "${OUTPUT_ROOT}/host-metadata.json" "${host_sha256}" "$(node --version)" "${SOURCE_INPUTS_HASH}"

rm -rf "${WORK_ROOT}"
echo "Prepared RuntimeHostResources.zip (${host_sha256})."
