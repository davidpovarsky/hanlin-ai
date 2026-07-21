#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly LOCK_FILE="${REPOSITORY_ROOT}/RuntimeDependencies.lock.json"
readonly WORK_ROOT="$(mktemp -d)"

cleanup() {
  rm -rf "${WORK_ROOT}"
}
trap cleanup EXIT

read_lock() {
  node -e "const lock=require(process.argv[1]); process.stdout.write(String($1));" "${LOCK_FILE}"
}

node "${SCRIPT_DIR}/validate-runtime-lock.mjs" "${LOCK_FILE}"

readonly DEPENDENCY_HASH="$(node "${SCRIPT_DIR}/compute-runtime-dependency-hash.mjs" "${LOCK_FILE}")"
readonly RELEASE_REPOSITORY="$(read_lock 'lock.runtimeBundle.releaseRepository')"
readonly RELEASE_TAG_PREFIX="$(read_lock 'lock.runtimeBundle.releaseTagPrefix')"
readonly EXPECTED_BUNDLE_SHA256="$(read_lock 'lock.runtimeBundle.sha256')"
readonly EXPECTED_NODE_SHA256="$(read_lock 'lock.node.xcframeworkSha256')"
readonly NODE_VERSION="$(read_lock 'lock.node.version')"
readonly PYTHON_VERSION="$(read_lock 'lock.python.version')"
readonly RELEASE_TAG="${RELEASE_TAG_PREFIX}${DEPENDENCY_HASH}"
readonly BUNDLE_NAME="hanlin-runtime-${DEPENDENCY_HASH}.zip"
readonly BUNDLE_ARCHIVE="${WORK_ROOT}/${BUNDLE_NAME}"
readonly PAYLOAD_ROOT="${WORK_ROOT}/payload"

[[ "${RELEASE_REPOSITORY}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]
command -v gh >/dev/null
gh release download "${RELEASE_TAG}" \
  --repo "${RELEASE_REPOSITORY}" \
  --pattern "${BUNDLE_NAME}" \
  --dir "${WORK_ROOT}"

actual_bundle_sha256="$(shasum -a 256 "${BUNDLE_ARCHIVE}" | awk '{print $1}')"
if [[ "${actual_bundle_sha256}" != "${EXPECTED_BUNDLE_SHA256}" ]]; then
  echo "RuntimeCore bundle checksum mismatch: expected ${EXPECTED_BUNDLE_SHA256}, received ${actual_bundle_sha256}." >&2
  exit 1
fi

mkdir -p "${PAYLOAD_ROOT}"
ditto -x -k "${BUNDLE_ARCHIVE}" "${PAYLOAD_ROOT}"

required_paths=(
  "NodeMobile.xcframework/Info.plist"
  "NodeMobile.xcframework/ios-arm64/NodeMobile.framework/NodeMobile"
  "NodeMobile.xcframework/ios-arm64-simulator/NodeMobile.framework/NodeMobile"
  "Python.xcframework/Info.plist"
  "Python.xcframework/ios-arm64/Python.framework/Python"
  "Python.xcframework/ios-arm64_x86_64-simulator/Python.framework/Python"
  "Python-VERSIONS"
  "RuntimeHostResources.zip"
  "RuntimeManifest.json"
  "RuntimeProvenance.json"
  "NodeMobile-smoke.json"
)
for relative_path in "${required_paths[@]}"; do
  test -e "${PAYLOAD_ROOT}/${relative_path}" || {
    echo "RuntimeCore bundle is missing ${relative_path}." >&2
    exit 1
  }
done

plutil -lint "${PAYLOAD_ROOT}/NodeMobile.xcframework/Info.plist"
plutil -lint "${PAYLOAD_ROOT}/Python.xcframework/Info.plist"
[[ "$(lipo -archs "${PAYLOAD_ROOT}/NodeMobile.xcframework/ios-arm64/NodeMobile.framework/NodeMobile")" == "arm64" ]]
[[ "$(lipo -archs "${PAYLOAD_ROOT}/NodeMobile.xcframework/ios-arm64-simulator/NodeMobile.framework/NodeMobile")" == "arm64" ]]
grep -Fq "Python version: ${PYTHON_VERSION}" "${PAYLOAD_ROOT}/Python-VERSIONS"
unzip -tq "${PAYLOAD_ROOT}/RuntimeHostResources.zip" >/dev/null

node -e '
  const fs = require("node:fs");
  const [root, lockPath, dependencyHash, nodeHash, nodeVersion] = process.argv.slice(1);
  const lock = JSON.parse(fs.readFileSync(lockPath, "utf8"));
  const manifest = JSON.parse(fs.readFileSync(`${root}/RuntimeManifest.json`, "utf8"));
  const provenance = JSON.parse(fs.readFileSync(`${root}/RuntimeProvenance.json`, "utf8"));
  const smoke = JSON.parse(fs.readFileSync(`${root}/NodeMobile-smoke.json`, "utf8"));
  const nodeRuntime = manifest.runtimes.find(runtime => runtime.id === "node");
  if (provenance.dependencyHash !== dependencyHash) throw new Error("Runtime provenance dependency hash mismatch");
  if (provenance.nodeXCFrameworkSha256 !== nodeHash) throw new Error("Runtime provenance Node hash mismatch");
  if (nodeRuntime?.bundleHash !== nodeHash) throw new Error("Runtime manifest Node hash mismatch");
  if (!smoke.ok || smoke.nodeVersion !== nodeVersion || !smoke.workerThreads || !smoke.hostStartup) {
    throw new Error("Embedded Node smoke evidence is incomplete");
  }
  if (lock.runtimeBundle.verificationStatus !== "verified" || lock.node.verificationStatus !== "verified") {
    throw new Error("Runtime lock verification is not finalized");
  }
' "${PAYLOAD_ROOT}" "${LOCK_FILE}" "${DEPENDENCY_HASH}" "${EXPECTED_NODE_SHA256}" "${NODE_VERSION}"

node_vendor="${REPOSITORY_ROOT}/Vendor/NodeMobile"
python_vendor="${REPOSITORY_ROOT}/Vendor/Python"
host_resource="${REPOSITORY_ROOT}/AI_HLY/RuntimeHostResources.zip"
manifest_resource="${REPOSITORY_ROOT}/AI_HLY/Downstream/RuntimeCore/Resources/RuntimeManifest.json"

mkdir -p "${node_vendor}" "${python_vendor}" "$(dirname "${manifest_resource}")"
rm -rf "${node_vendor}/NodeMobile.xcframework" "${python_vendor}/Python.xcframework"
ditto "${PAYLOAD_ROOT}/NodeMobile.xcframework" "${node_vendor}/NodeMobile.xcframework"
ditto "${PAYLOAD_ROOT}/Python.xcframework" "${python_vendor}/Python.xcframework"
cp "${PAYLOAD_ROOT}/Python-VERSIONS" "${python_vendor}/Python-VERSIONS"
cp "${PAYLOAD_ROOT}/RuntimeHostResources.zip" "${host_resource}"
node "${SCRIPT_DIR}/generate-runtime-manifest.mjs" "${LOCK_FILE}" "${manifest_resource}"

test -d "${node_vendor}/NodeMobile.xcframework"
test -d "${python_vendor}/Python.xcframework"
test -f "${host_resource}"
test -f "${manifest_resource}"

echo "Prepared verified RuntimeCore ${DEPENDENCY_HASH}: Node ${NODE_VERSION}, Python ${PYTHON_VERSION}."
