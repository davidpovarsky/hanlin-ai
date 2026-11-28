set -euo pipefail
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

rm -rf "${WORK_ROOT}" "${GRAMMAR_TOOL_ROOT}"
echo "Prepared RuntimeHostResources.zip (${host_sha256})."
