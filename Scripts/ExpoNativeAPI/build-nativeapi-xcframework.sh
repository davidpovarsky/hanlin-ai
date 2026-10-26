#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PACKAGE_DIR="$REPO_ROOT/Packages/HanlinExpoNativeAPI"
ARTIFACTS_DIR="$PACKAGE_DIR/Artifacts"

echo "[HanlinExpoNativeAPI] Building reproducible native artifacts for Apple iOS 27..."

# Verify dependencies are prepared
node "$SCRIPT_DIR/prepare-ios-dependencies.mjs"
node "$SCRIPT_DIR/verify-nsmd.mjs"
node "$SCRIPT_DIR/verify-artifacts.mjs"

echo "[HanlinExpoNativeAPI] Native dependencies and metadata successfully staged for SwiftPM/Xcode host build."
