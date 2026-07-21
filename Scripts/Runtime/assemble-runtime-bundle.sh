#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly LOCK_FILE="${REPOSITORY_ROOT}/RuntimeDependencies.lock.json"
readonly INPUT_ROOT="${RUNTIME_INPUT_ROOT:-${REPOSITORY_ROOT}/build/runtime-inputs}"
readonly OUTPUT_ROOT="${REPOSITORY_ROOT}/build/runtime-bundle"
readonly LOG_ROOT="${REPOSITORY_ROOT}/build/runtime-assembly-logs"
readonly WORK_ROOT="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/hanlin-runtime-assembly"

read_lock() {
  node -e "const lock=require(process.argv[1]); process.stdout.write(String($1));" "${LOCK_FILE}"
}

readonly NODE_VERSION="$(read_lock 'lock.node.version')"
readonly NODE_COMMIT="$(read_lock 'lock.node.commit')"
readonly NODE_SOURCE_SHA256="$(read_lock 'lock.node.sourceArchive.sha256')"
readonly PYTHON_VERSION="$(read_lock 'lock.python.version')"
readonly PYTHON_SHA256="$(read_lock 'lock.python.archive.sha256')"
readonly DEPENDENCY_HASH="$(node "${SCRIPT_DIR}/compute-runtime-dependency-hash.mjs" "${LOCK_FILE}")"

rm -rf "${WORK_ROOT}" "${OUTPUT_ROOT}"
mkdir -p "${WORK_ROOT}/device" "${WORK_ROOT}/simulator" "${OUTPUT_ROOT}" "${LOG_ROOT}"

verify_checksum() {
  local checksum_file="$1"
  local payload_directory="$2"
  (cd "${payload_directory}" && shasum -a 256 -c "${checksum_file}")
}

verify_checksum "${INPUT_ROOT}/node-device/framework.sha256" "${INPUT_ROOT}/node-device"
verify_checksum "${INPUT_ROOT}/node-simulator/framework.sha256" "${INPUT_ROOT}/node-simulator"
verify_checksum "${INPUT_ROOT}/python/python-runtime.sha256" "${INPUT_ROOT}/python"
verify_checksum "${INPUT_ROOT}/host/runtime-host.sha256" "${INPUT_ROOT}/host"

ditto -x -k "${INPUT_ROOT}/node-device/NodeMobile.framework.zip" "${WORK_ROOT}/device"
ditto -x -k "${INPUT_ROOT}/node-simulator/NodeMobile.framework.zip" "${WORK_ROOT}/simulator"
device_framework="${WORK_ROOT}/device/NodeMobile.framework"
simulator_framework="${WORK_ROOT}/simulator/NodeMobile.framework"

xcodebuild -create-xcframework \
  -framework "${device_framework}" \
  -framework "${simulator_framework}" \
  -output "${OUTPUT_ROOT}/NodeMobile.xcframework" \
  > "${LOG_ROOT}/create-xcframework.log" 2>&1

node_device="${OUTPUT_ROOT}/NodeMobile.xcframework/ios-arm64/NodeMobile.framework"
node_simulator="${OUTPUT_ROOT}/NodeMobile.xcframework/ios-arm64-simulator/NodeMobile.framework"
test -f "${node_device}/NodeMobile"
test -f "${node_simulator}/NodeMobile"
test -d "${node_device}/Headers"
test -f "${node_device}/Modules/module.modulemap"
test -d "${node_simulator}/Headers"
test -f "${node_simulator}/Modules/module.modulemap"
[[ "$(lipo -archs "${node_device}/NodeMobile")" == "arm64" ]]
[[ "$(lipo -archs "${node_simulator}/NodeMobile")" == "arm64" ]]
plutil -lint "${OUTPUT_ROOT}/NodeMobile.xcframework/Info.plist"
plutil -convert json -o "${WORK_ROOT}/xcframework-info.json" "${OUTPUT_ROOT}/NodeMobile.xcframework/Info.plist"
node -e '
  const info = require(process.argv[1]);
  const identifiers = info.AvailableLibraries.map(value => value.LibraryIdentifier);
  if (new Set(identifiers).size !== identifiers.length) throw new Error("Duplicate XCFramework library identifier");
  for (const expected of ["ios-arm64", "ios-arm64-simulator"]) {
    if (!identifiers.includes(expected)) throw new Error(`Missing XCFramework library identifier ${expected}`);
  }
