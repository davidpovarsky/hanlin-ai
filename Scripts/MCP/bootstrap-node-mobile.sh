#!/usr/bin/env bash
set -euo pipefail

readonly NODE_MOBILE_VERSION="18.20.4"
readonly NODE_MOBILE_ARCHIVE="nodejs-mobile-v${NODE_MOBILE_VERSION}-ios.zip"
readonly NODE_MOBILE_URL="https://github.com/nodejs-mobile/nodejs-mobile/releases/download/v${NODE_MOBILE_VERSION}/${NODE_MOBILE_ARCHIVE}"
readonly NODE_MOBILE_SHA256="8c5ca3a0d1e38de7f182a5642593e82593b820efd375a14b3ecafc4bcfee620e"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly VENDOR_DIR="${REPOSITORY_ROOT}/Vendor/NodeMobile"
readonly HOST_DIR="${REPOSITORY_ROOT}/AI_HLY/Downstream/MCP/Runtime/Host"
readonly HOST_ARCHIVE="${REPOSITORY_ROOT}/AI_HLY/MCPHostResources.zip"

temporary_directory="$(mktemp -d)"
trap 'rm -rf "${temporary_directory}"' EXIT

archive_path="${temporary_directory}/${NODE_MOBILE_ARCHIVE}"
curl --fail --location --retry 3 --output "${archive_path}" "${NODE_MOBILE_URL}"
actual_sha256="$(shasum -a 256 "${archive_path}" | awk '{print $1}')"
if [[ "${actual_sha256}" != "${NODE_MOBILE_SHA256}" ]]; then
  echo "Node.js Mobile checksum mismatch: ${actual_sha256}" >&2
  exit 1
fi

unzip -q "${archive_path}" -d "${temporary_directory}/node-mobile"
test -d "${temporary_directory}/node-mobile/NodeMobile.xcframework"
mkdir -p "${VENDOR_DIR}"
rm -rf "${VENDOR_DIR}/NodeMobile.xcframework"
ditto "${temporary_directory}/node-mobile/NodeMobile.xcframework" "${VENDOR_DIR}/NodeMobile.xcframework"
curl --fail --location --retry 3 \
  --output "${VENDOR_DIR}/NODE_LICENSE.generated.txt" \
  "https://raw.githubusercontent.com/nodejs-mobile/nodejs-mobile/v${NODE_MOBILE_VERSION}/LICENSE"

host_build_directory="${temporary_directory}/host"
mkdir -p "${host_build_directory}"
cp \
  "${HOST_DIR}/host.mjs" \
  "${HOST_DIR}/server-worker.mjs" \
  "${HOST_DIR}/package-installer.mjs" \
  "${HOST_DIR}/package-compatibility.mjs" \
  "${HOST_DIR}/package.json" \
  "${HOST_DIR}/package-lock.json" \
  "${host_build_directory}/"
npm ci --omit=dev --ignore-scripts --no-audit --no-fund --prefix "${host_build_directory}"
rm -f "${HOST_ARCHIVE}"
host_archive_temporary="${temporary_directory}/MCPHostResources.zip"
(
  cd "${host_build_directory}"
  find host.mjs server-worker.mjs package-installer.mjs package-compatibility.mjs package.json package-lock.json node_modules \
    -type f -print | LC_ALL=C sort | zip -X -q "${host_archive_temporary}" -@
)
mv "${host_archive_temporary}" "${HOST_ARCHIVE}"

echo "Prepared Node.js Mobile ${NODE_MOBILE_VERSION} and MCPHostResources.zip."
