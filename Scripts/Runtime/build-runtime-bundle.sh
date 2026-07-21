#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly LOCK_FILE="${REPOSITORY_ROOT}/RuntimeDependencies.lock.json"
readonly BUILD_ROOT="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/hanlin-runtime-build"
readonly OUTPUT_ROOT="${REPOSITORY_ROOT}/build/runtime-bundle"

node "${SCRIPT_DIR}/validate-runtime-lock.mjs" "${LOCK_FILE}" --allow-pending-build

read_lock() {
  node -e "const value=require(process.argv[1]); console.log($1)" "${LOCK_FILE}"
}

readonly NODE_URL="$(read_lock 'value.node.sourceArchive.url')"
readonly NODE_SOURCE_SHA="$(read_lock 'value.node.sourceArchive.sha256')"
readonly NODE_COMMIT="$(read_lock 'value.node.commit')"
readonly NODE_VERSION="$(read_lock 'value.node.version')"
readonly PYTHON_URL="$(read_lock 'value.python.archive.url')"
readonly PYTHON_SHA="$(read_lock 'value.python.archive.sha256')"
readonly PYTHON_VERSION="$(read_lock 'value.python.version')"

rm -rf "${BUILD_ROOT}" "${OUTPUT_ROOT}"
mkdir -p "${BUILD_ROOT}" "${OUTPUT_ROOT}"

download_verified() {
  local url="$1"
  local expected="$2"
  local destination="$3"
  curl --fail --location --retry 3 --output "${destination}" "${url}"
  local actual
  actual="$(shasum -a 256 "${destination}" | awk '{print $1}')"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "Checksum mismatch for ${url}: expected ${expected}, received ${actual}" >&2
    exit 1
  fi
}

node_archive="${BUILD_ROOT}/node-source.tar.gz"
download_verified "${NODE_URL}" "${NODE_SOURCE_SHA}" "${node_archive}"
mkdir -p "${BUILD_ROOT}/node-source"
tar -xzf "${node_archive}" -C "${BUILD_ROOT}/node-source" --strip-components=1
node_source="${BUILD_ROOT}/node-source"

grep -Eq '#define NODE_MAJOR_VERSION[[:space:]]+24' "${node_source}/src/node_version.h"
actual_node_version="$(awk '
  /#define NODE_MAJOR_VERSION/ { major=$3 }
  /#define NODE_MINOR_VERSION/ { minor=$3 }
  /#define NODE_PATCH_VERSION/ { patch=$3 }
  END { print major "." minor "." patch }
' "${node_source}/src/node_version.h")"
test "${actual_node_version}" = "${NODE_VERSION}"

pushd "${node_source}" >/dev/null
./tools/ios_framework_prepare.sh arm64
./tools/ios_framework_prepare.sh arm64-simulator
./tools/ios_framework_prepare.sh combine_frameworks
popd >/dev/null

node_xcframework="${node_source}/out_ios/NodeMobile.xcframework"
test -d "${node_xcframework}/ios-arm64/NodeMobile.framework"
test -d "${node_xcframework}/ios-arm64_x86_64-simulator/NodeMobile.framework" \
  || test -d "${node_xcframework}/ios-arm64-simulator/NodeMobile.framework"

