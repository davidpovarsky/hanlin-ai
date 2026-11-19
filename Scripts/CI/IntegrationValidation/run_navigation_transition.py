#!/usr/bin/env python3
"""Compile the complete original contract modules and dispatcher; no host/UI/model claim."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument("--artifacts-dir", type=Path, required=True)
args = parser.parse_args()
output = args.artifacts_dir.resolve()
output.mkdir(parents=True, exist_ok=True)
if any(output.iterdir()):
    raise SystemExit("Preserve prior evidence; select an empty artifacts directory")
package = output / "package"
package.mkdir()
inputs = {}
build_package = ROOT / "build/nav-package"
build_package.mkdir(parents=True, exist_ok=True)
def original(path, target):
    raw = (ROOT / path).read_bytes()
    destination = package / target
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(raw)
    compiler_input = build_package / target
    compiler_input.parent.mkdir(parents=True, exist_ok=True)
    if not compiler_input.exists() or compiler_input.read_bytes() != raw:
        compiler_input.write_bytes(raw)
    inputs[path] = {"sha256": hashlib.sha256(raw).hexdigest(), "bytes": len(raw), "build_path": target}
for module, prefix in [
    ("HanlinPlatformContracts", "Packages/HanlinPlatform/Sources/HanlinPlatformContracts"),
    ("HanlinHostContracts", "Packages/HanlinAgentSDK/Sources/HanlinHostContracts"),
]:
    for path in sorted((ROOT / prefix).rglob("*")):
        if path.is_file() and (path.suffix == ".swift" or "Resources" in path.relative_to(ROOT / prefix).parts):
            original(path.relative_to(ROOT).as_posix(), "Sources/" + module + "/" + path.relative_to(ROOT / prefix).as_posix())
original("Packages/HanlinAgentSDK/Sources/HanlinAgentCore/HanlinHostDispatcher.swift",
         "Sources/HanlinAgentCore/HanlinHostDispatcher.swift")
test_path = "Packages/HanlinAgentSDK/Tests/HanlinAgentCoreTests/NavigationTransitionTests.swift"
original(test_path, "Tests/HanlinAgentCoreTests/NavigationTransitionTests.swift")
manifest = """// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "HanlinNavigationTransitionProof",
    platforms: [.iOS("27.0"), .macOS(.v26)],
    targets: [
        .target(name: "HanlinPlatformContracts", resources: [.process("Resources")]),
        .target(name: "HanlinHostContracts", dependencies: ["HanlinPlatformContracts"]),
        .target(name: "HanlinAgentCore", dependencies: ["HanlinPlatformContracts", "HanlinHostContracts"]),
        .testTarget(name: "HanlinAgentCoreTests", dependencies: ["HanlinAgentCore", "HanlinHostContracts", "HanlinPlatformContracts"])
    ], swiftLanguageModes: [.v6])
"""
(package / "Package.swift").write_text(manifest, encoding="utf-8", newline="\n")
compiler_manifest = build_package / "Package.swift"
if not compiler_manifest.exists() or compiler_manifest.read_text(encoding="utf-8") != manifest:
    compiler_manifest.write_text(manifest, encoding="utf-8", newline="\n")
expected_inputs = {record["build_path"] for record in inputs.values()}
actual_inputs = {p.relative_to(build_package).as_posix() for folder in ["Sources", "Tests"]
                 for p in (build_package / folder).rglob("*") if p.is_file()}
assert actual_inputs == expected_inputs, "Unexpected compiler input; preserve and inspect the owned build package"

(output / "inputs.json").write_text(json.dumps(inputs, indent=2) + "\n", encoding="utf-8")
toolchain = subprocess.check_output(["swift", "--version"], text=True, encoding="utf-8")
(output / "toolchain.txt").write_text(toolchain, encoding="utf-8")
command = ["swift", "test", "--scratch-path", str(ROOT / "build/nav"),
           "-j", "1", "-Xswiftc", "-strict-concurrency=complete",
           "--filter", "NavigationTransitionTests", "--xunit-output", str(output / "tests.xml")]
with (output / "swift-test.log").open("w", encoding="utf-8") as log:
    process = subprocess.Popen(command, cwd=build_package, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT)
    try:
        code = process.wait(timeout=300)
    except subprocess.TimeoutExpired:
        if os.name == "nt":
            subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True)
        else:
            process.kill()
        process.wait()
        code = 124
expected = sorted(re.findall(r"@Test func (\w+)\(", (ROOT / test_path).read_text(encoding="utf-8")))
cases = []
try:
    # SwiftPM 6.3 emits Swift Testing cases in a separate sibling XML file.
    xml_path = output / "tests-swift-testing.xml"
    if not xml_path.exists():
        xml_path = output / "tests.xml"
    for item in ET.parse(xml_path).getroot().iter("testcase"):
        cases.append({"name": item.attrib["name"], "class": item.attrib.get("classname"),
                      "status": "FAILED" if item.find("failure") is not None or item.find("error") is not None
                      else "SKIPPED" if item.find("skipped") is not None else "EXECUTED_PASS"})
except (OSError, ET.ParseError) as error:
    cases = []
actual = sorted(c["name"].split("(")[0] for c in cases)
passed = code == 0 and actual == expected and bool(cases) and all(c["status"] == "EXECUTED_PASS" for c in cases)
log_text = (output / "swift-test.log").read_text(encoding="utf-8", errors="replace")
report = {"observed_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
          "source_head": subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip(),
          "status": "EXECUTED_PASS_PORTABLE_CONTRACT" if passed else "FAIL", "process_exit": code,
          "toolchain": toolchain.strip(), "command": command, "input_files": len(inputs),
          "expected": expected, "cases": cases, "warnings": log_text.count("warning:"),
          "boundary": "Complete original Platform/Host contracts and whole dispatcher, with an explicit host double. AgentSession/engine/provider and native application are not executed here.",
          "native_passes": 0, "full_sdk_graph": "NOT_RUN"}
(output / "RESULT.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print(json.dumps(report))
if not passed:
    print(log_text[-20000:])
raise SystemExit(0 if passed else 1)