' "${WORK_ROOT}/xcframework-info.json"

ditto -x -k "${INPUT_ROOT}/python/PythonRuntime.zip" "${OUTPUT_ROOT}"
test -d "${OUTPUT_ROOT}/Python.xcframework"
test -f "${OUTPUT_ROOT}/Python-VERSIONS"
cp "${INPUT_ROOT}/host/RuntimeHostResources.zip" "${OUTPUT_ROOT}/RuntimeHostResources.zip"

node_xcframework_archive="${WORK_ROOT}/NodeMobile.xcframework.zip"
ditto -c -k --sequesterRsrc --keepParent \
  "${OUTPUT_ROOT}/NodeMobile.xcframework" "${node_xcframework_archive}"
node_xcframework_sha256="$(shasum -a 256 "${node_xcframework_archive}" | awk '{print $1}')"

node_source="${WORK_ROOT}/node-source"
bash "${SCRIPT_DIR}/prepare-node-source.sh" "${node_source}" > "${LOG_ROOT}/prepare-smoke-source.log" 2>&1
mkdir -p "${node_source}/out_ios"
ditto "${OUTPUT_ROOT}/NodeMobile.xcframework" "${node_source}/out_ios/NodeMobile.xcframework"

# The sample project embeds its source tree's test folder. Keep only the focused fixture.
rm -rf "${node_source}/test"
smoke_host="${node_source}/test/fixtures/hanlin-runtime-host"
mkdir -p "${smoke_host}"
ditto -x -k "${OUTPUT_ROOT}/RuntimeHostResources.zip" "${smoke_host}"
cp "${SCRIPT_DIR}/Tests/node-mobile-smoke.mjs" "${smoke_host}/smoke.mjs"

sample_project="${node_source}/tools/mobile-test/ios/testnode/testnode.xcodeproj"
sample_derived="${WORK_ROOT}/sample-derived"
python3 "${SCRIPT_DIR}/run-with-heartbeat.py" \
  --log "${LOG_ROOT}/sample-xcodebuild.log" \
  --summary "${LOG_ROOT}/sample-xcodebuild-heartbeat.log" \
  --object-root "${sample_derived}" \
  --timeout 3600 \
  -- xcodebuild \
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
  let input="";
  process.stdin.on("data", chunk => input += chunk);
  process.stdin.on("end", () => {
    const devices = Object.values(JSON.parse(input).devices).flat();
    const device = devices.find(value => value.isAvailable && value.deviceTypeIdentifier.includes("iPhone"));
    if (!device) process.exit(1);
    process.stdout.write(device.udid);
  });
')"
xcrun simctl boot "${device_udid}" 2>/dev/null || true
python3 "${SCRIPT_DIR}/run-with-heartbeat.py" \
  --log "${LOG_ROOT}/simulator-boot.log" \
  --summary "${LOG_ROOT}/simulator-boot-heartbeat.log" \
  --timeout 900 \
  -- xcrun simctl bootstatus "${device_udid}" -b
xcrun simctl install "${device_udid}" "${sample_app}"
xcrun simctl launch "${device_udid}" nodejsmobile.test --copy-path-for-testing
sleep 2
xcrun simctl terminate "${device_udid}" nodejsmobile.test 2>/dev/null || true
xcrun simctl launch "${device_udid}" nodejsmobile.test ./test/fixtures/hanlin-runtime-host/smoke.mjs

data_container="$(xcrun simctl get_app_container "${device_udid}" nodejsmobile.test data)"
smoke_result="${data_container}/Documents/hanlin-node-smoke.json"
for attempt in {1..180}; do
  [[ -f "${smoke_result}" ]] && break
  if (( attempt % 30 == 0 )); then echo "Waiting for embedded smoke result (${attempt}s)."; fi
  sleep 1
done
test -f "${smoke_result}"
cp "${smoke_result}" "${OUTPUT_ROOT}/NodeMobile-smoke.json"
node -e '
  const result = require(process.argv[1]);
  if (!result.ok || result.nodeVersion !== "24.5.0" || !result.workerThreads || !result.hostStartup) {
    throw new Error(`Embedded Node smoke failed: ${JSON.stringify(result)}`);
  }
