#!/usr/bin/env bash
set -euo pipefail

# build-nativeapi-xcframework.sh alias for backwards compatibility
# Native compilation occurs in Xcode 27 / SwiftPM via AI_HLY scheme
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/prepare-nativeapi-assets.sh" "$@"
