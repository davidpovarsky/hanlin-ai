#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ( "$1" != "arm64" && "$1" != "arm64-simulator" ) ]]; then
  echo "Usage: build-node-slice.sh arm64|arm64-simulator" >&2
  exit 64
fi

readonly TARGET="$1"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly LOCK_FILE="${REPOSITORY_ROOT}/RuntimeDependencies.lock.json"
readonly NODE_SOURCE_ROOT="${NODE_SOURCE_ROOT:?NODE_SOURCE_ROOT must identify the prepared pinned source}"
readonly OUTPUT_ROOT="${REPOSITORY_ROOT}/build/node-slices/${TARGET}"
readonly CCACHE_STATS_FILE="${CCACHE_STATS_FILE:-${OUTPUT_ROOT}/ccache-stats.txt}"

case "${TARGET}" in
  arm64)
    readonly SOURCE_FRAMEWORK="${NODE_SOURCE_ROOT}/out_ios_arm64/iphoneos-arm64/Release-iphoneos/NodeMobile.framework"
    readonly EXPECTED_PLATFORM="iPhoneOS"
    ;;
  arm64-simulator)
    readonly SOURCE_FRAMEWORK="${NODE_SOURCE_ROOT}/out_ios_arm64-simulator/iphonesimulator-arm64/Release-iphonesimulator/NodeMobile.framework"
    readonly EXPECTED_PLATFORM="iPhoneSimulator"
    ;;
esac

started_at="$(date +%s)"
rm -rf "${OUTPUT_ROOT}"
mkdir -p "${OUTPUT_ROOT}"

cd "${NODE_SOURCE_ROOT}"
./tools/ios_framework_prepare.sh "${TARGET}"

test -d "${SOURCE_FRAMEWORK}"
test -f "${SOURCE_FRAMEWORK}/NodeMobile"
architectures="$(lipo -archs "${SOURCE_FRAMEWORK}/NodeMobile")"
if [[ " ${architectures} " != *" arm64 "* || " ${architectures} " == *" x86_64 "* ]]; then
  echo "Unexpected ${TARGET} framework architectures: ${architectures}" >&2
  exit 1
fi

platform="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "${SOURCE_FRAMEWORK}/Info.plist")"
if [[ "${platform}" != "${EXPECTED_PLATFORM}" ]]; then
  echo "Unexpected ${TARGET} framework platform: ${platform}" >&2
  exit 1
fi

ditto "${SOURCE_FRAMEWORK}" "${OUTPUT_ROOT}/NodeMobile.framework"
ditto -c -k --sequesterRsrc --keepParent \
  "${OUTPUT_ROOT}/NodeMobile.framework" "${OUTPUT_ROOT}/NodeMobile.framework.zip"
framework_sha256="$(shasum -a 256 "${OUTPUT_ROOT}/NodeMobile.framework.zip" | awk '{print $1}')"
printf '%s  %s\n' "${framework_sha256}" "NodeMobile.framework.zip" > "${OUTPUT_ROOT}/framework.sha256"
rm -rf "${OUTPUT_ROOT}/NodeMobile.framework"
ccache --show-stats > "${CCACHE_STATS_FILE}"

node_version="$(node -e 'process.stdout.write(require(process.argv[1]).node.version)' "${LOCK_FILE}")"
node_commit="$(node -e 'process.stdout.write(require(process.argv[1]).node.commit)' "${LOCK_FILE}")"
xcode_version="$(xcodebuild -version | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
duration="$(( $(date +%s) - started_at ))"

node -e '
  const fs = require("node:fs");
  const [file, nodeVersion, nodeCommit, target, xcodeVersion, hash, duration, architectures, platform] = process.argv.slice(1);
  fs.writeFileSync(file, `${JSON.stringify({
    nodeVersion, nodeCommit, target, xcodeVersion, frameworkSha256: hash,
    buildDurationSeconds: Number(duration), architectures: architectures.split(/\\s+/), platform,
  }, null, 2)}\n`);
' "${OUTPUT_ROOT}/slice-metadata.json" "${node_version}" "${node_commit}" "${TARGET}" \
  "${xcode_version}" "${framework_sha256}" "${duration}" "${architectures}" "${platform}"

echo "Built ${TARGET} NodeMobile.framework (${framework_sha256}) in ${duration}s."
