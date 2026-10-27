#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "[HanlinExpoNativeAPI] Preparing and verifying native assets for SwiftPM / Xcode host build..."

node "$SCRIPT_DIR/prepare-ios-dependencies.mjs"
node "$SCRIPT_DIR/verify-artifacts.mjs"
node "$SCRIPT_DIR/verify-nsmd.mjs"
node "$SCRIPT_DIR/preflight.mjs"

echo "[HanlinExpoNativeAPI] Native dependencies, metadata, and multi-target sources successfully staged."
