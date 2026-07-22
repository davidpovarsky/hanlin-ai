#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly LOCK_FILE="${REPOSITORY_ROOT}/RuntimeDependencies.lock.json"
readonly NODE_FRAMEWORK="${REPOSITORY_ROOT}/Vendor/NodeMobile/NodeMobile.xcframework"
readonly PYTHON_FRAMEWORK="${REPOSITORY_ROOT}/Vendor/Python/Python.xcframework"
readonly HOST_ARCHIVE="${REPOSITORY_ROOT}/AI_HLY/RuntimeHostResources.zip"
readonly HOST_ROOT="${REPOSITORY_ROOT}/AI_HLY/Downstream/RuntimeCore/Node/Host"

node "${SCRIPT_DIR}/validate-runtime-lock.mjs" "${LOCK_FILE}"
node "${SCRIPT_DIR}/validate-ios-system-package.mjs" \
  "${LOCK_FILE}" \
  "${REPOSITORY_ROOT}/Packages/IOSSystemLite/Package.swift"
python3 "${SCRIPT_DIR}/validate_ios_system_resources.py" \
  --repository-root "${REPOSITORY_ROOT}"
node "${SCRIPT_DIR}/validate-runtime-localization.mjs" \
  "${REPOSITORY_ROOT}/AI_HLY/Downstream/RuntimeCore" \
  "${REPOSITORY_ROOT}/AI_HLY/Downstream/RuntimeCore/Resources/RuntimeLocalizable.xcstrings"
node "${SCRIPT_DIR}/validate-runtime-localization.mjs" \
  "${REPOSITORY_ROOT}/AI_HLY/Downstream/MCP" \
  "${REPOSITORY_ROOT}/AI_HLY/Downstream/MCP/Resources/MCPLocalizable.xcstrings" \
  "MCPL10n"
generated_manifest="$(mktemp)"
trap 'rm -f "${generated_manifest}"' EXIT
node "${SCRIPT_DIR}/generate-runtime-manifest.mjs" "${LOCK_FILE}" "${generated_manifest}" >/dev/null
cmp -s \
  "${generated_manifest}" \
  "${REPOSITORY_ROOT}/AI_HLY/Downstream/RuntimeCore/Resources/RuntimeManifest.json" || {
    echo "RuntimeManifest.json is stale relative to RuntimeDependencies.lock.json." >&2
    diff -u \
      "${REPOSITORY_ROOT}/AI_HLY/Downstream/RuntimeCore/Resources/RuntimeManifest.json" \
      "${generated_manifest}" >&2 || true
    exit 1
  }

required_paths=(
  "${REPOSITORY_ROOT}/AI_HLY.xcodeproj/project.pbxproj"
  "${REPOSITORY_ROOT}/AI_HLY.xcodeproj/xcshareddata/xcschemes/AI_HLY.xcscheme"
  "${NODE_FRAMEWORK}/Info.plist"
  "${NODE_FRAMEWORK}/ios-arm64/NodeMobile.framework/NodeMobile"
  "${NODE_FRAMEWORK}/ios-arm64-simulator/NodeMobile.framework/NodeMobile"
  "${PYTHON_FRAMEWORK}/Info.plist"
  "${PYTHON_FRAMEWORK}/ios-arm64/Python.framework/Python"
  "${PYTHON_FRAMEWORK}/build/utils.sh"
  "${REPOSITORY_ROOT}/Vendor/Python/Python-VERSIONS"
  "${HOST_ARCHIVE}"
  "${REPOSITORY_ROOT}/AI_HLY/Downstream/RuntimeCore/Resources/RuntimeManifest.json"
  "${REPOSITORY_ROOT}/AI_HLY/Downstream/RuntimeCore/Resources/RuntimeLinkDependencyNotices.txt"
  "${REPOSITORY_ROOT}/Packages/IOSSystemLite/Package.swift"
  "${REPOSITORY_ROOT}/Packages/IOSSystemLite/Sources/IOSSystemLite/Resources/commandDictionary.plist"
  "${REPOSITORY_ROOT}/Packages/IOSSystemLite/Sources/IOSSystemLite/Resources/extraCommandsDictionary.plist"
)
for required_path in "${required_paths[@]}"; do
  test -e "${required_path}" || { echo "RuntimeCore preflight is missing ${required_path}." >&2; exit 1; }
