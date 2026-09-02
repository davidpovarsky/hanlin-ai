#!/usr/bin/env bash
set -euo pipefail

target_arch=""
arguments=("$@")
for ((index = 0; index < ${#arguments[@]}; index++)); do
    case "${arguments[$index]}" in
        -arch)
            target_arch="${arguments[$((index + 1))]:-}"
            break
            ;;
        -target)
            target_arch="${arguments[$((index + 1))]:-}"
            target_arch="${target_arch%%-*}"
            break
            ;;
    esac
done

if [[ -z "$target_arch" ]]; then
    echo "Hanlin NSLD: unable to determine target architecture" >&2
    exit 1
fi

# NativeScript metadata is regenerated at the final link, after SwiftPM has
# emitted the generated Objective-C interface that exposes embedded providers.
host_arch="$(uname -m)"
generator_root="$SRCROOT/Scripts/NativeScript/node_modules/@nativescript/ios/framework/internal/metadata-generator-$host_arch/bin"
generator="$generator_root/build-step-metadata-generator.py"
module_root="$TARGET_TEMP_DIR/HanlinNativeScriptSwiftMetadata-$target_arch"
module_map="$module_root/module.modulemap"
intermediates_root="${BUILD_DIR%/Products*}/Intermediates.noindex"
runtime_header="$intermediates_root/GeneratedModuleMaps-${PLATFORM_NAME}/HanlinNativeScriptRuntime-Swift.h"

if [[ ! -x "$generator" ]]; then
    echo "Hanlin NSLD: metadata generator is missing: $generator" >&2
    exit 1
fi
if [[ ! -f "$runtime_header" ]]; then
    echo "Hanlin NSLD: generated runtime Swift header is missing: $runtime_header" >&2
    exit 1
fi

rm -rf "$module_root"
mkdir -p "$module_root"
printf 'module hanlinnativescriptswiftsupport {\n' > "$module_map"
printf '  header "%s"\n' "$runtime_header" >> "$module_map"
swift_header_root="${PER_VARIANT_OBJECT_FILE_DIR:-}/$target_arch"
if [[ -d "$swift_header_root" ]]; then
    while IFS= read -r header; do
        printf '  header "%s"\n' "$header" >> "$module_map"
    done < <(find "$swift_header_root" -name '*-Swift.h' -type f -print | sort)
fi
printf '  export *\n}\n' >> "$module_map"

export OTHER_CFLAGS="${OTHER_CFLAGS:-} -fmodule-map-file=\"$module_map\""
pushd "$generator_root" >/dev/null
"$generator" "$target_arch"
popd >/dev/null
test -s "$CONFIGURATION_BUILD_DIR/metadata-$target_arch.bin"
rm -rf "$module_root"

if [[ -n "${NS_LD:-}" && -x "${NS_LD}" ]]; then
    real_linker="$NS_LD"
elif [[ -n "${DT_TOOLCHAIN_DIR:-}" && -x "$DT_TOOLCHAIN_DIR/usr/bin/clang" ]]; then
    real_linker="$DT_TOOLCHAIN_DIR/usr/bin/clang"
else
    real_linker="$(xcrun --find clang)"
fi

exec "$real_linker" "$@"
