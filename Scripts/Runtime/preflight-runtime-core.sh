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
  "${REPOSITORY_ROOT}/Packages/IOSSystemLite/Package.swift"
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

node - "${LOCK_FILE}" "${HOST_ROOT}/package.json" "${HOST_ROOT}/package-lock.json" "${REPOSITORY_ROOT}/Packages/IOSSystemLite/Package.swift" <<'NODE'
const fs = require('node:fs');
const [lockPath, packagePath, packageLockPath, swiftPackagePath] = process.argv.slice(2);
const lock = JSON.parse(fs.readFileSync(lockPath, 'utf8'));
const manifest = JSON.parse(fs.readFileSync(packagePath, 'utf8'));
const packageLock = JSON.parse(fs.readFileSync(packageLockPath, 'utf8'));
const swiftPackage = fs.readFileSync(swiftPackagePath, 'utf8');
if (manifest.engines?.node !== lock.node.version) throw new Error('Host Node engine does not match RuntimeDependencies.lock.json');
if (manifest.dependencies?.typescript !== lock.typescript.version) throw new Error('TypeScript version does not match the runtime lock');
if (packageLock.packages?.['']?.dependencies?.typescript !== lock.typescript.version) throw new Error('package-lock TypeScript version is inconsistent');
for (const component of lock.iosSystem.components) {
  if (!swiftPackage.includes(`name: "${component.name}"`) || !swiftPackage.includes(`checksum: "${component.sha256}"`)) {
    throw new Error(`IOSSystemLite is inconsistent for ${component.name}`);
  }
}
NODE

test "$(unzip -Z1 "${HOST_ARCHIVE}" | grep -c '^node_modules/typescript/package.json$')" -eq 1
test "$(unzip -Z1 "${HOST_ARCHIVE}" | grep -c '^host.mjs$')" -eq 1
test "$(unzip -Z1 "${HOST_ARCHIVE}" | grep -c '^execution-worker.mjs$')" -eq 1

echo "RuntimeCore preflight passed: verified Node 24.5.0, Python 3.14.6, TypeScript 6.0.3, host resources and ios_system 3.0.5 pins."
