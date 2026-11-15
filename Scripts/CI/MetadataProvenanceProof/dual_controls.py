#!/usr/bin/env python3
"""Execute focused cross-grammar controls with real ASTs and original serializers."""
import hashlib
import importlib.util
import json
import os
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
        "mergePolicyVersion": 3, "runtimeAcceptance": "NOT_ESTABLISHED"})

    core = """#pragma once
#ifdef __cplusplus
extern "C" {
#endif
#ifdef __cplusplus
#define HANLIN_PARAM_ALIAS
#define HANLIN_NO_PROTO_PARAM
#define HANLIN_NO_PROTO_CB_PARAM
#else
#define HANLIN_PARAM_ALIAS restrict
#define HANLIN_NO_PROTO_PARAM
#define HANLIN_NO_PROTO_CB_PARAM
#endif
struct HanlinDualShared {
  SHARED_FIELD
  double ratio;
};
struct HanlinDualLateNamed { int value; };
typedef struct HanlinDualLateNamed HanlinDualLaterAlias;
typedef struct HanlinDualInlineNamed { double amount; } HanlinDualInlineAlias;
int HanlinDualRecordAliases(struct HanlinDualLateNamed *original, HanlinDualLaterAlias *later, HanlinDualInlineAlias *inlineAlias);
RETURN_TYPE HanlinDualSharedFunction(struct HanlinDualShared *value);
int HanlinDualTakeSigned(int value);
int HanlinDualNoPrototype(HANLIN_NO_PROTO_PARAM);
typedef int (*HanlinDualNoProtoCallback)(HANLIN_NO_PROTO_CB_PARAM);
int HanlinDualUseNoProtoCallback(HanlinDualNoProtoCallback value);
unsigned long HanlinDualTakeUnsigned(unsigned long value);
double HanlinDualTakeDouble(double value);
void HanlinDualTakePointer(void * HANLIN_PARAM_ALIAS value);
typedef int (*HanlinDualCallback)(int * HANLIN_PARAM_ALIAS value);
int HanlinDualUseCallback(HanlinDualCallback value);
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
struct HanlinDualOpaque;
extern struct HanlinDualOpaque HanlinDualOpaqueObject;
extern const char *const HanlinDualSignNames[32];
int HanlinDualAsmFunction(int value) __asm__("hanlin_dual_function");
EXTERNAL_BINDING
@protocol HanlinDualRepeatedProtocol
- (int)repeatProtocolMarker;
@end
#ifdef __cplusplus
@interface HanlinDualObject (CppFirstConformance) <HanlinDualRepeatedProtocol>
@end
@interface HanlinDualObject (CppSecondConformance) <HanlinDualRepeatedProtocol>
@end
#endif
@interface HanlinDualRepeatedConsumer : HanlinDualObject <HanlinDualRepeatedProtocol>
@end
@interface HanlinDualRepeatedConsumer (ActualAdditionalConformance) <HanlinDualRepeatedProtocol>
@end
@interface HanlinDualGeneric<Element> : HanlinDualObject
@end
@interface HanlinDualDerived : HanlinDualGeneric<HanlinDualObject *>
@end
#ifdef __cplusplus
#define HANLIN_DECL_EXPORT extern "C" __attribute__((visibility("default")))
#else
#define HANLIN_DECL_EXPORT extern __attribute__((visibility("default")))
#endif
__attribute__((availability(ios,introduced=2.0)))
__attribute__((objc_root_class))
HANLIN_DECL_EXPORT
@interface HanlinDualPrefixAvailable { void *isa; }
@end
"""
    baseline = core.replace("SHARED_FIELD", "int value;").replace("RETURN_TYPE", "int").replace("CONSTANT_VALUE", "42").replace("OBJC_INVALID", "").replace("CLASS_ATTRIBUTE", "").replace("EXTERNAL_BINDING", "")
    provider = '#include "core.h"\nnamespace hanlin_cpp { template<class T> struct Token { T value; }; }\nextern "C" int HanlinDualProvider(struct HanlinDualShared *value);\n@interface HanlinDualProviderObject : HanlinDualGeneric<HanlinDualObject *>\n@end\n'
    cases = [
        ("equivalent-c-only-and-lifetime", baseline, "pass", ""),
        ("conflicting-layout", core.replace("SHARED_FIELD", "\n#ifdef __cplusplus\nlong long value;\n#else\nint value;\n#endif\n").replace("RETURN_TYPE", "int").replace("CONSTANT_VALUE", "42").replace("OBJC_INVALID", "").replace("CLASS_ATTRIBUTE", "").replace("EXTERNAL_BINDING", ""), "merge-failure", "Dual-grammar actual AST ABI conflict:"),
        ("conflicting-signature", "#ifdef __cplusplus\ntypedef long long HanlinDualReturn;\n#else\ntypedef int HanlinDualReturn;\n#endif\n" + baseline.replace("int HanlinDualSharedFunction", "HanlinDualReturn HanlinDualSharedFunction"), "merge-failure", "Dual-grammar actual AST ABI conflict:"),
        ("no-prototype-parameter-loss-rejected", baseline.replace("#define HANLIN_NO_PROTO_PARAM\n", "#define HANLIN_NO_PROTO_PARAM int value\n", 1), "merge-failure", "Dual-grammar actual AST ABI conflict:"),
        ("no-prototype-callback-parameter-loss-rejected", baseline.replace("#define HANLIN_NO_PROTO_CB_PARAM\n", "#define HANLIN_NO_PROTO_CB_PARAM int value\n", 1), "merge-failure", "Dual-grammar actual AST ABI conflict:"),
        ("conflicting-pointee-qualifier", "#ifdef __cplusplus\n#define HANLIN_POINTEE_CONST const\n#else\n#define HANLIN_POINTEE_CONST\n#endif\n" + baseline.replace("int HanlinDualTakeSigned(int value);", "int HanlinDualTakeSigned(HANLIN_POINTEE_CONST int *value);"), "merge-failure", "Dual-grammar actual AST ABI conflict:"),
        ("conflicting-constant", "#ifdef __cplusplus\n#define HANLIN_REAL_FIXTURE_CONSTANT 43\n#else\n#define HANLIN_REAL_FIXTURE_CONSTANT 42\n#endif\n" + baseline.replace("HanlinDualConstant = 42", "HanlinDualConstant = HANLIN_REAL_FIXTURE_CONSTANT"), "merge-failure", "Dual-grammar actual API model conflict:"),
        ("conflicting-symbol-binding", "#ifdef __cplusplus\n#define HANLIN_ACTUAL_BINDING \"hanlin_cpp_symbol\"\n#else\n#define HANLIN_ACTUAL_BINDING \"hanlin_c_symbol\"\n#endif\n" + baseline + "\nextern int HanlinDualAlias __asm__(HANLIN_ACTUAL_BINDING);\n", "merge-failure", "Dual-grammar actual AST ABI conflict:"),
        ("conflicting-function-symbol", "#ifdef __cplusplus\n#define HANLIN_FUNCTION_BINDING \"hanlin_cpp_function\"\n#else\n#define HANLIN_FUNCTION_BINDING \"hanlin_c_function\"\n#endif\n" + baseline + "\nint HanlinDualFunctionAlias(int value) __asm__(HANLIN_FUNCTION_BINDING);\n", "merge-failure", "Dual-grammar actual AST ABI conflict:"),
        ("nonSDK-unexported-mangling", baseline + "\nint HanlinDualNonSDKMangled(int value);\n", "merge-failure", "Dual-grammar actual AST ABI conflict:"),
        ("opaque-by-value-rejected", baseline + "\n#ifdef __cplusplus\nextern \"C\" {\n#endif\nvoid HanlinDualOpaqueByValue(struct HanlinDualOpaque value);\n#ifdef __cplusplus\n}\n#endif\n", "merge-failure", "Unproven actual CPP ABI:"),
        ("conflicting-availability", baseline.replace("__attribute__((objc_root_class))", "#ifdef __cplusplus\n__attribute__((availability(ios,introduced=26.0)))\n#else\n__attribute__((availability(ios,introduced=25.0)))\n#endif\n__attribute__((objc_root_class))", 1), "merge-failure", "Dual-grammar availability conflict:"),
        ("missing-cpp-availability-before-target", baseline.replace("availability(ios,introduced=2.0)", "availability(ios,introduced=28.0)"), "merge-failure", "Dual-grammar availability conflict:"),
        ("conflicting-physical-owner", baseline, "merge-failure", "Dual-grammar canonical declaration/owner conflict:"),
        ("invalid-objc-pass", baseline.replace("_Static_assert", "HanlinOnlyBadType invalid;\n_Static_assert"), "parse-failure", "Actual dual-grammar AST parse failed"),
    ]
    from metadata_dual_grammar import create_request, validate_receipt
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
            passed = passed and output.is_file() and actual.get("lifetime", {}).get("bothSourceManagersReadAfterSerialization") is True and actual.get("crossFactoryTypeValidation") is True and actual.get("actualRecordAliasIdentity") is True and actual.get("sameProtocolObjectMultiplicityPreserved") is True and actual.get("cppAddedProtocolRoutedToCanonicalCObject") is True and actual.get("bindingNameOnlyGuardCounterexamples") is True
            if output.is_file():
                body = output.read_bytes()
                passed = passed and all(name.encode() + b"\0" in body for name in ["HanlinDualCOnlyRecord", "HanlinDualCOnlyFunction", "HanlinDualProvider"])
            declarations = list(folder.glob("metadata.bin.types/*.d.ts"))
            declaration_text = "\n".join(path.read_text() for path in declarations)
            for no_prototype_name in ["HanlinDualNoPrototype", "HanlinDualUseNoProtoCallback"]:
                rows = [item for item in actual.get("mergeProof", {}).get("duplicateProofs", []) if item["canonicalKey"].split("\n")[2] == no_prototype_name]
                passed = passed and len(rows) == 1 and rows[0].get("disposition") == "PROVEN_ORIGINAL_NO_PROTOTYPE_ENCODING_OBJC_AUTHORITY"
                if len(rows) == 1:
                    facts = rows[0].get("rawCallablePrototypeDifference", {})
                    c_unknown = [entry for entry in facts.get("objc", []) if entry.get("hasPrototype") is False]
                    cpp_empty = [entry for entry in facts.get("cpp", []) if entry.get("hasPrototype") is True and entry.get("sourceDeclaredParameterCount") == 0]
                    passed = passed and facts.get("sourcePrototypeTypesEquivalent") is False and bool(c_unknown) and bool(cpp_empty) and all(entry.get("sourceDeclaredParameterCount") is None and entry.get("originalFactorySignatureEntries") == 1 and entry.get("callingConvention") == 0 for entry in c_unknown)
            sign_names = [item for item in actual.get("mergeProof", {}).get("duplicateProofs", []) if "HanlinDualSignNames" in item["canonicalKey"]]
            passed = passed and len(sign_names) == 1 and sign_names[0].get("rawVariableLinkage") == {
                "cppLanguageLinkage": 1, "objcLanguageLinkage": 0} and sign_names[0].get("actualASTABI", {}).get("externalBinding", {}).get("clangSymbolBeforeTargetPrefix") == "HanlinDualSignNames"
            opaque_objects = [item for item in actual.get("mergeProof", {}).get("duplicateProofs", []) if "HanlinDualOpaqueObject" in item["canonicalKey"]]
            passed = passed and len(opaque_objects) == 1 and opaque_objects[0].get("actualASTABI", {}).get("type", {}).get("storageContract") == "EXTERNAL_OPAQUE_OBJECT_NO_BY_VALUE_ENCODING" and opaque_objects[0]["actualASTABI"]["type"].get("layout") == "NOT_DECLARED"
            prefix_availability = [item for item in actual.get("mergeProof", {}).get("duplicateProofs", []) if "HanlinDualPrefixAvailable" in item["canonicalKey"]]
            passed = passed and len(prefix_availability) == 1 and prefix_availability[0].get("cppIntroducedIn") == "" and prefix_availability[0].get("objcIntroducedIn") == "2.0" and prefix_availability[0].get("availability") == "ACTUAL_C_INTRODUCED_ATTR_MISSING_CPP_EQUIVALENT_AT_BOUND_TARGET"
            asm_functions = [item for item in actual.get("mergeProof", {}).get("duplicateProofs", []) if "HanlinDualAsmFunction" in item["canonicalKey"]]
            passed = passed and len(asm_functions) == 1 and asm_functions[0].get("rawFunctionLinkage") == {
                "cppLanguageLinkage": 1, "objcLanguageLinkage": 0} and asm_functions[0].get("actualASTABI", {}).get("externalBinding", {}).get("clangSymbolBeforeTargetPrefix") == "\x01hanlin_dual_function"
            canonical_parameters = [item for item in actual.get("mergeProof", {}).get("duplicateProofs", []) if "HanlinDualTakePointer" in item["canonicalKey"]]
            passed = passed and len(canonical_parameters) == 1 and canonical_parameters[0].get("cppRawParameterCVR") == [0] and canonical_parameters[0].get("objcRawParameterCVR") == [2] and canonical_parameters[0]["actualASTABI"].get("parameterTypeRule") == "ASTContext.getCanonicalParamType"
            passed = passed and bool(declarations) and all(fragment in declaration_text for fragment in [
                "HanlinDualDerived extends HanlinDualGeneric<HanlinDualObject>",
                "HanlinDualProviderObject extends HanlinDualGeneric<HanlinDualObject>",
                "HanlinDualCOnlyFunction", "HanlinDualProvider"])
        else:
            passed = passed and not output.exists() and actual.get("writerEntries") == 0 and actual.get("reason", "").startswith(expected_reason)
            if expectation == "parse-failure":
                passed = passed and b"unknown type name 'HanlinOnlyBadType'" in run.stderr
        # Exercise the real producer entry and its publication boundary using
        # the same actual fixture inputs, never merely the focused test main.
        transaction = folder / "transaction"
        transaction.mkdir()
        target_binary = transaction / "metadata.bin"
        request_path = transaction / "request.json"
        producer = tool_root / "bin/objc-metadata-generator"
        cpp_arguments = actual.get("cppArguments")
        transaction_result = {"status": "NOT_RUN"}
        if cpp_arguments:
            producer_command = [str(producer), "-input-umbrella", str(folder / "full.h"),
                "-output-bin", str(target_binary), "-output-yaml", str(transaction / "yaml"),
                "-output-typescript", str(transaction / "types"), "-output-umbrella", str(transaction / "umbrella.h"),
                "-hanlin-dual-grammar-request", str(request_path), "Xclang", *cpp_arguments]
            context_file = transaction / "actual-context.bin"
            context = wrapper.capture_native_compiler_context(producer, {"generatorCall": producer_command},
                os.environ.copy(), tool_root / "bin", context_file)
            create_request(request_path, folder / "full.h", folder / "objc.h", context, Path(sdk),
                [*folder.glob("*.h"), folder / "provider.hpp", folder / "module.modulemap",
                 tool_root / "provenance.json", ROOT / "Scripts/NativeScript/metadata_dual_grammar.py"])
            position = producer_command.index("Xclang")
            producer_command[position:position] = ["-hanlin-expected-clang-context", str(context_file)]
            write(transaction / "command.json", producer_command)
            executed = subprocess.run(producer_command, cwd=tool_root / "bin", capture_output=True, timeout=90)
            (transaction / "stdout.log").write_bytes(executed.stdout)
            (transaction / "stderr.log").write_bytes(executed.stderr)
            receipt_file = target_binary.with_name(target_binary.name + ".dual-grammar.json")
            try:
                if expectation == "pass":
                    if executed.returncode != 0:
                        raise RuntimeError("Real transaction producer failed: " + executed.stderr.decode(errors="replace")[-1600:])
                    actual_receipt = validate_receipt(target_binary, request_path, context, producer)
                    transaction_result = {"status": "EXECUTED_PASS", "metadataSHA256": actual_receipt["metadataSHA256"],
                        "actualReceiptSHA256": sha(receipt_file), "outputs": len(actual_receipt["outputs"])}
                else:
                    final_paths = [target_binary, receipt_file, transaction / "yaml", transaction / "types", transaction / "umbrella.h"]
                    if executed.returncode <= 0 or any(path.exists() for path in final_paths) or expected_reason.encode() not in executed.stderr:
                        raise RuntimeError("Real transaction did not reject before output publication")
                    transaction_result = {"status": "EXECUTED_PASS", "exitCode": executed.returncode, "publishedOutputs": 0}
            except (RuntimeError, OSError, ValueError, KeyError) as error:
                transaction_result = {"status": "FAILED", "reason": str(error)}
        passed = passed and transaction_result["status"] == "EXECUTED_PASS"
        results.append({"case": name, "status": "EXECUTED_PASS" if passed else "FAILED", "transaction": transaction_result, "nativeStatus": actual.get("status"),
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
