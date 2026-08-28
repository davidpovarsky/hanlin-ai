#!/usr/bin/env bash
set -euo pipefail

target_arch=""
previous=""
for argument in "$@"; do
    if [[ "$previous" == "-arch" ]]; then
        target_arch="$argument"
        break
    fi
    if [[ "$previous" == "-target" ]]; then
        target_arch="${argument%%-*}"
        break
    fi
    previous="$argument"
done

if [[ -z "$target_arch" ]]; then
    echo "Hanlin NativeScript linker: unable to determine target architecture." >&2
    exit 1
fi

script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tool_root="$script_root/node_modules/@nativescript/ios/framework/internal"
host_arch="$(uname -m)"
generator_root="$tool_root/metadata-generator-$host_arch/bin"
generator="$generator_root/build-step-metadata-generator.py"

if [[ ! -x "$generator" ]]; then
    echo "Hanlin NativeScript metadata tooling is missing. Run npm ci --prefix Scripts/NativeScript." >&2
    exit 1
fi

pushd "$generator_root" >/dev/null
"$generator" "$target_arch"
popd >/dev/null

if [[ -n "${NS_LD:-}" && -x "${NS_LD}" ]]; then
    real_linker="$NS_LD"
elif [[ -n "${DT_TOOLCHAIN_DIR:-}" && -x "$DT_TOOLCHAIN_DIR/usr/bin/clang" ]]; then
    real_linker="$DT_TOOLCHAIN_DIR/usr/bin/clang"
else
    real_linker="$(xcrun --find clang)"
fi

exec "$real_linker" "$@"
