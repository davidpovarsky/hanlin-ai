#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly LOCK_FILE="${REPOSITORY_ROOT}/RuntimeDependencies.lock.json"
readonly WORK_ROOT="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/hanlin-python-runtime"
readonly OUTPUT_ROOT="${REPOSITORY_ROOT}/build/python-runtime"

read_lock() {
  node -e "const lock=require(process.argv[1]); process.stdout.write(String($1));" "${LOCK_FILE}"
}

readonly PYTHON_URL="$(read_lock 'lock.python.archive.url')"
readonly PYTHON_SHA256="$(read_lock 'lock.python.archive.sha256')"
readonly PYTHON_VERSION="$(read_lock 'lock.python.version')"
readonly PYTHON_COMMIT="$(read_lock 'lock.python.commit')"

rm -rf "${WORK_ROOT}" "${OUTPUT_ROOT}"
mkdir -p "${WORK_ROOT}/source" "${OUTPUT_ROOT}/payload"
archive="${WORK_ROOT}/python-support.tar.gz"

curl --fail --location --retry 3 --retry-all-errors --silent --show-error \
  --output "${archive}" "${PYTHON_URL}"
actual_sha256="$(shasum -a 256 "${archive}" | awk '{print $1}')"
if [[ "${actual_sha256}" != "${PYTHON_SHA256}" ]]; then
  echo "Python archive checksum mismatch: expected ${PYTHON_SHA256}, received ${actual_sha256}." >&2
  exit 1
fi

tar -xzf "${archive}" -C "${WORK_ROOT}/source"
python_xcframework="${WORK_ROOT}/source/Python.xcframework"
versions_file="${WORK_ROOT}/source/VERSIONS"
test -d "${python_xcframework}/ios-arm64/Python.framework"
test -f "${python_xcframework}/ios-arm64/Python.framework/Python"
test -d "${python_xcframework}/ios-arm64_x86_64-simulator/Python.framework"
test -f "${python_xcframework}/ios-arm64_x86_64-simulator/Python.framework/Python"
test -f "${python_xcframework}/build/utils.sh"
grep -Fq "Python version: ${PYTHON_VERSION}" "${versions_file}"

ditto "${python_xcframework}" "${OUTPUT_ROOT}/payload/Python.xcframework"
cp "${versions_file}" "${OUTPUT_ROOT}/payload/Python-VERSIONS"
ditto -c -k --sequesterRsrc "${OUTPUT_ROOT}/payload" "${OUTPUT_ROOT}/PythonRuntime.zip"
runtime_sha256="$(shasum -a 256 "${OUTPUT_ROOT}/PythonRuntime.zip" | awk '{print $1}')"
printf '%s  %s\n' "${runtime_sha256}" "PythonRuntime.zip" > "${OUTPUT_ROOT}/python-runtime.sha256"
rm -rf "${OUTPUT_ROOT}/payload"

node -e '
  const fs = require("node:fs");
  const [file, version, commit, sourceHash, archiveHash] = process.argv.slice(1);
  fs.writeFileSync(file, `${JSON.stringify({
    pythonVersion: version, pythonCommit: commit, sourceArchiveSha256: sourceHash,
    packagedRuntimeSha256: archiveHash, deviceSlice: "ios-arm64",
    simulatorSlice: "ios-arm64_x86_64-simulator",
  }, null, 2)}\n`);
' "${OUTPUT_ROOT}/python-metadata.json" "${PYTHON_VERSION}" "${PYTHON_COMMIT}" \
  "${PYTHON_SHA256}" "${runtime_sha256}"

rm -rf "${WORK_ROOT}"
echo "Prepared Python ${PYTHON_VERSION} runtime (${runtime_sha256})."
