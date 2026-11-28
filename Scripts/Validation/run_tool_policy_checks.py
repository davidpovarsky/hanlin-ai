#!/usr/bin/env python3
"""Compile a focused, unmodified portable source closure. No simulator or native runtime."""
import argparse
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
from datetime import datetime, timezone

# Windows console encodings may not represent Swift Testing's status glyphs.
# Escaping console output must not turn a completed test run into a wrapper error.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(errors="backslashreplace")

parser = argparse.ArgumentParser()
parser.add_argument("--sdk-repo", required=True, type=pathlib.Path)
parser.add_argument("--build-root", required=True, type=pathlib.Path)
args = parser.parse_args()
repo = pathlib.Path(__file__).resolve().parents[2]
staging = args.build_root.resolve()
staging.mkdir(parents=True, exist_ok=True)
records = []

def copy_source(relative, target):
    src = repo / relative
    dst = staging / target
    if src.is_dir():
        shutil.copytree(src, dst, dirs_exist_ok=True)
        paths = sorted(p for p in src.rglob("*") if p.is_file())
    else:
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        paths = [src]
    for path in paths:
        records.append({"path": path.relative_to(repo).as_posix(), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})

for module in ["JSON", "JSONRegexRuntime", "JSONSchema"]:
    copy_source("Packages/HanlinAgentSDK/Vendor/Swift-JSON/Sources/" + module, "Sources/" + ("HanlinExactJSONSchema" if module == "JSONSchema" else module))
copy_source("Packages/HanlinPlatform/Sources/HanlinPlatformContracts", "Sources/HanlinPlatformContracts")
copy_source("Packages/HanlinAgentSDK/Sources/HanlinAgentCore/HanlinHostSchemaValidation.swift", "Sources/HanlinAgentCore/HanlinHostSchemaValidation.swift")
copy_source("AI_HLY/Downstream/ChatCore/HanlinToolApprovalStore.swift", "Sources/AI_Hanlin/HanlinToolApprovalStore.swift")
for file, target in [
    ("Packages/HanlinAgentSDK/Tests/HanlinAgentCoreTests/HostInputIntegrityRegressionTests.swift", "Tests/ToolPolicyChecks/HostInputIntegrityRegressionTests.swift"),
    ("Packages/HanlinPlatform/Tests/HanlinPlatformContractsTests/ToolApprovalAndPresentationTests.swift", "Tests/ToolPolicyChecks/ToolApprovalAndPresentationTests.swift"),
    ("AI_HLYTests/HanlinToolApprovalStoreTests.swift", "Tests/ToolPolicyChecks/HanlinToolApprovalStoreTests.swift"),
]:
    copy_source(file, target)
sdk_revision = "e7bf34111e603ca977becd007dd4e5bb109af857"
sdk_path = "Sources/AISDKProvider/JSONValue/JSONValue.swift"
sdk_bytes = subprocess.check_output(["git", "-C", str(args.sdk_repo), "show", sdk_revision + ":" + sdk_path])
sdk_destination = staging / "Sources/AISDKProvider/JSONValue.swift"
sdk_destination.parent.mkdir(parents=True, exist_ok=True)
if not sdk_destination.exists() or sdk_destination.read_bytes() != sdk_bytes:
    sdk_destination.write_bytes(sdk_bytes)
records.append({"repository": "davidpovarsky/swift-ai-sdk", "revision": sdk_revision, "path": sdk_path, "sha256": hashlib.sha256(sdk_bytes).hexdigest()})
manifest = '''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "HanlinToolPolicyChecks", targets: [
    .target(name: "JSON"),
    .target(name: "JSONRegexRuntime", dependencies: ["JSON"]),
    .target(name: "HanlinExactJSONSchema", dependencies: ["JSON", "JSONRegexRuntime"], resources: [.copy("Resources/Draft2020-12")]),
    .target(name: "HanlinPlatformContracts", resources: [.process("Resources")]),
    .target(name: "AISDKProvider"),
    .target(name: "HanlinAgentCore", dependencies: ["JSON", "HanlinExactJSONSchema", "HanlinPlatformContracts", "AISDKProvider"]),
    .target(name: "AI_Hanlin"),
    .testTarget(name: "ToolPolicyChecks", dependencies: ["HanlinAgentCore", "HanlinPlatformContracts", "AI_Hanlin"])
], swiftLanguageModes: [.v6])
'''
manifest_path = staging / "Package.swift"
if not manifest_path.exists() or manifest_path.read_text(encoding="utf-8") != manifest:
    manifest_path.write_text(manifest, encoding="utf-8", newline="\n")
# Production deliberately resolves only its fixed resource bundle identity. This
# isolated package has a different name, so use its existing DEBUG lookup hook.
# The unchanged loader still verifies every pinned resource size and SHA-256.
resource_parent = staging / "ProductionResources"
resource_bundle = resource_parent / "HanlinAgentSDK_HanlinExactJSONSchema.resources"
shutil.copytree(repo / "Packages/HanlinAgentSDK/Vendor/Swift-JSON/Sources/JSONSchema/Resources/Draft2020-12",
                resource_bundle / "Draft2020-12", dirs_exist_ok=True)
environment = os.environ.copy()
environment["PACKAGE_RESOURCE_BUNDLE_PATH"] = str(resource_parent)
command = ["swift", "test", "--package-path", str(staging), "-j", "2"]
started = datetime.now(timezone.utc).isoformat()
result = subprocess.run(command, capture_output=True, env=environment)
output = result.stdout.decode("utf-8", errors="replace") + result.stderr.decode("utf-8", errors="replace")
(staging / "result.log").write_text(output, encoding="utf-8", newline="\n")
evidence = {
    "schema_version": 1,
    "suite": "exact tool-input preservation, manifest policy/presentation, durable scoped consent",
    "status": "passed" if result.returncode == 0 else "failed",
    "started_at": started,
    "finished_at": datetime.now(timezone.utc).isoformat(),
    "exit_code": result.returncode,
    "command": command,
    "toolchain": subprocess.check_output(["swift", "--version"]).decode().strip(),
    "environment_overrides": {"PACKAGE_RESOURCE_BUNDLE_PATH": str(resource_parent)},
    "resource_note": "Fixed production bundle identity; unmodified loader enforces all nine pinned sizes and SHA-256s.",
    "source_closure": records,
    "limitations": [
        "Windows Swift portable source closure only; UIKit/SwiftUI, whole app host wiring and Apple compilation are not executed.",
        "No simulator or physical device; no native runtime rebuild.",
        "MCP provider execution, Apple Maps networking, account credentials, and OS permission dialogs are not invoked."
    ]
}
destination = repo / "docs/chat-ui-handoff/2026-11-22-followup-evidence/tool-policy-domain-result.json"
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
print("\n".join(output.splitlines()[-65:]))
print("Evidence: " + str(destination))
sys.exit(result.returncode)
