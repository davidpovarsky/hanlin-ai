#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR=/Users/m1/builds/hanlin-two-wave-root-20261126/source/Scripts/Runtime
readonly REPOSITORY_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly HOST_SOURCE="${REPOSITORY_ROOT}/AI_HLY/Downstream/RuntimeCore/Node/Host"
readonly WORK_ROOT="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/hanlin-runtime-host"
readonly OUTPUT_ROOT=/Users/m1/builds/hanlin-two-wave-root-20261126/source/build/runtime-host-f768d634-original-phases-r1
readonly GRAMMAR_TOOL_ROOT="${WORK_ROOT}-grammar-tools"

# MiniApp authoring consumes the same original npm packages as the native host.
# This is included with the tool implementation, not installed during an agent run.
# Refresh documentation from the prepared native inputs before any SDK/Host reuse
# fingerprint; a cache hit must not preserve provenance from an earlier graph.
if [[ -f "${HOST_SOURCE}/miniapp-authoring.mjs" ]]; then
  for engine in expo nativescript; do
    node "${REPOSITORY_ROOT}/Scripts/MiniApps/install-tooling.mjs" --repository="${REPOSITORY_ROOT}" --engine="$engine" --ignore-scripts
  done
  node "${REPOSITORY_ROOT}/Scripts/Expo/prepare-types.mjs"
  node "${REPOSITORY_ROOT}/Scripts/MiniApps/generate-scriptwidget-types.mjs" --check
  node "${REPOSITORY_ROOT}/Scripts/Audit/audit-miniapp-sdk.mjs" --write
  node "${REPOSITORY_ROOT}/Scripts/Audit/audit-miniapp-sdk.mjs" --check
  python3 "${REPOSITORY_ROOT}/Scripts/Audit/audit_miniapp_reachability.py"
  python3 "${REPOSITORY_ROOT}/Scripts/Audit/audit_miniapp_reachability.py" --check
fi

readonly NODE_FINGERPRINT="$(node -p 'JSON.stringify({ versions: process.versions, platform: process.platform, arch: process.arch })')"
if python3 "${SCRIPT_DIR}/runtime_host_archive.py" reuse "${OUTPUT_ROOT}" --source-root "${HOST_SOURCE}" --node-fingerprint "${NODE_FINGERPRINT}"; then
  echo "Reusing verified current RuntimeHostResources.zip and its completed Host/JITless checks."
  exit 0
fi

rm -rf "${WORK_ROOT}" "${OUTPUT_ROOT}" "${GRAMMAR_TOOL_ROOT}"
mkdir -p "${WORK_ROOT}" "${OUTPUT_ROOT}" "${GRAMMAR_TOOL_ROOT}"
cp "${SCRIPT_DIR}/HostGrammarTools/package.json" "${SCRIPT_DIR}/HostGrammarTools/package-lock.json" "${GRAMMAR_TOOL_ROOT}/"
(cd "${GRAMMAR_TOOL_ROOT}" && npm ci --ignore-scripts --workspaces=false --no-audit --no-fund)
export HANLIN_HOST_GRAMMAR_COMPILER_ROOT="${GRAMMAR_TOOL_ROOT}"
export HANLIN_MINIAPP_REPOSITORY_ROOT="${REPOSITORY_ROOT}"
export HANLIN_RUNTIME_TEST_FIXTURES="${REPOSITORY_ROOT}/AI_HLYTests/Fixtures/RuntimeNetworkFixtures.bundle"
cp \
  "${HOST_SOURCE}"/*.mjs \
  "${HOST_SOURCE}/package.json" \
  "${HOST_SOURCE}/package-lock.json" \
  "${HOST_SOURCE}/runtime-dependency-overrides.json" \
  "${HOST_SOURCE}/host-dependency-patches.json" \
  "${HOST_SOURCE}/UNICODE-LICENSE.txt" \
  "${HOST_SOURCE}/PEGJS-LICENSE.txt" \
  "${WORK_ROOT}/"
cp -R "${HOST_SOURCE}/Tests" "${WORK_ROOT}/Tests"

if [[ -f "${HOST_SOURCE}/miniapp-authoring.mjs" ]]; then
  node "${REPOSITORY_ROOT}/Scripts/MiniApps/stage-sdk.mjs" --repository="${REPOSITORY_ROOT}" --output="${WORK_ROOT}/MiniAppSDK"
fi

readonly SOURCE_INPUTS_HASH="$(python3 "${SCRIPT_DIR}/runtime_host_archive.py" fingerprint --source-root "${HOST_SOURCE}" --node-fingerprint "${NODE_FINGERPRINT}")"

(
  cd "${WORK_ROOT}"
  npm ci --omit=dev --ignore-scripts --workspaces=false --no-audit --no-fund
  node apply-host-dependency-patches.mjs
  node "${SCRIPT_DIR}/generate-yarn-unicode-patch.mjs" --root "${WORK_ROOT}"
  node "${SCRIPT_DIR}/generate-yarn-multiline-patch.mjs" --root "${WORK_ROOT}" --compiler-root "${GRAMMAR_TOOL_ROOT}"
)
