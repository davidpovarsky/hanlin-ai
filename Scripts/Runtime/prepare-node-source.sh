#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || -z "$1" ]]; then
  echo "Usage: prepare-node-source.sh DESTINATION" >&2
  exit 64
fi

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly LOCK_FILE="${REPOSITORY_ROOT}/RuntimeDependencies.lock.json"
readonly DESTINATION="$1"

read_lock() {
  node -e "const lock=require(process.argv[1]); process.stdout.write(String($1));" "${LOCK_FILE}"
}

readonly NODE_URL="$(read_lock 'lock.node.sourceArchive.url')"
readonly NODE_SHA256="$(read_lock 'lock.node.sourceArchive.sha256')"
readonly NODE_VERSION="$(read_lock 'lock.node.version')"
readonly NODE_COMMIT="$(read_lock 'lock.node.commit')"
readonly DESTINATION_PARENT="$(dirname "${DESTINATION}")"
readonly ARCHIVE="${DESTINATION_PARENT}/node-source-${NODE_COMMIT}.tar.gz"

node "${SCRIPT_DIR}/validate-runtime-lock.mjs" "${LOCK_FILE}" --allow-pending-build >/dev/null
mkdir -p "${DESTINATION_PARENT}"
rm -rf "${DESTINATION}"

curl --fail --location --retry 3 --retry-all-errors --silent --show-error \
  --output "${ARCHIVE}" "${NODE_URL}"

actual_sha256="$(shasum -a 256 "${ARCHIVE}" | awk '{print $1}')"
if [[ "${actual_sha256}" != "${NODE_SHA256}" ]]; then
  echo "Node source checksum mismatch: expected ${NODE_SHA256}, received ${actual_sha256}." >&2
  exit 1
fi

mkdir -p "${DESTINATION}"
tar -xzf "${ARCHIVE}" -C "${DESTINATION}" --strip-components=1
rm -f "${ARCHIVE}"

version_header="${DESTINATION}/src/node_version.h"
test -f "${version_header}"
actual_version="$(awk '
  /#define NODE_MAJOR_VERSION/ { major=$3 }
  /#define NODE_MINOR_VERSION/ { minor=$3 }
  /#define NODE_PATCH_VERSION/ { patch=$3 }
  END { print major "." minor "." patch }
' "${version_header}")"
actual_major="${actual_version%%.*}"

if [[ "${actual_version}" != "${NODE_VERSION}" || "${actual_major}" != "24" ]]; then
  echo "Pinned Node source version mismatch: expected ${NODE_VERSION}, received ${actual_version}." >&2
  exit 1
fi

echo "Prepared Node ${actual_version} (${NODE_COMMIT}) at ${DESTINATION}."
