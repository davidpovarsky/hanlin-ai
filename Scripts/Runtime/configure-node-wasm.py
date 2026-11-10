#!/usr/bin/env python3
"""Wire pinned V8's existing DrumBrake sources into Node Mobile's GYP build.

This downstream build adapter is not an upstream backport. It does not enable
JIT, remove bounds checks, change engine versions or fabricate verification.
"""
from __future__ import annotations
import argparse
import ast
import hashlib
import json
from pathlib import Path

SOURCE_COMMIT = "4768489cd0cfa3bb0c27786e958c6446c004f1bd"
PREIMAGES = {
    "tools/v8_gypfiles/features.gypi": "afbcb2609a6c4f684a092485fbf9a7666f2f44a4f20eb5931b58ec0b3d49b7a3",
    "tools/v8_gypfiles/v8.gyp": "371223b2620db3f0c3a65e8be09096acdeb549435a2d23fe22b2dced6f717230",
    "tools/ios_framework_prepare.sh": "864dbf89ceed04b93c88bcd03cb35c63ad1d5ec08bb8e3447fba10885c82b8a7",
}
POSTIMAGES = {
    "tools/v8_gypfiles/features.gypi": "90da41738ea9ec84ed3c633b6c3e92281116f5c83e9b79a4fba5771d0af94396",
    "tools/v8_gypfiles/v8.gyp": "d55186e1cf0e015994c34f46d3df40b3ce18e642b17e229440ba4cce97a1532a",
    "tools/ios_framework_prepare.sh": "1d08245dd2b0382b5097533b9628eb40e5a36a2dc39adb2753b2539c4953d052",
}
INTERPRETER_SOURCES = [
    "src/wasm/interpreter/wasm-interpreter-objects.cc",
    "src/wasm/interpreter/wasm-interpreter-runtime.cc",
    "src/wasm/interpreter/wasm-interpreter-simd.cc",
    "src/wasm/interpreter/wasm-interpreter.cc",
]

def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def replace_once(text: str, before: str, after: str) -> str:
    if text.count(before) != 1:
        raise ValueError("Ambiguous pinned GYP build anchor: " + before)
    return text.replace(before, after, 1)

def target_condition(text: str, target: str, condition: str) -> str:
    start = text.index("'target_name': '" + target + "'")
    end = text.index("    },  # " + target + "\n", start)
    section = text[start:end]
    patched = replace_once(section, "\n      'conditions': [\n", "\n      'conditions': [\n" + condition)
    return text[:start] + patched + text[end:]

def transform(name: str, text: str) -> str:
    if name.endswith("features.gypi"):
        text = replace_once(text, "    'v8_enable_webassembly%': 1,\n",
            "    'v8_enable_webassembly%': 1,\n"
            "    # Hanlin: existing V8 interpreter, no Wasm executable pages.\n"
            "    'v8_enable_drumbrake%': 1,\n")
        anchor = "      ['v8_enable_webassembly==1', {\n"
        text = replace_once(text, anchor,
            "      ['v8_enable_drumbrake==1', {\n"
            "        'defines': ['V8_ENABLE_DRUMBRAKE', 'V8_DRUMBRAKE_BOUNDS_CHECKS'],\n"
            "      }],\n" + anchor)
        ast.literal_eval(text)
        return text
    if name.endswith("v8.gyp"):
        text = target_condition(text, "v8_base_without_compiler",
            "        ['v8_enable_webassembly==1 and v8_enable_drumbrake==1', {\n"
            "          'sources': [\n" + "".join("            '<(V8_ROOT)/" + source + "',\n" for source in INTERPRETER_SOURCES) +
            "          ],\n        }],\n")
        text = target_condition(text, "v8_initializers",
            "        ['v8_enable_webassembly==1 and v8_enable_drumbrake==1', {\n"
            "          'conditions': [\n"
            "            ['v8_target_arch==\"arm64\"', {\n"
            "              'sources': ['<(V8_ROOT)/src/wasm/interpreter/arm64/interpreter-builtins-arm64.cc'],\n"
            "            }],\n"
            "            ['v8_target_arch==\"x64\"', {\n"
            "              'sources': ['<(V8_ROOT)/src/wasm/interpreter/x64/interpreter-builtins-x64.cc'],\n"
            "            }],\n"
            "          ],\n        }],\n")
        ast.literal_eval(text)
        return text
    if name.endswith("ios_framework_prepare.sh"):
        before = "--v8-options=--jitless \\\n"
        if text.count(before) != 3:
            raise ValueError("Unexpected pinned iOS configure commands")
        return text.replace(before,
            "--v8-options='--jitless --wasm-jitless' \\\n"
            "    --experimental-enable-pointer-compression \\\n")
    raise ValueError("Unknown native build adapter target")

def proposed_changes(source: Path) -> list[tuple[Path, bytes, dict]]:
    changes = []
    for name, expected in PREIMAGES.items():
        target = (source / name).resolve(strict=True)
        if not target.is_relative_to(source):
            raise ValueError("Native build adapter path escapes source root")
        before = target.read_bytes()
        if digest(before) == POSTIMAGES[name]:
            after = before
        elif digest(before) != expected:
            raise ValueError("Unexpected pinned Node build preimage: " + name)
        else:
            after = transform(name, before.decode("utf-8")).encode("utf-8")
        if digest(after) != POSTIMAGES[name]:
            raise ValueError("Unexpected Node build adapter output: " + name)
        changes.append((target, after, {"path": name, "beforeSHA256": expected, "afterSHA256": digest(after)}))
    return changes

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--describe", action="store_true", help="Validate and describe without modifying source")
    args = parser.parse_args()
    source = args.source.resolve(strict=True)
    changes = proposed_changes(source)
    if not args.describe:
        # All exact source preimages validate before any disposable source edit.
        for target, contents, _ in changes:
            target.write_bytes(contents)
    print(json.dumps({"sourceCommit": SOURCE_COMMIT, "wasmInterpreter": "drumbrake", "jitless": True,
        "explicitBoundsChecks": True, "pointerCompression": True,
        "files": [item[2] for item in changes]}, sort_keys=True))

if __name__ == "__main__":
    main()