done

plutil -lint "${NODE_FRAMEWORK}/Info.plist"
plutil -lint "${PYTHON_FRAMEWORK}/Info.plist"
[[ "$(lipo -archs "${NODE_FRAMEWORK}/ios-arm64/NodeMobile.framework/NodeMobile")" == "arm64" ]]
[[ "$(lipo -archs "${NODE_FRAMEWORK}/ios-arm64-simulator/NodeMobile.framework/NodeMobile")" == "arm64" ]]
[[ "$(lipo -archs "${PYTHON_FRAMEWORK}/ios-arm64/Python.framework/Python")" == "arm64" ]]
test -d "${PYTHON_FRAMEWORK}/ios-arm64_x86_64-simulator" || test -d "${PYTHON_FRAMEWORK}/ios-arm64-simulator"
grep -Fq "Python version: 3.14.6" "${REPOSITORY_ROOT}/Vendor/Python/Python-VERSIONS"
unzip -tq "${HOST_ARCHIVE}" >/dev/null

node - "${LOCK_FILE}" "${HOST_ROOT}/package.json" "${HOST_ROOT}/package-lock.json" <<'NODE'
const fs = require('node:fs');
const [lockPath, packagePath, packageLockPath] = process.argv.slice(2);
const lock = JSON.parse(fs.readFileSync(lockPath, 'utf8'));
const manifest = JSON.parse(fs.readFileSync(packagePath, 'utf8'));
const packageLock = JSON.parse(fs.readFileSync(packageLockPath, 'utf8'));
if (manifest.engines?.node !== lock.node.version) throw new Error('Host Node engine does not match RuntimeDependencies.lock.json');
if (manifest.dependencies?.typescript !== lock.typescript.version) throw new Error('TypeScript version does not match the runtime lock');
if (packageLock.packages?.['']?.dependencies?.typescript !== lock.typescript.version) throw new Error('package-lock TypeScript version is inconsistent');
NODE

readonly EXPECTED_RUNTIME_DEPENDENCY_HASH="7d967563db0809a4efa0f07b75d6b5928379a3b6f3aafb886899a79f59512a93"
runtime_dependency_hash="$(node "${SCRIPT_DIR}/compute-runtime-dependency-hash.mjs" "${LOCK_FILE}")"
[[ "${runtime_dependency_hash}" == "${EXPECTED_RUNTIME_DEPENDENCY_HASH}" ]] || {
  echo "Runtime dependency hash changed unexpectedly: ${runtime_dependency_hash}" >&2
  exit 1
}

test "$(unzip -Z1 "${HOST_ARCHIVE}" | grep -c '^node_modules/typescript/package.json$')" -eq 1
test "$(unzip -Z1 "${HOST_ARCHIVE}" | grep -c '^host.mjs$')" -eq 1
test "$(unzip -Z1 "${HOST_ARCHIVE}" | grep -c '^execution-worker.mjs$')" -eq 1
test "$(unzip -Z1 "${HOST_ARCHIVE}" | grep -c '^server-worker.mjs$')" -eq 1
test "$(unzip -Z1 "${HOST_ARCHIVE}" | grep -c '^runtime-probe.mjs$')" -eq 1
unzip -p "${HOST_ARCHIVE}" server-worker.mjs | grep -Fq 'registerHooks'
unzip -p "${HOST_ARCHIVE}" package-compatibility.mjs | grep -Fq 'inspectArchiveSafety'

echo "RuntimeCore preflight passed: verified Node 24.5.0, Python 3.14.6, TypeScript 6.0.3, host resources, ios_system 3.0.5 pins, and the complete pinned curl_ios link closure."