' "${OUTPUT_ROOT}/NodeMobile-smoke.json"
xcrun simctl terminate "${device_udid}" nodejsmobile.test 2>/dev/null || true

node "${SCRIPT_DIR}/generate-runtime-manifest.mjs" "${LOCK_FILE}" "${OUTPUT_ROOT}/RuntimeManifest.json"
node -e '
  const fs = require("node:fs");
  const [file, hash] = process.argv.slice(1);
  const manifest = require(file);
  const nodeRuntime = manifest.runtimes.find(runtime => runtime.id === "node");
  nodeRuntime.bundleHash = hash;
  nodeRuntime.verificationStatus = "embedded-smoke-verified";
  fs.writeFileSync(file, `${JSON.stringify(manifest, null, 2)}\n`);
' "${OUTPUT_ROOT}/RuntimeManifest.json" "${node_xcframework_sha256}"

device_slice_sha256="$(awk '{print $1}' "${INPUT_ROOT}/node-device/framework.sha256")"
simulator_slice_sha256="$(awk '{print $1}' "${INPUT_ROOT}/node-simulator/framework.sha256")"
host_sha256="$(awk '{print $1}' "${INPUT_ROOT}/host/runtime-host.sha256")"
python_runtime_sha256="$(awk '{print $1}' "${INPUT_ROOT}/python/python-runtime.sha256")"
node -e '
  const fs = require("node:fs");
  const [file, dependencyHash, nodeCommit, nodeVersion, nodeSourceHash, nodeHash, deviceHash,
    simulatorHash, pythonVersion, pythonSourceHash, pythonRuntimeHash, hostHash, runID, runAttempt] = process.argv.slice(1);
  fs.writeFileSync(file, `${JSON.stringify({
    dependencyHash, nodeCommit, nodeVersion, nodeSourceSha256: nodeSourceHash,
    nodeXCFrameworkSha256: nodeHash, nodeDeviceSliceSha256: deviceHash,
    nodeSimulatorSliceSha256: simulatorHash, pythonVersion,
    pythonArchiveSha256: pythonSourceHash, pythonRuntimeSha256: pythonRuntimeHash,
    runtimeHostSha256: hostHash, workflowRunID: runID || null,
    workflowRunAttempt: runAttempt ? Number(runAttempt) : null,
  }, null, 2)}\n`);
' "${OUTPUT_ROOT}/RuntimeProvenance.json" "${DEPENDENCY_HASH}" "${NODE_COMMIT}" "${NODE_VERSION}" \
  "${NODE_SOURCE_SHA256}" "${node_xcframework_sha256}" "${device_slice_sha256}" \
  "${simulator_slice_sha256}" "${PYTHON_VERSION}" "${PYTHON_SHA256}" \
  "${python_runtime_sha256}" "${host_sha256}" "${GITHUB_RUN_ID:-}" "${GITHUB_RUN_ATTEMPT:-}"

bundle_name="hanlin-runtime-${DEPENDENCY_HASH}.zip"
bundle_path="${REPOSITORY_ROOT}/build/${bundle_name}"
ditto -c -k --sequesterRsrc "${OUTPUT_ROOT}" "${bundle_path}"
bundle_sha256="$(shasum -a 256 "${bundle_path}" | awk '{print $1}')"

printf '%s\n' "${DEPENDENCY_HASH}" > "${REPOSITORY_ROOT}/build/runtime-dependency-hash.txt"
printf '%s  %s\n' "${node_xcframework_sha256}" "NodeMobile.xcframework.zip" > "${REPOSITORY_ROOT}/build/node-xcframework.sha256"
printf '%s  %s\n' "${bundle_sha256}" "${bundle_name}" > "${REPOSITORY_ROOT}/build/runtime-bundle.sha256"
printf '%s\n' "${bundle_name}" > "${REPOSITORY_ROOT}/build/runtime-bundle-name.txt"

rm -rf "${sample_derived}" "${node_source}"
echo "Assembled ${bundle_name} (${bundle_sha256}); Node XCFramework ${node_xcframework_sha256}."
