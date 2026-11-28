#!/usr/bin/env python3
"""Verify the actual shared module and the presentation path predicate across a Swift module boundary."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[4]
OUTPUT = Path(__file__).resolve().parent
BASE = "ee3b0ede43fcb4aac02def04d469eae542ba035b"
POLICY = "Packages/HanlinPlatform/Sources/HanlinScriptCompiler/HanlinArchivePolicy.swift"
WIDGET = "Packages/HanlinPlatform/Sources/HanlinWidgetCompiler/HanlinWidgetCompiler.swift"
SHARED = "Packages/HanlinPlatform/Sources/HanlinPlatformContracts/HanlinPackagePath.swift"
TESTS = "Packages/HanlinPlatform/Tests/HanlinScriptCompilerTests/HanlinArchivePolicyTests.swift"

def before(path):
    return subprocess.check_output(["git", "show", f"{BASE}:{path}"], cwd=ROOT, text=True)

def body(source, name):
    start = source.index("{", source.index(f"func {name}("))
    depth = 1
    for index in range(start + 1, len(source)):
        depth += (source[index] == "{") - (source[index] == "}")
        if depth == 0:
            return source[start + 1:index]
    raise AssertionError(f"Missing function end: {name}")

def sha(data):
    return hashlib.sha256(data).hexdigest()

receipt = {
    "schemaVersion": 1,
    "baseSourceSHA": BASE,
    "sourceCheckpointSHA": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
    "status": "RUNNING",
    "scope": "Build the complete actual Foundation-only PlatformContracts target with its original SwiftPM target declaration and resources, then typecheck the old and new production path predicate in a separate consumer module; this is not full WidgetCompiler or Apple compilation.",
    "priorProbe": {"status": "FAILED_PROBE_SETUP", "receipt": "initial-direct-swiftc/module-boundary.json", "reason": "Direct swiftc compilation omitted SwiftPM's generated Bundle.module accessor; production was unchanged."},
    "checks": {},
    "commands": [],
    "notRun": ["Full HanlinWidgetCompiler target with Apple dependencies", "Apple SDK compilation", "native gate38"]
}
def save():
    (OUTPUT / "module-boundary.json").write_text(json.dumps(receipt, indent=2) + "\n")

def run(argv, log, timeout=120):
    started = time.monotonic()
    result = subprocess.run(argv, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    raw = result.stdout + result.stderr
    (OUTPUT / log).write_text(raw)
    receipt["commands"].append({"argv": argv, "exit": result.returncode,
        "seconds": time.monotonic() - started, "log": log, "logSHA256": sha(raw.encode())})
    save()
    return result.returncode, raw

try:
    swiftc = shutil.which("swiftc")
    assert swiftc, "Installed Swift compiler is required."
    receipt["toolchain"] = subprocess.check_output([swiftc, "--version"], text=True).strip()
    old_policy = before(POLICY)
    new_shared = (ROOT / SHARED).read_text()
    for name in ["normalizedRelativePath", "hasDrivePrefix"]:
        original_body = body(old_policy, name)
        moved_body = body(new_shared, name)
        assert original_body == moved_body, f"Changed original body: {name}"
        receipt["checks"][name + "Body"] = {"status": "BYTE_IDENTICAL",
            "beforeSHA256": sha(original_body.encode()), "afterSHA256": sha(moved_body.encode())}
    for path in [TESTS, "Package.swift", "Packages/HanlinPlatform/Package.swift"]:
        old = before(path).encode()
        new = (ROOT / path).read_bytes()
        assert old == new, f"Unexpected source change: {path}"
        receipt["checks"][path] = {"status": "UNCHANGED", "sha256": sha(new)}
    sources = sorted((ROOT / "Packages/HanlinPlatform/Sources/HanlinPlatformContracts").glob("*.swift"))
    assert sources and ROOT / SHARED in sources
    receipt["moduleSources"] = [{"path": str(path.relative_to(ROOT)), "sha256": sha(path.read_bytes())} for path in sources]
    with tempfile.TemporaryDirectory(prefix="hanlin-widget-path-module-") as temporary:
        module_root = Path(temporary)
        source_directory = Path("Packages/HanlinPlatform/Sources/HanlinPlatformContracts")
        shutil.copytree(ROOT / source_directory, module_root / source_directory)
        manifest = (ROOT / "Package.swift").read_text()
        marker = '        .target(\n            name: "HanlinPlatformContracts",'
        start = manifest.index(marker)
        end = manifest.index("        ),", start) + len("        ),")
        target_declaration = manifest[start:end]
        probe_manifest = (manifest.splitlines()[0] + "\nimport PackageDescription\n" +
            'let package = Package(name: "WidgetPathBoundaryProbe", targets: [\n' +
            target_declaration + "\n])\n")
        (module_root / "Package.swift").write_text(probe_manifest)
        (OUTPUT / "probe-Package.swift").write_text(probe_manifest)
        receipt["targetDeclaration"] = {"origin": "Package.swift", "verbatim": True,
            "sha256": sha(target_declaration.encode())}
        receipt["resources"] = [{"path": str(path.relative_to(ROOT)), "sha256": sha(path.read_bytes())}
            for path in sorted((ROOT / source_directory / "Resources").rglob("*")) if path.is_file()]
        swift = shutil.which("swift")
        assert swift, "Installed SwiftPM is required."
        code, _ = run([swift, "build", "--package-path", str(module_root),
            "--scratch-path", str(module_root / ".build"), "--target", "HanlinPlatformContracts"],
            "module-compile.log")
        assert code == 0, "Actual PlatformContracts target failed to build."
        modules = [path for path in (module_root / ".build").rglob("HanlinPlatformContracts.swiftmodule")
            if path.is_file() and path.parent.name == "Modules"]
        assert len(modules) == 1, "Expected one compiled PlatformContracts module."
        module = modules[0]
        receipt["compiledModuleSHA256"] = sha(module.read_bytes())
        for state, production in [("before", before(WIDGET)), ("after", (ROOT / WIDGET).read_text())]:
            predicate = next(line.strip().rstrip(",") for line in production.splitlines()
                if "normalizedRelativePath(declaration.sourcePath)" in line)
            consumer = OUTPUT / f"{state}-consumer.swift"
            consumer.write_text("import HanlinPlatformContracts\n\n"
                "public func presentationPathIsNormalized(_ sourcePath: String) -> Bool {\n    " +
                predicate.replace("declaration.sourcePath", "sourcePath") + "\n}\n")
            code, raw = run([swiftc, "-typecheck", "-swift-version", "6",
                "-module-name", "HanlinWidgetCompiler", "-I", str(module.parent), str(consumer)],
                f"{state}-consumer-typecheck.log")
            if state == "before":
                assert code != 0 and "cannot find 'HanlinArchivePolicy' in scope" in raw
                status = "EXPECTED_UNDEFINED_SYMBOL_REPRODUCED"
            else:
                assert code == 0, "New shared public predicate was not visible from the external consumer."
                status = "EXECUTED_PASS"
            receipt["checks"][state + "Consumer"] = {"status": status, "exit": code,
                "source": consumer.name, "sourceSHA256": sha(consumer.read_bytes()),
                "productionPredicate": predicate}
    receipt["status"] = "EXECUTED_PASS"
finally:
    if receipt["status"] == "RUNNING":
        receipt["status"] = "FAILED"
    save()
print(json.dumps(receipt, indent=2))
