#!/usr/bin/env python3
"""Run focused production action/broker and Foundation codec checks.

Uses the complete original PlatformContracts source target, two actual portable
MiniAppCore sources and existing Core tests. Only the native-free JSON methods
are projected verbatim from the NativeScript adapter/AppIntent into Foundation
containers. This does not execute a JS engine, AppIntents, or the Darwin store.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--core-only", action="store_true",
                    help="Check only the two affected existing portable Core cases.")
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)

def source(path: str) -> bytes:
    local = ROOT / path
    return local.read_bytes() if local.is_file() else subprocess.check_output(
        ["git", "show", f"HEAD:{path}"], cwd=ROOT)

def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

inputs = {}
projections = {}
def capture(path: str) -> bytes:
    data = source(path)
    inputs[path] = sha(data)
    return data

def between(path: str, start: str, end: str) -> str:
    text = capture(path).decode()
    assert text.count(start) == 1 and text.count(end) == 1, path
    body = text[text.index(start):text.index(end, text.index(start))]
    projections[path] = {"start": start, "end": end, "sha256": sha(body.encode())}
    return body

with tempfile.TemporaryDirectory(prefix="hanlin-action-capacity-",
                                 dir=os.environ.get("HANLIN_AUTHORING_TMP")) as temporary:
    package = Path(temporary)
    def write(path: str, data):
        file = package / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_bytes(data if isinstance(data, bytes) else data.encode())

    prefix = "Packages/HanlinPlatform/Sources/HanlinPlatformContracts/"
    tracked = subprocess.check_output(
        ["git", "ls-files", "--", prefix], cwd=ROOT, text=True).splitlines()
    for path in tracked:
        write("Sources/HanlinPlatformContracts/" + path.removeprefix(prefix), capture(path))
    for name in ["HanlinMiniAppActionChannel.swift", "HanlinMiniAppRequestBroker.swift"]:
        path = "Packages/HanlinPlatform/Sources/HanlinMiniAppCore/" + name
        write("Sources/HanlinMiniAppCore/" + name, capture(path))
    for name in ["HanlinMiniAppActionChannelTests.swift", "HanlinMiniAppRequestLifetimeTests.swift"]:
        path = "Packages/HanlinPlatform/Tests/HanlinMiniAppCoreTests/" + name
        write("Tests/ActionPayloadCapacityTests/" + name, capture(path))

    if not args.core_only:
        ns = between("AI_HLY/Downstream/HostServices/Adapters/NativeScriptHostServicesAdapter.swift",
                     "    private static func decodeJSONPayload(", "    public func sendRequest(")
        bridge = between("Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinScriptAppIntentBridge.swift",
                         "    static func decodeParameters(", "\n}\n\nprivate enum HanlinScriptAppIntentBridgeError:")
        error = capture("Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinScriptAppIntentBridge.swift").decode()
        error = error[error.index("private enum HanlinScriptAppIntentBridgeError:"):error.index("/// Metadata entry point")]
        write("Tests/ActionPayloadCapacityTests/NativeFoundationCodecTests.swift",
              "import Foundation\nimport CoreFoundation\nimport HanlinPlatformContracts\nimport Testing\n"
              + "private enum NativeScriptJSONProjection {\n" + ns
              + "    static func roundTrip(_ value: HanlinValue) throws -> HanlinValue {\n"
                "        try decodeJSONPayload(serializeUntaggedJSON(value))\n    }\n"
                "    static func decode(_ json: String) throws -> HanlinValue { try decodeJSONPayload(json) }\n}\n"
              + "private enum AppIntentJSONProjection {\n" + bridge + "\n}\n" + error
              + """
struct NativeFoundationCodecTests {
    @Test func nativeScriptJSONCodecsPreserveLargeDeepValuesAndRejectMalformedJSON() throws {
        var nested: HanlinValue = .bool(true)
        for _ in 0..<65 { nested = .array([nested]) }
        let value: HanlinValue = .object([
            "document": .string(String(repeating: "x", count: 4_194_305)),
            "nested": nested
        ])
        #expect(try NativeScriptJSONProjection.roundTrip(value) == value)
        #expect(throws: (any Error).self) { try NativeScriptJSONProjection.decode("{") }
    }
    @Test func appIntentJSONConversionPreservesLargeDeepValuesAndRejectsMalformedJSON() throws {
        let document = String(repeating: "x", count: 262_145)
        let nestedJSON = String(repeating: "[", count: 65) + "true" + String(repeating: "]", count: 65)
        let json = "{\\"document\\":\\"" + document + "\\",\\"nested\\":" + nestedJSON + "}"
        var nested: HanlinValue = .bool(true)
        for _ in 0..<65 { nested = .array([nested]) }
        #expect(try AppIntentJSONProjection.decodeParameters(json) == .object([
            "document": .string(document), "nested": nested
        ]))
        #expect(throws: (any Error).self) { try AppIntentJSONProjection.decodeParameters("[") }
    }
}
""")
    write("Package.swift", """// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ActionPayloadCapacity", targets: [
    .target(name: "HanlinPlatformContracts", resources: [.process("Resources")],
        swiftSettings: [.unsafeFlags(["-application-extension"], .when(platforms: [.iOS]))],
        linkerSettings: [.unsafeFlags(["-Xlinker", "-application_extension"], .when(platforms: [.iOS]))]),
    .target(name: "HanlinMiniAppCore", dependencies: ["HanlinPlatformContracts"]),
    .testTarget(name: "ActionPayloadCapacityTests", dependencies: ["HanlinMiniAppCore", "HanlinPlatformContracts"])
])
""")
    pattern = "requestReplyPreservesIdentityAndPayload|explicitlyRequestedDeadlinesAndSizeBudgetsAreStillEnforced"
    if not args.core_only:
        pattern += "|NativeFoundationCodecTests"
    command = ["swift", "test", "--package-path", str(package), "--filter", pattern,
               "--xunit-output", str(args.output / "tests.xml")]
    with (args.output / "swift-test.log").open("w") as log:
        process = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    result = {
        "status": "EXECUTED_PASS" if process.returncode == 0 else "FAILED",
        "baseCommit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "coreOnly": args.core_only, "command": command, "exitCode": process.returncode,
        "toolchain": subprocess.check_output(["swift", "--version"], text=True).strip(),
        "inputs": inputs, "nativeFreeProjections": projections,
        "scope": "Actual portable Core behavior and verbatim Foundation codecs only.",
        "notExecuted": ["Darwin queue persistence", "AppIntents discovery or execution", "NativeScript VM", "Expo VM", "physical device"]
    }
    (args.output / "receipt.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"status": result["status"], "exitCode": process.returncode,
                      "receipt": str(args.output / "receipt.json")}))
    raise SystemExit(process.returncode)
