#!/usr/bin/env python3
"""Run affected original ChatCore/producer suites with their canonical native targets.

The proof graph retains complete original production and test sources through
symlinks. It omits unrelated iOS UI targets, never replaces a production engine
or provider, and is not evidence of an application build or a live cache hit.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import importlib.util
import json
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_FILTER = (
    "HanlinPromptCacheTests|HanlinPromptCachePresetTests|HanlinPromptCachePolicyMutationTests|HanlinGoogleCachedContentTests|HanlinOpenTelemetryTracerTests|"
    "HanlinAISDKJSONOutputTests|OpenAIPromptCacheControlTests|HanlinCompactResponsesTests|"
    "testAnthropicRequestBuilder|testOpenAIResponseRouting"
)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--proof", type=Path, required=True)
    parser.add_argument("--scratch", type=Path, required=True)
    parser.add_argument("--producer-tests", type=Path, required=True)
    parser.add_argument("--filter", default=DEFAULT_FILTER)
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("Native Apple validation must run on the authorized Mac.")
    proof = args.proof.resolve()
    proof.mkdir(parents=True, exist_ok=True)
    evidence = proof / "evidence"
    evidence.mkdir(exist_ok=True)
    spec = importlib.util.spec_from_file_location("canonical_graph", ROOT / "Scripts/SDK/generate_manifest.py")
    gen = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gen)
    module = ROOT / "Packages/HanlinPlatform"
    canonical = json.loads(subprocess.check_output(
        ["swift", "package", "--package-path", str(module), "dump-package"], text=True))
    selected = {"HanlinPlatformContracts", "HanlinChatCore", "HanlinChatCoreTests"}
    targets = [t for t in canonical["targets"] if t["name"] in selected]
    assert {t["name"] for t in targets} == selected
    remote = set()
    for target in targets:
        for dep in target["dependencies"]:
            if "product" in dep:
                remote.add(dep["product"][1].lower())
    deps = [gen.source_dependency(d) for d in canonical["dependencies"] if "sourceControl" in d]
    deps = [d for d in deps if d[0] in remote]
    assert {d[0] for d in deps} == remote
    linked = proof / "Packages/HanlinPlatform"
    linked.parent.mkdir(parents=True, exist_ok=True)
    if linked.is_symlink():
        assert linked.resolve() == module.resolve()
    elif linked.exists():
        raise RuntimeError("Proof link destination already contains unrelated data.")
    else:
        linked.symlink_to(module, target_is_directory=True)
    producer_dir = proof / "ProducerTests"
    producer_dir.mkdir(exist_ok=True)
    for filename in ["OpenAIPromptCacheControlTests.swift", "MockTracer.swift"]:
        source = args.producer_tests / filename
        assert source.is_file()
        destination = producer_dir / filename
        shutil.copyfile(source, destination)
        assert sha(source) == sha(destination)
    dependency_text = ",\n        ".join(
        ".package(url: " + gen.quoted(url) + ", " + rule + ")" for _, url, rule in deps)
    target_text = [gen.target(t, "Packages/HanlinPlatform", {}) for t in targets]
    target_text.append(
        '.testTarget(name: "ProducerPromptCacheTests", dependencies: ['
        '.product(name: "SwiftAISDK", package: "swift-ai-sdk"), '
        '.product(name: "AISDKProvider", package: "swift-ai-sdk"), '
        '.product(name: "AISDKProviderUtils", package: "swift-ai-sdk"), '
        '.product(name: "OpenAIProvider", package: "swift-ai-sdk")], path: "ProducerTests")')
    manifest = (
        "// swift-tools-version: 6.2\nimport PackageDescription\n"
        'let package = Package(name: "HanlinCacheNativeProof", platforms: [.macOS(.v26)],\n'
        "    dependencies: [\n        " + dependency_text + "\n    ],\n"
        "    targets: [\n        " + ",\n        ".join(target_text) + "\n    ])\n")
    (proof / "Package.swift").write_text(manifest)
    inputs = {}
    for target in targets:
        path = module / target.get("path",
            ("Tests/" if target["type"] == "test" else "Sources/") + target["name"])
        for file in sorted(path.rglob("*")):
            if file.is_file():
                inputs[str(file.relative_to(ROOT))] = sha(file)
    inputs["Packages/HanlinPlatform/Package.swift"] = sha(module / "Package.swift")
    source_sha = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
    command = ["swift", "test", "--package-path", str(proof), "--scratch-path",
        str(args.scratch), "--jobs", "2", "--filter", args.filter]
    receipt = {
        "status": "RUNNING", "started_at": utc(), "source_sha": source_sha,
        "scope": "Original complete ChatCore/PlatformContracts source closure; affected suites only.",
        "not_claimed": ["full application build", "live provider cache hits", "billing savings"],
        "command": command, "canonical_source_sha256": inputs,
        "producer_test_sha256": {p.name: sha(p) for p in sorted(producer_dir.glob("*.swift"))},
        "swift": subprocess.check_output(["swift", "--version"], text=True).strip()
    }
    receipt_path = evidence / "receipt.json"
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
    log = evidence / "raw.log"
    with log.open("w") as output:
        result = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT)
    unchanged = all(sha(ROOT / name) == expected for name, expected in inputs.items())
    receipt.update(finished_at=utc(), exit_code=result.returncode,
        source_unchanged=unchanged, log_sha256=sha(log),
        status="PASS" if result.returncode == 0 and unchanged else "FAILED")
    matches = re.findall(r"Test run with (\d+) tests.*?passed", log.read_text())
    if matches:
        receipt["swift_testing_process_counts"] = [int(count) for count in matches]
        receipt["swift_testing_passed"] = sum(receipt["swift_testing_process_counts"])
    lock = proof / "Package.resolved"
    if lock.exists():
        receipt["resolved_pins"] = json.loads(lock.read_text())["pins"]
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps({k: v for k, v in receipt.items()
        if k not in ["canonical_source_sha256", "resolved_pins"]}, indent=2))
    print("Evidence:", evidence)
    return result.returncode if unchanged else 2

if __name__ == "__main__":
    sys.exit(main())
