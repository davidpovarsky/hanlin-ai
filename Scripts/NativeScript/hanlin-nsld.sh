#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${NS_LD:-}" && -x "${NS_LD}" ]]; then
    real_linker="$NS_LD"
elif [[ -n "${DT_TOOLCHAIN_DIR:-}" && -x "$DT_TOOLCHAIN_DIR/usr/bin/clang" ]]; then
    real_linker="$DT_TOOLCHAIN_DIR/usr/bin/clang"
else
    real_linker="$(xcrun --find clang)"
fi

exec "$real_linker" "$@"
