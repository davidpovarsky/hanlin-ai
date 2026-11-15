#!/usr/bin/env python3
"""Execute focused cross-grammar controls with real ASTs and original serializers."""
import hashlib
import importlib.util
import json
from pathlib import Path
import platform
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
OUTPUT = ROOT / "build/acceptance/metadata-dual-grammar-controls"


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    if sys.platform != "darwin" or platform.machine() != "arm64":
        raise RuntimeError("Actual pinned macOS arm64 compiler required")
    OUTPUT.mkdir(parents=True, exist_ok=False)
    sys.path.insert(0, str(ROOT / "Scripts/NativeScript"))
    spec = importlib.util.spec_from_file_location("actual_metadata_wrapper", ROOT / "Scripts/NativeScript/build-step-metadata-generator-wrapper.py")
    wrapper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(wrapper)
    tool_root, library = wrapper.validate_modern_tool(ROOT)
    provenance = json.loads((tool_root / "provenance.json").read_text())
    binary = tool_root / "bin/HanlinDualGrammarControls"
    if sha(binary) != provenance["dualControlBinarySHA256"]:
        raise RuntimeError("Actual dual-control image/provenance mismatch")
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip()
    resource = Path(provenance["frontendRoot"]) / "lib/clang/20"
    write(OUTPUT / "preflight.json", {"sourceSHA": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
        "sdk": sdk, "resourceDirectory": str(resource), "binarySHA256": sha(binary),
        "generatorSHA256": provenance["generatorSHA256"], "classifierLibrarySHA256": sha(library),
        "mergePolicyVersion": 2, "runtimeAcceptance": "NOT_ESTABLISHED"})

    core = """#pragma once
#ifdef __cplusplus
extern "C" {
#endif
struct HanlinDualShared {
  SHARED_FIELD
  double ratio;
};
RETURN_TYPE HanlinDualSharedFunction(struct HanlinDualShared *value);
int HanlinDualTakeSigned(int value);
unsigned long HanlinDualTakeUnsigned(unsigned long value);
double HanlinDualTakeDouble(double value);
void HanlinDualTakePointer(void *value);
struct HanlinDualShared *HanlinDualReturnShared(void);
static const int HanlinDualConstant = CONSTANT_VALUE;
#ifdef __cplusplus
}
#endif
#if !defined __cplusplus
struct HanlinDualCOnlyRecord { int code; double amount; };
int HanlinDualCOnlyFunction(struct HanlinDualCOnlyRecord *value);
_Static_assert(sizeof(struct HanlinDualCOnlyRecord) == 16, "Actual target ABI fixture size");
OBJC_INVALID
#endif
CLASS_ATTRIBUTE
__attribute__((objc_root_class))
@interface HanlinDualObject { void *isa; int _token; }
@property(nonatomic) int token;
@end
"""
    baseline = core.replace("SHARED_FIELD", "int value;").replace("RETURN_TYPE", "int").replace("CONSTANT_VALUE", "42").replace("OBJC_INVALID", "").replace("CLASS_ATTRIBUTE", "")
    provider = '#include "core.h"\nnamespace hanlin_cpp { template<class T> struct Token { T value; }; }\nextern "C" int HanlinDualProvider(struct HanlinDualShared *value);\n'
    cases = [
        ("equivalent-c-only-and-lifetime", baseline, "pass", ""),
        ("conflicting-layout", core.replace("SHARED_FIELD", "\n#ifdef __cplusplus\nlong long value;\n#else\nint value;\n#endif\n").replace("RETURN_TYPE", "int").replace("CONSTANT_VALUE", "42").replace("OBJC_INVALID", "").replace("CLASS_ATTRIBUTE", ""), "merge-failure", "Dual-grammar actual AST ABI conflict:"),
        ("conflicting-signature", "#ifdef __cplusplus\ntypedef long long HanlinDualReturn;\n#else\ntypedef int HanlinDualReturn;\n#endif\n" + baseline.replace("int HanlinDualSharedFunction", "HanlinDualReturn HanlinDualSharedFunction"), "merge-failure", "Dual-grammar actual AST ABI conflict:"),
        ("conflicting-constant", "#ifdef __cplusplus\n#define HANLIN_REAL_FIXTURE_CONSTANT 43\n#else\n#define HANLIN_REAL_FIXTURE_CONSTANT 42\n#endif\n" + baseline.replace("HanlinDualConstant = 42", "HanlinDualConstant = HANLIN_REAL_FIXTURE_CONSTANT"), "merge-failure", "Dual-grammar actual API model conflict:"),
        ("conflicting-availability", baseline.replace("__attribute__((objc_root_class))", "#ifdef __cplusplus\n__attribute__((availability(ios,introduced=26.0)))\n#else\n__attribute__((availability(ios,introduced=25.0)))\n#endif\n__attribute__((objc_root_class))"), "merge-failure", "Dual-grammar availability conflict:"),
        ("conflicting-physical-owner", baseline, "merge-failure", "Dual-grammar canonical declaration/owner conflict:"),
        ("invalid-objc-pass", baseline.replace("_Static_assert", "HanlinOnlyBadType invalid;\n_Static_assert"), "parse-failure", "Actual dual-grammar AST parse failed"),
    ]
    results = []
    for name, source, expectation, expected_reason in cases:
        folder = OUTPUT / name
        folder.mkdir()
        if name == "conflicting-physical-owner":
            (folder / "owner_cpp.h").write_text(source)
            (folder / "owner_objc.h").write_text(source)
            source = '#ifdef __cplusplus\n#include "owner_cpp.h"\n#else\n#include "owner_objc.h"\n#endif\n'
        (folder / "core.h").write_text(source)
        (folder / "provider.hpp").write_text(provider)
        (folder / "full.h").write_text('#include "core.h"\n#include "provider.hpp"\n')
        (folder / "objc.h").write_text('#include "core.h"\n')
        headers = ["core.h", "provider.hpp"] + (["owner_cpp.h", "owner_objc.h"] if name == "conflicting-physical-owner" else [])
        (folder / "module.modulemap").write_text('module HanlinDualFixture {\n' + ''.join(' header "' + path + '"\n' for path in headers) + ' export *\n}\n')
        output = folder / "metadata.bin"
        receipt = folder / "native-receipt.json"
        config = folder / "config.json"
        write(config, {"root": str(folder), "sdk": sdk, "resource": str(resource),
            "target": "arm64-apple-ios27.0-simulator", "output": str(output), "receipt": str(receipt),
            "expectation": expectation, "expectedReason": expected_reason})
        command = [str(binary), str(config)]
        write(folder / "command.json", {"argv": command, "cwd": str(tool_root / "bin"), "timeoutSeconds": 60})
        started = time.monotonic()
        run = subprocess.run(command, cwd=tool_root / "bin", capture_output=True, timeout=60)
        (folder / "stdout.log").write_bytes(run.stdout)
        (folder / "stderr.log").write_bytes(run.stderr)
        actual = json.loads(receipt.read_text()) if receipt.is_file() else {}
        if run.returncode < 0 and not receipt.exists() and not output.exists() and not (OUTPUT / "crash-backtrace.log").exists():
            debug_command = ["xcrun", "lldb", "--batch", "-o", "run", "-k", "thread backtrace all", "-k", "register read", "--", *command]
            write(OUTPUT / "crash-backtrace-command.json", {"argv": debug_command, "boundary": "Diagnostic rerun of first crashing fixture; never a test pass"})
            debug_run = subprocess.run(debug_command, cwd=tool_root / "bin", capture_output=True, timeout=60)
            (OUTPUT / "crash-backtrace.log").write_bytes(debug_run.stdout + debug_run.stderr)
        expected_status = "EXECUTED_PASS" if expectation == "pass" else "REJECTED_EXPECTED"
        passed = run.returncode == 0 and actual.get("status") == expected_status
        if expectation == "pass":
            passed = passed and output.is_file() and actual.get("lifetime", {}).get("bothSourceManagersReadAfterSerialization") is True and actual.get("crossFactoryTypeValidation") is True
            if output.is_file():
                body = output.read_bytes()
                passed = passed and all(name.encode() + b"\0" in body for name in ["HanlinDualCOnlyRecord", "HanlinDualCOnlyFunction", "HanlinDualProvider"])
        else:
            passed = passed and not output.exists() and actual.get("writerEntries") == 0 and actual.get("reason", "").startswith(expected_reason)
            if expectation == "parse-failure":
                passed = passed and b"unknown type name 'HanlinOnlyBadType'" in run.stderr
        results.append({"case": name, "status": "EXECUTED_PASS" if passed else "FAILED", "nativeStatus": actual.get("status"),
            "exitCode": run.returncode, "seconds": time.monotonic() - started, "expectation": expectation,
            "reason": actual.get("reason"), "nativeReceiptSHA256": sha(receipt) if receipt.is_file() else None})
        write(OUTPUT / "result.json", {"status": "RUNNING", "cases": results})
        print(name + ": " + results[-1]["status"], flush=True)
    passed = len(results) == len(cases) and all(case["status"] == "EXECUTED_PASS" for case in results)
    write(OUTPUT / "result.json", {"status": "EXECUTED_PASS" if passed else "FAILED", "cases": results,
        "boundary": "Fresh real compiler/model/ABI/lifetime/serializer fixture controls; no SDK/app/VM/UI/device pass."})
    manifest = [{"path": p.relative_to(OUTPUT).as_posix(), "sha256": sha(p), "bytes": p.stat().st_size}
                for p in sorted(OUTPUT.rglob("*")) if p.is_file()]
    write(OUTPUT / "artifact-manifest.json", manifest)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
