"""Actual compiler/link evidence for the narrowly pinned SDK linkage defect.

No SDK edits, declarations, engine execution or metadata acceptance. This
candidate preflight runs only for the explicitly requested SDK authority slice.
"""
import hashlib
import json
from pathlib import Path
import shlex
import shutil
import subprocess

HEADER = "System/Library/Frameworks/AVFoundation.framework/Headers/AVCaptureTimecodeGenerator.h"
HEADER_SHA = "bb74610a80523338eb765c952fd9a1205f56d4a59cec02dfd9326d9dc26dbc22"
SYMBOLS = ["AVCaptureTimecodeCreateMetadataSampleBufferAssociatedWithPresentationTimeStamp",
           "AVCaptureTimecodeCreateMetadataSampleBufferForDuration", "AVCaptureTimecodeAdvancedByFrames"]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def create_evidence(folder, context, sdk, tool):
    """Emit fresh four-compiler/grammar proofs for each pinned physical declaration."""
    from metadata_dual_grammar import objc_arguments
    root = Path(__file__).resolve().parents[2]
    lock = json.loads((root / "Scripts/NativeScript/metadata-frontend-lock.json").read_text(encoding="utf-8"))
    frontend = Path(lock["installedPrefix"])
    for relative, digest in lock["files"].items():
        if sha(frontend / relative) != digest:
            raise RuntimeError("SDK binding evidence frontend drift")
    header = sdk / HEADER
    if not header.is_file() or sha(header) != HEADER_SHA:
        raise RuntimeError("Unproven SDK binding defect source version")
    apple = Path(subprocess.check_output(["xcrun", "--find", "clang"], text=True).strip())
    if str(sdk) != subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip():
        raise RuntimeError("SDK binding proof target SDK drift")
    arguments = context["arguments"]
    target = arguments[arguments.index("-target") + 1]
    if not target.startswith("arm64-apple-ios") or not target.endswith("-simulator"):
        raise RuntimeError("SDK binding proof target not yet supported")
    actual_target = subprocess.check_output([str(frontend / "bin/clang"), "-target", target, "-print-target-triple"], text=True).strip()
    reference = root / "build/modern-compile-reference/acceptance/nativescript-sdk-probe-dual/textual-public/sdk-export-evidence"
    reference_evidence = reference / "binding-evidence.json"
    if reference_evidence.is_file():
        previous = json.loads(reference_evidence.read_text(encoding="utf-8"))
        unchanged = previous.get("proofSourceSHA256") == sha(Path(__file__)) and previous.get("fullArguments") == arguments and previous.get("contextCompiler") == context["compiler"] and previous.get("target") == actual_target and previous.get("requestedTarget") == target and previous.get("sdkRoot") == str(sdk.resolve())
        if unchanged:
            for item in previous.get("inputFiles", []):
                path = Path(item["path"])
                try:
                    relative = path.relative_to(folder)
                    observed = reference / relative
                except ValueError:
                    observed = path
                if not observed.is_file() or sha(observed) != item["sha256"]:
                    unchanged = False
                    break
        if unchanged and previous.get("inputFiles"):
            shutil.copytree(reference, folder)
            reuse = folder / "proof-reuse.json"
            reuse.write_text(json.dumps({"status": "REUSED_VERIFIED_STATIC_BINDING_PROOF", "originalEvidenceSHA256": sha(reference_evidence),
                "verifiedInputs": len(previous["inputFiles"]), "boundary": "No new compiler/link controls executed; exact fixture/helper/argv/compiler/resource/dependency inputs verified unchanged."}, indent=2) + "\n", encoding="utf-8")
            return folder / "binding-evidence.json", [folder / "binding-evidence.json", reuse, *[Path(item["path"]) for item in previous["inputFiles"]]]
    folder.mkdir(parents=True, exist_ok=False)
    inputs = {header.resolve()}
    result = {"schemaVersion": 1, "status": "STATIC_BINDING_PROOF", "contextCompiler": context["compiler"], "proofSourceSHA256": sha(Path(__file__)),
        "fullArguments": arguments, "sdkRoot": str(sdk.resolve()), "target": actual_target, "requestedTarget": target, "functions": []}
    def run(label, argv):
        completed = subprocess.run([str(x) for x in argv], cwd=tool.parent, capture_output=True, timeout=90)
        stdout = folder / (label + ".stdout")
        stderr = folder / (label + ".stderr")
        stdout.write_bytes(completed.stdout); stderr.write_bytes(completed.stderr)
        inputs.update([stdout, stderr])
        return {"arguments": [str(x) for x in argv], "exitCode": completed.returncode,
            "stdoutPath": str(stdout), "stdoutSHA256": sha(stdout), "stderrPath": str(stderr), "stderrSHA256": sha(stderr)}
    for number, symbol in enumerate(SYMBOLS):
        source = folder / (str(number) + ".m")
        source.write_text('#import <AVFoundation/AVCaptureTimecodeGenerator.h>\n'
            + '__typeof__(&' + symbol + ') volatile hanlinSDKBindingReference = &' + symbol + ';\n'
            + 'int main(void) { return hanlinSDKBindingReference == 0; }\n', encoding="utf-8")
        inputs.add(source)
        function = {"name": symbol, "source": str(header.resolve()), "sourceSHA256": HEADER_SHA, "proofs": []}
        symbols = {}
        for role, compiler in [("lockedLLVM20", frontend / "bin/clang"), ("installedApple", apple)]:
            inputs.add(compiler.resolve())
            for language in ["objective-c", "objective-c++"]:
                label = str(number) + "-" + role + "-" + language
                flags = list(arguments) if language == "objective-c++" else objc_arguments(arguments, str(sdk / "usr/include/c++/v1"))
                resource = tool.parent / "lib/clang/20" if role == "lockedLLVM20" else Path(subprocess.check_output([str(apple), "-print-resource-dir"], text=True).strip())
                flags.extend(["-resource-dir", str(resource)])
                ast = run(label + "-ast", [compiler, *flags, "-fsyntax-only", "-Xclang", "-ast-dump=json", "-Xclang", "-ast-dump-filter", "-Xclang", symbol, source])
                if ast["exitCode"] != 0:
                    raise RuntimeError("Actual SDK binding AST failed: " + label)
                declaration = json.loads(Path(ast["stdoutPath"]).read_text())
                if declaration.get("kind") != "FunctionDecl" or declaration.get("name") != symbol:
                    raise RuntimeError("Unproven actual SDK binding declaration")
                location = declaration["loc"]
                if Path(location["file"]).resolve() != header.resolve():
                    raise RuntimeError("SDK binding declaration source owner changed")
                if "offset" in function and function["offset"] != location["offset"]:
                    raise RuntimeError("SDK binding declaration physical location differs")
                function["offset"] = location["offset"]
                mangled = declaration["mangledName"]
                if language in symbols and symbols[language] != mangled:
                    raise RuntimeError("Installed and locked SDK binding compilers disagree")
                symbols[language] = mangled
                obj = folder / (label + ".o"); dependency = folder / (label + ".d")
                compile_result = run(label + "-compile", [compiler, *flags, "-MD", "-MF", dependency, "-c", source, "-o", obj])
                if compile_result["exitCode"] != 0:
                    raise RuntimeError("SDK binding object compilation failed: " + label)
                inputs.update([obj, dependency])
                for value in shlex.split(dependency.read_text().replace("\\\n", " ").partition(":")[2]):
                    path = Path(value)
                    if not path.is_absolute(): path = tool.parent / path
                    if not path.is_file(): raise RuntimeError("Missing actual SDK binding compile dependency")
                    inputs.add(path.resolve())
                link = run(label + "-link", [apple, "-isysroot", sdk, "-target", target, obj, "-framework", "AVFoundation",
                    "-framework", "Foundation", "-framework", "CoreMedia", "-lobjc", "-o", folder / (label + ".exe")])
                if link["exitCode"] != (0 if language == "objective-c" else 1):
                    raise RuntimeError("Unproven unique SDK C binding: " + label)
                if language == "objective-c++" and (b"Undefined symbols" not in Path(link["stderrPath"]).read_bytes() or symbol.encode() not in Path(link["stderrPath"]).read_bytes()):
                    raise RuntimeError("SDK C++ link failure not attributable to the actual symbol")
                function["proofs"].append({"role": role, "language": language, "compilerPath": str(compiler.resolve()),
                    "compilerSHA256": sha(compiler.resolve()), "mangledName": mangled, "AST": ast,
                    "compile": compile_result, "link": link})
        function["CBinding"] = symbols["objective-c"]
        function["CPPBinding"] = symbols["objective-c++"]
        result["functions"].append(function)
    result["inputFiles"] = [{"path": str(path), "sha256": sha(path)} for path in sorted(inputs)]
    evidence = folder / "binding-evidence.json"
    evidence.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return evidence, [evidence, *sorted(inputs)]
