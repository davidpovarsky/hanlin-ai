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
readonly EXPORTS_FILE="${SCRIPT_DIR}/NodeMobile.exports"
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

readonly NODE_FRAMEWORK_PROJECT="${NODE_SOURCE_ROOT}/tools/ios-framework/NodeMobile.xcodeproj/project.pbxproj"
readonly NODE_FRAMEWORK_EXPORTS="${NODE_SOURCE_ROOT}/tools/ios-framework/NodeMobile/NodeMobile.exports"
test -f "${NODE_FRAMEWORK_PROJECT}"
test -f "${EXPORTS_FILE}"
mkdir -p "$(dirname "${NODE_FRAMEWORK_EXPORTS}")"
cp "${EXPORTS_FILE}" "${NODE_FRAMEWORK_EXPORTS}"

node - "${LOCK_FILE}" "${EXPORTS_FILE}" "${NODE_FRAMEWORK_PROJECT}" "${NODE_FRAMEWORK_EXPORTS}" <<'NODE'
const fs = require('node:fs');
const [lockPath, exportsPath, projectPath, injectedExportsPath] = process.argv.slice(2);
const lock = JSON.parse(fs.readFileSync(lockPath, 'utf8'));
const expected = lock.node.exportedSymbols.join('\n') + '\n';
const actual = fs.readFileSync(exportsPath, 'utf8');
if (actual !== expected) throw new Error('NodeMobile.exports does not match node.exportedSymbols in the runtime lock');

const marker = '\t\t\t\tDEFINES_MODULE = YES;';
let project = fs.readFileSync(projectPath, 'utf8');
const occurrences = project.split(marker).length - 1;
if (occurrences !== 2) throw new Error(`Expected two NodeMobile build configurations, found ${occurrences}`);
const setting = `${marker}\n\t\t\t\tEXPORTED_SYMBOLS_FILE = ${JSON.stringify(injectedExportsPath)};`;
project = project.split(marker).join(setting);
fs.writeFileSync(projectPath, project);
NODE

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

exported_symbols="$(nm -gjU "${SOURCE_FRAMEWORK}/NodeMobile" | sort -u)"
expected_symbols="$(sed '/^[[:space:]]*$/d' "${EXPORTS_FILE}" | sort -u)"
if [[ "${exported_symbols}" != "${expected_symbols}" ]]; then
  printf 'Unexpected NodeMobile exported symbols. Expected:\n%s\nActual:\n%s\n' \
    "${expected_symbols}" "${exported_symbols}" >&2
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
