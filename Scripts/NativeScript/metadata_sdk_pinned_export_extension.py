"""One manager-approved AuthenticationServices declaration, under contract3.

The original three-declaration AVFoundation helper stays byte-identical so its
four-way proofs can be reused only after its own complete unchanged-input check.
This module adds a separately bound certificate; it never edits the SDK.
"""
import json
from pathlib import Path
import shlex
import shutil
import subprocess
import uuid

import metadata_sdk_export_evidence as original

HEADER = "System/Library/Frameworks/AuthenticationServices.framework/Headers/ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor.h"
HEADER_SHA = "9c8d78bf8b4dd4dad491e838f0a9a31fd44de840f06f3a98aa3f7575ec999599"
SYMBOL = "ASAuthorizationAllSupportedPublicKeyCredentialDescriptorTransports"
C_BINDING = "_" + SYMBOL
CPP_BINDING = "__Z66ASAuthorizationAllSupportedPublicKeyCredentialDescriptorTransportsv"


def create_evidence(folder, context, sdk, tool):
    from metadata_dual_grammar import objc_arguments
    sha = original.sha
    base_path, base_inputs = original.create_evidence(folder, context, sdk, tool)
    base = json.loads(base_path.read_text(encoding="utf-8"))
    header = sdk / HEADER
    if not header.is_file() or sha(header) != HEADER_SHA:
        raise RuntimeError("Unproven AuthenticationServices declaration source version")
    if len(base["functions"]) != 3 or {item["name"] for item in base["functions"]} != set(original.SYMBOLS):
        raise RuntimeError("Original AVFoundation certificate declaration set drift")
    root = Path(__file__).resolve().parents[2]
    lock = json.loads((root / "Scripts/NativeScript/metadata-frontend-lock.json").read_text(encoding="utf-8"))
    frontend = Path(lock["installedPrefix"])
    apple = Path(subprocess.check_output(["xcrun", "--find", "clang"], text=True).strip())
    arguments = context["arguments"]
    target = base["requestedTarget"]
    relative = Path("authentication-services-" + sha(Path(__file__))[:16])
    reference_root = root / "build/modern-compile-reference/acceptance/nativescript-sdk-probe-dual/textual-public/sdk-export-evidence"
    previous_extended = reference_root / "binding-evidence-extended.json"
    if previous_extended.is_file():
        previous_fields = json.loads(previous_extended.read_text(encoding="utf-8"))
        if previous_fields.get("proofSourceSHA256") == sha(Path(__file__)):
            candidate = Path(previous_fields.get("authenticationEvidenceRelativePath", ""))
            if candidate.is_absolute() or ".." in candidate.parts or candidate.name != "binding-evidence.json":
                raise RuntimeError("Invalid original AuthenticationServices evidence path")
            relative = candidate.parent
    subfolder = folder / relative
    reference = reference_root / relative
    prior_path = reference / "binding-evidence.json"
    additional = None
    if prior_path.is_file():
        previous = json.loads(prior_path.read_text(encoding="utf-8"))
        unchanged = all(previous.get(key) == base.get(key) for key in
            ["contextCompiler", "fullArguments", "sdkRoot", "target", "requestedTarget"])
        unchanged = unchanged and previous.get("proofSourceSHA256") == sha(Path(__file__))
        for item in previous.get("inputFiles", []):
            path = Path(item["path"])
            try:
                observed = reference / path.relative_to(subfolder)
            except ValueError:
                observed = path
            if not observed.is_file() or sha(observed) != item["sha256"]:
                unchanged = False
                break
        if unchanged and previous.get("inputFiles"):
            if not subfolder.exists(): shutil.copytree(reference, subfolder)
            additional = previous
            (subfolder / "proof-reuse.json").write_text(json.dumps({
                "status": "REUSED_VERIFIED_STATIC_BINDING_PROOF", "originalEvidenceSHA256": sha(prior_path),
                "verifiedInputs": len(previous["inputFiles"]), "newCompilerExecution": "NOT_RUN"}, indent=2) + "\n", encoding="utf-8")
    if additional is None:
        # A verified base certificate may have copied an older, now-invalid
        # additional proof. Preserve it and perform a new proof in an owned path.
        if subfolder.exists(): subfolder = folder / (subfolder.name + "-" + uuid.uuid4().hex)
        subfolder.mkdir(parents=True, exist_ok=False)
        inputs = {header.resolve(), Path(__file__).resolve()}
        additional = {key: base[key] for key in
            ["schemaVersion", "status", "contextCompiler", "fullArguments", "sdkRoot", "target", "requestedTarget"]}
        additional["proofSourceSHA256"] = sha(Path(__file__))
        source = subfolder / "reference.m"
        source.write_text('#import <AuthenticationServices/ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor.h>\n'
            + '__typeof__(&' + SYMBOL + ') volatile hanlinSDKBindingReference = &' + SYMBOL + ';\n'
            + 'int main(void) { return hanlinSDKBindingReference == 0; }\n', encoding="utf-8")
        inputs.add(source)
        function = {"name": SYMBOL, "source": str(header.resolve()), "sourceSHA256": HEADER_SHA, "offset": 1819, "proofs": []}

        def run(label, argv):
            completed = subprocess.run([str(x) for x in argv], cwd=tool.parent, capture_output=True, timeout=90)
            stdout, stderr = subfolder / (label + ".stdout"), subfolder / (label + ".stderr")
            stdout.write_bytes(completed.stdout); stderr.write_bytes(completed.stderr)
            inputs.update([stdout, stderr])
            return {"arguments": [str(x) for x in argv], "exitCode": completed.returncode,
                "stdoutPath": str(stdout), "stdoutSHA256": sha(stdout), "stderrPath": str(stderr), "stderrSHA256": sha(stderr)}

        for role, compiler in [("lockedLLVM20", frontend / "bin/clang"), ("installedApple", apple)]:
            inputs.add(compiler.resolve())
            for language in ["objective-c", "objective-c++"]:
                label = role + "-" + language
                flags = list(arguments) if language == "objective-c++" else objc_arguments(arguments, str(sdk / "usr/include/c++/v1"))
                resource = tool.parent / "lib/clang/20" if role == "lockedLLVM20" else Path(subprocess.check_output([str(apple), "-print-resource-dir"], text=True).strip())
                flags.extend(["-resource-dir", str(resource)])
                ast = run(label + "-ast", [compiler, *flags, "-fsyntax-only", "-Xclang", "-ast-dump=json", "-Xclang", "-ast-dump-filter", "-Xclang", SYMBOL, source])
                if ast["exitCode"] != 0: raise RuntimeError("Actual AuthenticationServices AST failed: " + label)
                declaration = json.loads(Path(ast["stdoutPath"]).read_text(encoding="utf-8"))
                expected = C_BINDING if language == "objective-c" else CPP_BINDING
                if declaration.get("kind") != "FunctionDecl" or declaration.get("name") != SYMBOL or declaration.get("mangledName") != expected or \
                    Path(declaration["loc"]["file"]).resolve() != header.resolve() or declaration["loc"].get("offset") != function["offset"]:
                    raise RuntimeError("Actual AuthenticationServices declaration/source/binding drift")
                obj, dependency = subfolder / (label + ".o"), subfolder / (label + ".d")
                compiled = run(label + "-compile", [compiler, *flags, "-MD", "-MF", dependency, "-c", source, "-o", obj])
                if compiled["exitCode"] != 0: raise RuntimeError("Actual AuthenticationServices object failed: " + label)
                inputs.update([obj, dependency])
                for item in shlex.split(dependency.read_text(encoding="utf-8").replace("\\\n", " ").partition(":")[2]):
                    path = Path(item)
                    if not path.is_absolute(): path = tool.parent / path
                    if not path.is_file(): raise RuntimeError("Missing actual AuthenticationServices dependency")
                    inputs.add(path.resolve())
                link = run(label + "-link", [apple, "-isysroot", sdk, "-target", target, obj,
                    "-framework", "AuthenticationServices", "-framework", "Foundation", "-lobjc", "-o", subfolder / (label + ".exe")])
                if link["exitCode"] != (0 if language == "objective-c" else 1):
                    raise RuntimeError("Actual AuthenticationServices C-only binding unproven")
                if language == "objective-c++" and (b"Undefined symbols" not in Path(link["stderrPath"]).read_bytes() or SYMBOL.encode() not in Path(link["stderrPath"]).read_bytes()):
                    raise RuntimeError("AuthenticationServices CPP rejection not attributable to exact symbol")
                function["proofs"].append({"role": role, "language": language, "compilerPath": str(compiler.resolve()),
                    "compilerSHA256": sha(compiler.resolve()), "mangledName": expected, "AST": ast, "compile": compiled, "link": link})
        function.update(CBinding=C_BINDING, CPPBinding=CPP_BINDING)
        additional["functions"] = [function]
        additional["inputFiles"] = [{"path": str(p), "sha256": sha(p)} for p in sorted(inputs)]
        (subfolder / "binding-evidence.json").write_text(json.dumps(additional, indent=2) + "\n", encoding="utf-8")
    if len(additional.get("functions", [])) != 1 or additional["functions"][0].get("name") != SYMBOL or additional["functions"][0].get("sourceSHA256") != HEADER_SHA:
        raise RuntimeError("Pinned AuthenticationServices certificate declaration set drift")
    combined = dict(base)
    combined["proofSourceSHA256"] = sha(Path(__file__))
    combined["originalAVFoundationEvidenceSHA256"] = sha(base_path)
    combined["authenticationEvidenceRelativePath"] = (subfolder / "binding-evidence.json").relative_to(folder).as_posix()
    combined["functions"] = [*base["functions"], *additional["functions"]]
    all_inputs = {Path(item["path"]).resolve(): item["sha256"] for item in [*base["inputFiles"], *additional["inputFiles"]]}
    for path in [base_path, subfolder / "binding-evidence.json", Path(__file__), Path(original.__file__)]:
        all_inputs[path.resolve()] = sha(path)
    if (subfolder / "proof-reuse.json").is_file():
        all_inputs[(subfolder / "proof-reuse.json").resolve()] = sha(subfolder / "proof-reuse.json")
    combined["inputFiles"] = [{"path": str(p), "sha256": digest} for p, digest in sorted(all_inputs.items())]
    evidence = folder / "binding-evidence-extended.json"
    evidence.write_text(json.dumps(combined, indent=2) + "\n", encoding="utf-8")
    return evidence, [evidence, *base_inputs, *all_inputs]