host_source="${REPOSITORY_ROOT}/AI_HLY/Downstream/MCP/Runtime/Host"
smoke_host="${node_source}/test/fixtures/hanlin-runtime-host"
rm -rf "${smoke_host}"
mkdir -p "${smoke_host}"
cp "${host_source}"/*.mjs "${host_source}/package.json" "${host_source}/package-lock.json" "${smoke_host}/"
cp "${SCRIPT_DIR}/Tests/node-mobile-smoke.mjs" "${smoke_host}/smoke.mjs"
cp -R "${host_source}/Tests" "${smoke_host}/Tests"
(
  cd "${smoke_host}"
  npm ci --omit=dev --ignore-scripts --ignore-workspaces --no-audit --no-fund
  npm test
)

sample_project="${node_source}/tools/mobile-test/ios/testnode/testnode.xcodeproj"
sample_derived="${BUILD_ROOT}/sample-derived"
xcodebuild \
  -project "${sample_project}" \
  -target testnode \
  -configuration Release \
  -sdk iphonesimulator \
  -arch arm64 \
  SYMROOT="${sample_derived}/Build/Products" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=NO \
  DEVELOPMENT_TEAM= \
  build

sample_app="$(find "${sample_derived}/Build/Products" -path '*Release-iphonesimulator/testnode.app' -type d -print -quit)"
test -n "${sample_app}"

device_udid="$(xcrun simctl list devices available --json | node -e '
  let input=""; process.stdin.on("data", chunk => input += chunk); process.stdin.on("end", () => {
    const devices = Object.values(JSON.parse(input).devices).flat();
    const device = devices.find(value => value.isAvailable && value.deviceTypeIdentifier.includes("iPhone"));
    if (!device) process.exit(1);
    process.stdout.write(device.udid);
  });
')"
xcrun simctl boot "${device_udid}" 2>/dev/null || true
open -a Simulator --args -CurrentDeviceUDID "${device_udid}" 2>/dev/null || true
xcrun simctl bootstatus "${device_udid}" -b
xcrun simctl install "${device_udid}" "${sample_app}"
xcrun simctl launch "${device_udid}" nodejsmobile.test --copy-path-for-testing
sleep 2
xcrun simctl terminate "${device_udid}" nodejsmobile.test 2>/dev/null || true
xcrun simctl launch "${device_udid}" nodejsmobile.test ./test/fixtures/hanlin-runtime-host/smoke.mjs

data_container="$(xcrun simctl get_app_container "${device_udid}" nodejsmobile.test data)"
smoke_result="${data_container}/Documents/hanlin-node-smoke.json"
for _ in {1..180}; do
  [[ -f "${smoke_result}" ]] && break
  sleep 1
done
test -f "${smoke_result}"
cat "${smoke_result}"
node -e '
  const result = require(process.argv[1]);
  if (!result.ok || result.nodeVersion !== `24.5.0` || !result.workerThreads || !result.hostStartup) process.exit(1);
' "${smoke_result}"
xcrun simctl terminate "${device_udid}" nodejsmobile.test || true

python_archive="${BUILD_ROOT}/python-support.tar.gz"
download_verified "${PYTHON_URL}" "${PYTHON_SHA}" "${python_archive}"
mkdir -p "${BUILD_ROOT}/python-support"
tar -xzf "${python_archive}" -C "${BUILD_ROOT}/python-support"
python_xcframework="${BUILD_ROOT}/python-support/Python.xcframework"
test -d "${python_xcframework}/ios-arm64/Python.framework"
test -d "${python_xcframework}/ios-arm64_x86_64-simulator/Python.framework"
grep -Fq "Python version: ${PYTHON_VERSION}" "${BUILD_ROOT}/python-support/VERSIONS"
test -f "${python_xcframework}/build/utils.sh"

host_build="${BUILD_ROOT}/runtime-host"
mkdir -p "${host_build}"
cp "${host_source}"/*.mjs "${host_source}/package.json" "${host_source}/package-lock.json" "${host_build}/"
(
  cd "${host_build}"
  npm ci --omit=dev --ignore-scripts --ignore-workspaces --no-audit --no-fund
)
host_archive="${OUTPUT_ROOT}/RuntimeHostResources.zip"
(
  cd "${host_build}"
  find . -type f -print | LC_ALL=C sort | zip -X -q "${host_archive}" -@
)

cp -R "${node_xcframework}" "${OUTPUT_ROOT}/NodeMobile.xcframework"
cp -R "${python_xcframework}" "${OUTPUT_ROOT}/Python.xcframework"
cp "${BUILD_ROOT}/python-support/VERSIONS" "${OUTPUT_ROOT}/Python-VERSIONS"
cp "${smoke_result}" "${OUTPUT_ROOT}/NodeMobile-smoke.json"
node "${SCRIPT_DIR}/generate-runtime-manifest.mjs" "${LOCK_FILE}" "${OUTPUT_ROOT}/RuntimeManifest.json"

node_framework_archive="${BUILD_ROOT}/NodeMobile.xcframework.zip"
ditto -c -k --sequesterRsrc --keepParent "${OUTPUT_ROOT}/NodeMobile.xcframework" "${node_framework_archive}"
node_framework_sha="$(shasum -a 256 "${node_framework_archive}" | awk '{print $1}')"

node -e '
  const fs = require("node:fs");
  const file = process.argv[1];
  const sha = process.argv[2];
  const manifest = JSON.parse(fs.readFileSync(file, "utf8"));
  const node = manifest.runtimes.find(runtime => runtime.id === "node");
  node.bundleHash = sha;
  node.verificationStatus = "embedded-smoke-verified";
  fs.writeFileSync(file, `${JSON.stringify(manifest, null, 2)}\n`);
' "${OUTPUT_ROOT}/RuntimeManifest.json" "${node_framework_sha}"

dependency_hash="$(node -e '
  const crypto = require("node:crypto");
  const lock = require(process.argv[1]);
  delete lock.runtimeBundle.sha256;
  delete lock.runtimeBundle.verificationStatus;
  delete lock.node.xcframeworkSha256;
  delete lock.node.verificationStatus;
  process.stdout.write(crypto.createHash("sha256").update(JSON.stringify(lock)).digest("hex"));
' "${LOCK_FILE}")"

cat > "${OUTPUT_ROOT}/RuntimeProvenance.json" <<JSON
{
  "dependencyHash": "${dependency_hash}",
  "nodeCommit": "${NODE_COMMIT}",
  "nodeVersion": "${NODE_VERSION}",
  "nodeSourceSha256": "${NODE_SOURCE_SHA}",
  "nodeXCFrameworkSha256": "${node_framework_sha}",
  "pythonVersion": "${PYTHON_VERSION}",
  "pythonArchiveSha256": "${PYTHON_SHA}"
}
JSON

bundle_name="hanlin-runtime-${dependency_hash}.zip"
bundle_path="${REPOSITORY_ROOT}/build/${bundle_name}"
ditto -c -k --sequesterRsrc "${OUTPUT_ROOT}" "${bundle_path}"
bundle_sha="$(shasum -a 256 "${bundle_path}" | awk '{print $1}')"

printf '%s\n' "${dependency_hash}" > "${REPOSITORY_ROOT}/build/runtime-dependency-hash.txt"
printf '%s\n' "${node_framework_sha}" > "${REPOSITORY_ROOT}/build/node-xcframework.sha256"
printf '%s\n' "${bundle_sha}" > "${REPOSITORY_ROOT}/build/runtime-bundle.sha256"
printf '%s\n' "${bundle_name}" > "${REPOSITORY_ROOT}/build/runtime-bundle-name.txt"

echo "Runtime dependency hash: ${dependency_hash}"
echo "Node XCFramework SHA-256: ${node_framework_sha}"
echo "Runtime bundle: ${bundle_name}"
echo "Runtime bundle SHA-256: ${bundle_sha}"
