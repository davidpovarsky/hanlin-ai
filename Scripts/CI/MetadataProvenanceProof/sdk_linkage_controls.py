#!/usr/bin/env python3
"""Focused actual SDK compiler/export/link evidence; never metadata acceptance."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
REFERENCE = ROOT / "build/modern-compile-reference"
OUTPUT = ROOT / "build/acceptance/metadata-sdk-linkage-controls"
SYMBOL = "AVCaptureTimecodeCreateMetadataSampleBufferAssociatedWithPresentationTimeStamp"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(symbol=SYMBOL, framework="AVFoundation", header="AVCaptureTimecodeGenerator.h", original_run=43753113119):
    OUTPUT.mkdir(parents=True, exist_ok=False)
    source = OUTPUT / "reference.m"
    source.write_text('#import <' + framework + '/' + header + '>\n'
        + '__typeof__(&' + symbol + ') volatile hanlinSDKLinkageReference = &' + symbol + ';\n'
        + 'int main(void) { return hanlinSDKLinkageReference == 0; }\n')
    baseline = REFERENCE / "acceptance/nativescript-sdk-probe-dual/textual-public"
    context_path = baseline / "native-compiler-context.json"
    context = json.loads(context_path.read_text())
    request = json.loads((baseline / "dual-request.json").read_text())
    arguments = context["arguments"]
    sdk = Path(arguments[arguments.index("-isysroot") + 1])
    target = arguments[arguments.index("-target") + 1]
    actual_sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip()
    if str(sdk) != actual_sdk or not target.startswith("arm64-apple-ios") or not target.endswith("-simulator"):
        raise RuntimeError("Original selected SDK/target drift")
    apple = Path(subprocess.check_output(["xcrun", "--find", "clang"], text=True).strip())
    frontend = Path(json.loads((ROOT / "Scripts/NativeScript/metadata-frontend-lock.json").read_text())["installedPrefix"])
    cwd = ROOT / "build/nativescript-modern-metadata-tool/bin"
    if not (cwd / "objc-metadata-generator").is_file() or sha(cwd / "objc-metadata-generator") != context["generatorSHA256"]:
        raise RuntimeError("Verified original generator/resource image unavailable")
    normalized = []
    index = 0
    while index < len(arguments):
        item = arguments[index]
        if item in ["-x", "-std"]:
            index += 2
        elif item.startswith("-std="):
            index += 1
        else:
            normalized.append(item)
            index += 1
    result = {"schemaVersion": 1, "status": "READ_ONLY_AUDIT", "originalRun": original_run,
        "symbol": symbol, "framework": framework,
        "originalContextSHA256": sha(context_path), "sourceSHA256": sha(source), "sdk": str(sdk), "target": target,
        "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(), "cases": [], "files": [],
        "boundary": "Actual compiler objects and focused SDK link only. No metadata merge, executable invocation, app, VM or device pass."}
    for raw in (baseline / "stderr.log").read_text().splitlines():
        for label in ["Actual CPP ABI=", "Actual ObjC ABI="]:
            if raw.startswith(label):
                result[label[:-1]] = json.loads(raw[len(label):])
    def run(label, argv):
        completed = subprocess.run([str(v) for v in argv], cwd=cwd, capture_output=True, timeout=90)
        (OUTPUT / (label + ".stdout")).write_bytes(completed.stdout)
        (OUTPUT / (label + ".stderr")).write_bytes(completed.stderr)
        return {"argv": [str(v) for v in argv], "exitCode": completed.returncode,
            "stdout": label + ".stdout", "stderr": label + ".stderr"}
    for compiler_name, compiler in [("lockedLLVM20", frontend / "bin/clang"), ("installedApple", apple)]:
        for language, standard in [("objective-c", "gnu17"), ("objective-c++", "gnu++20")]:
            label = compiler_name + "-" + language
            flags = [*normalized, "-x", language, "-std=" + standard]
            if language == "objective-c":
                flags.extend(["-isystem", request["standardLibraryDirectory"]])
            # Explicitly preserve the generator's copied resource headers for
            # the locked frontend; Apple uses its own installed resource root.
            resource = cwd / "lib/clang/20" if compiler_name == "lockedLLVM20" else Path(subprocess.check_output([str(apple), "-print-resource-dir"], text=True).strip())
            flags.extend(["-resource-dir", str(resource)])
            case = {"compiler": compiler_name, "compilerPath": str(compiler), "compilerSHA256": sha(compiler),
                "version": subprocess.check_output([str(compiler), "--version"], text=True).strip(),
                "language": language, "resourceDirectory": str(resource),
                "rootDifference": "Focused actual SDK header plus address reference; no rewritten declarations or macros",
                "compilerDifference": "Installed Apple compiler/resources" if compiler_name == "installedApple" else "Original locked LLVM20 generator resource headers"}
            case["preprocess"] = run(label + "-preprocess", [compiler, *flags, "-E", "-dD", source])
            case["declaration"] = run(label + "-ast", [compiler, *flags, "-fsyntax-only", "-Xclang", "-ast-dump=json", "-Xclang", "-ast-dump-filter", "-Xclang", symbol, source])
            obj = OUTPUT / (label + ".o")
            case["compile"] = run(label + "-compile", [compiler, *flags, "-c", source, "-o", obj])
            if case["compile"]["exitCode"] == 0:
                case["undefinedSymbols"] = run(label + "-symbols", ["xcrun", "nm", "-u", obj])
                case["link"] = run(label + "-link", [apple, "-isysroot", sdk, "-target", target, obj,
                    "-framework", framework, "-framework", "Foundation", "-framework", "CoreMedia", "-lobjc", "-o", OUTPUT / (label + ".exe")])
            result["cases"].append(case)
    framework_root = "System/Library/Frameworks/" + framework + ".framework/"
    relatives = [framework_root + "Headers/" + header, framework_root + framework + ".tbd"]
    if framework == "AVFoundation": relatives.append(framework_root + "Headers/AVBase.h")
    for relative in relatives:
        path = sdk / relative
        output = OUTPUT / "sdk" / relative
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(path.read_bytes())
        result["files"].append({"physicalPath": str(path.resolve()), "path": str(path), "sha256": sha(path), "retained": output.relative_to(OUTPUT).as_posix()})
        if path.suffix == ".tbd":
            case = run("export-documents", ["/usr/bin/ruby", "-ryaml", "-rjson", "-e", "puts JSON.generate(YAML.load_stream(File.read(ARGV[0])))", path])
            result["exportParse"] = case
            if case["exitCode"] == 0:
                docs = json.loads((OUTPUT / case["stdout"]).read_text())
                expected = {"_" + result[key]["externalBinding"]["clangSymbolBeforeTargetPrefix"] for key in ["Actual CPP ABI", "Actual ObjC ABI"]}
                matches = []
                for document in docs:
                    for export in document.get("exports", []):
                        symbols = sorted(expected.intersection(export.get("symbols", [])))
                        if symbols:
                            matches.append({"installName": document.get("install-name"), "documentTargets": document.get("targets"),
                                "exportTargets": export.get("targets"), "symbols": symbols})
                result["targetScopedExportMatches"] = matches
    (OUTPUT / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    manifest = [{"path": p.relative_to(OUTPUT).as_posix(), "sha256": sha(p), "bytes": p.stat().st_size} for p in sorted(OUTPUT.rglob("*")) if p.is_file()]
    (OUTPUT / "artifact-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"status": result["status"], "cases": [{"compiler": c["compiler"], "language": c["language"], "compile": c["compile"]["exitCode"], "link": c.get("link", {}).get("exitCode")} for c in result["cases"]], "exports": result.get("targetScopedExportMatches")}))
    return 0 if all(c["compile"]["exitCode"] == 0 for c in result["cases"]) and result.get("exportParse", {}).get("exitCode") == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main(symbol="ASAuthorizationAllSupportedPublicKeyCredentialDescriptorTransports",
        framework="AuthenticationServices", header="ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor.h",
        original_run=43764936118) if "--authentication-services" in sys.argv else main())
