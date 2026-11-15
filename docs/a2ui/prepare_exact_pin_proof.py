"""Prepare, but never dispatch or run, the isolated official-SDK proof.

Default/--plan and --self-test are read-only and portable. --output creates a
fresh temporary harness only on an authorized macOS host, outside the checkout.
No app project, dependency manifest/lock, source or build setting is modified.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

REPOSITORY = Path(__file__).resolve().parents[2]
UPSTREAM = "https://github.com/a2ui-project/a2ui"
REVISION = "3ed9601862ecc78027e20ac80ad8b1b98a5d9079"
CONSUMER_MODULE = "AI_Hanlin"
PORTABLE_CASE_COUNT = 8
SDK_CASE_COUNT = 36
OWNERSHIP_CASES = [
    "successfulProducerEOFKeepsOriginalModelActionAndClosesInput",
    "producerEOFDoesNotSurviveRevocationOrFollowAnotherGeneration",
    "producerEOFCancelsOnlyItsReceiverAndCannotReplaceFinishedTool",
    "modelPartUsesMessageIdentityWithoutToolCall",
    "orderedModelProjectionPreservesTextAndRegisteredSurface",
    "modelProjectionRejectsForeignIdentityAndAmbiguousParts",
    "modelProjectionNeverFollowsReplacedGeneration",
    "transientOwnerLookupKeepsWireIDsIndependent",
    "transientReceiveRejectsWrongIdentityAndSequence",
    "sealedResultRetainsModelsAndRevokesActions",
    "sealingRunDoesNotRevokeOtherRun",
    "replacementRevokesOldGenerationBeforeNewDelivery",
    "endingResultCancelsOwnedReceiveTask",
    "presentationCopiesDoNotOwnDiscard",
    "eventSinkIsWeakAndCannotKeepAuthorityAlive",
    "deletedSurfaceDropsQueuedOwnedEvents",
    "retiredSurfaceCannotReanimateQueuedEventsInSameResult",
]
CASE_COUNT = PORTABLE_CASE_COUNT + SDK_CASE_COUNT
SOURCES = "AI_HLY/Downstream/ChatPresentation/A2UI"
TEST = "AI_HLYTests/A2UITests.swift"
FIXTURES = "AI_HLYTests/A2UIFixtures"
PACKAGE = f'''// swift-tools-version: 6.1
import PackageDescription

let products: [Target.Dependency] = [
    .product(name: "A2UISwiftCore", package: "a2ui"),
    .product(name: "A2UISwiftUI", package: "a2ui"),
    .product(name: "BasicCatalog", package: "a2ui"),
    .product(name: "BasicCatalogSwiftUI", package: "a2ui"),
]
let enabled: [SwiftSetting] = [
    .define("HANLIN_A2UI_POC", .when(configuration: .debug)),
    .define("DEBUG", .when(configuration: .debug)),
]
let package = Package(
    name: "HanlinA2UIProof",
    platforms: [.macOS("27.0")],
    dependencies: [.package(url: "{UPSTREAM}", revision: "{REVISION}")],
    targets: [
        .target(name: "{CONSUMER_MODULE}", dependencies: products, swiftSettings: enabled),
        .testTarget(name: "AI_HLYTests", dependencies: ["{CONSUMER_MODULE}"] + products,
                    resources: [.copy("A2UIFixtures")], swiftSettings: enabled),
    ],
    swiftLanguageModes: [.v6]
)
'''


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def plan() -> dict:
    source = (REPOSITORY / TEST).read_text(encoding="utf-8")
    if re.findall(r"^@testable import (\w+)$", source, re.MULTILINE) != [CONSUMER_MODULE]:
        raise ValueError("Test import must match the actual AI_Hanlin consumer; do not add a module alias")
    ingress, sdk = source.split("struct A2UISDKTests", 1)
    cases = lambda text: re.findall(r"^\s+@Test func (\w+)\(", text, re.MULTILINE)
    portable, native = cases(ingress), cases(sdk)
    if (len(portable) != PORTABLE_CASE_COUNT or len(native) != SDK_CASE_COUNT
            or len(set(portable + native)) != CASE_COUNT):
        raise ValueError(f"Expected exactly {PORTABLE_CASE_COUNT} portable and {SDK_CASE_COUNT} enabled SDK cases; update the proof contract")
    if not set(OWNERSHIP_CASES).issubset(native):
        raise ValueError("Missing exact affected ownership case")
    paths = sorted((REPOSITORY / SOURCES).glob("*.swift"))
    paths += [REPOSITORY / TEST] + sorted((REPOSITORY / FIXTURES).iterdir())
    files = [{"path": p.relative_to(REPOSITORY).as_posix(), "sha256": sha(p.read_bytes())}
             for p in paths if p.is_file()]
    return {"status": "PREPARED_NOT_EXECUTED", "upstream": UPSTREAM, "revision": REVISION,
            "consumer_module": CONSUMER_MODULE, "test_module": "AI_HLYTests",
            "portable_cases": portable, "sdk_cases": native, "ownership_cases": OWNERSHIP_CASES, "files": files,
            "harness_manifest_sha256": sha(PACKAGE.encode()),
            "native_execution": "NOT_RUN", "platform": "macOS27 / current stable Xcode"}


def prepare(destination: Path, inputs: dict) -> None:
    if sys.platform != "darwin":
        raise ValueError("Harness creation requires the separately authorized macOS execution host")
    destination = destination.resolve()
    if destination.is_relative_to(REPOSITORY) or destination.exists():
        raise ValueError("Use a fresh temporary directory outside the product checkout")
    destination.mkdir()
    for entry in inputs["files"]:
        relative = entry["path"]
        data = (REPOSITORY / relative).read_bytes()
        if sha(data) != entry["sha256"]:
            raise ValueError(f"Input changed while preparing proof: {relative}")
        if relative.startswith(SOURCES + "/"):
            target = destination / "Sources" / CONSUMER_MODULE / Path(relative).name
        elif relative == TEST:
            target = destination / "Tests/AI_HLYTests/A2UITests.swift"
        else:
            target = destination / "Tests/AI_HLYTests/A2UIFixtures" / Path(relative).name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    (destination / "Package.swift").write_text(PACKAGE, encoding="utf-8")
    (destination / "proof-inputs.json").write_text(json.dumps(inputs, indent=2) + "\n", encoding="utf-8")


def verify_pin(lock: dict) -> None:
    roots = [p for p in lock["pins"] if p.get("identity") == "a2ui"]
    if len(roots) != 1:
        raise ValueError("Missing or ambiguous official a2ui resolution")
    location = roots[0].get("location", "").removesuffix(".git").rstrip("/")
    if location != UPSTREAM or roots[0]["state"].get("revision") != REVISION:
        raise ValueError("Resolved root repository/revision does not match the inspected SDK")


def verify_cases(roots: list[ET.Element], expected: list[str]) -> None:
    seen: list[str] = []
    for root in roots:
        for suite in root.iter("testsuite"):
            if any(int(suite.get(key, "0")) != 0 for key in ("errors", "failures", "skipped", "disabled")):
                raise ValueError("Result bundle includes failures/skips")
        for case in root.iter("testcase"):
            if any(case.find(tag) is not None for tag in ("failure", "error", "skipped")):
                raise ValueError("A case did not execute successfully")
            if case.get("status", "").lower() in ("skipped", "notrun", "disabled"):
                raise ValueError("A case was not run")
            identity = case.get("classname", "") + "/" + case.get("name", "")
            matches = [name for name in expected if re.search(rf"(?<!\w){re.escape(name)}(?:\(\))?(?!\w)", identity)]
            if len(matches) != 1:
                raise ValueError(f"Unrecognized/ambiguous actual test identity: {identity}")
            seen.append(matches[0])
    if sorted(seen) != sorted(expected):
        raise ValueError(f"Executed cases differ from the exact {len(expected)}-case contract (missing/duplicate/zero cases)")


def self_test(inputs: dict) -> int:
    names = inputs["portable_cases"] + inputs["sdk_cases"]
    def result(selected: list[str]) -> ET.Element:
        root = ET.Element("testsuite")
        for name in selected:
            ET.SubElement(root, "testcase", name=name + "()", classname="AI_HLYTests")
        return root
    verify_cases([result(names)], names)
    bad = [result([]), result(names[:-1]), result(names + [names[0]]), result(names)]
    ET.SubElement(bad[-1][0], "skipped")
    for root in bad:
        try:
            verify_cases([root], names)
        except ValueError:
            continue
        raise AssertionError("Synthetic invalid result was accepted")
    lock = {"pins": [{"identity": "a2ui", "location": UPSTREAM, "state": {"revision": REVISION}}]}
    verify_pin(lock)
    lock["pins"][0]["state"]["revision"] = "0" * 40
    try:
        verify_pin(lock)
    except ValueError:
        return 7  # Valid cases, four invalid bundles, valid pin, invalid pin.
    raise AssertionError("Wrong SDK revision was accepted")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--plan", action="store_true")
    modes.add_argument("--output", type=Path)
    modes.add_argument("--self-test", action="store_true")
    modes.add_argument("--verify-pin", type=Path)
    modes.add_argument("--verify-results", type=Path, nargs="+")
    modes.add_argument("--verify-xcresult", type=Path)
    parser.add_argument("--resolved", type=Path)
    parser.add_argument("--inputs", type=Path)
    parser.add_argument("--suite", choices=["all", "sdk", "ownership"], default="all",
                        help="Verify only SDK identities when portable framing is unaffected")
    args = parser.parse_args()
    inputs = plan()
    if args.self_test:
        print(json.dumps({"local_validator_self_checks": self_test(inputs),
                          "data": "synthetic XML/lock; not native execution", "sdk": "NOT_RUN"}))
    elif args.verify_pin:
        verify_pin(json.loads(args.verify_pin.read_text(encoding="utf-8")))
        print(json.dumps({"status": "RESOLVED_PIN_MATCHES", "native_execution": "NOT_ASSERTED",
                          "lock_sha256": sha(args.verify_pin.read_bytes())}))
    elif args.output:
        prepare(args.output, inputs)
        print(json.dumps({"harness": str(args.output.resolve()), "status": "PREPARED_NOT_EXECUTED"}))
    elif args.verify_results or args.verify_xcresult:
        if not args.resolved or not args.inputs:
            parser.error("--verify-results requires the actual --resolved lock and retained --inputs")
        recorded = json.loads(args.inputs.read_text(encoding="utf-8"))
        if recorded != inputs:
            raise ValueError("Current sources/cases/harness differ from the retained proof inputs")
        verify_pin(json.loads(args.resolved.read_text(encoding="utf-8")))
        expected = (inputs["ownership_cases"] if args.suite == "ownership" else inputs["sdk_cases"]
                    if args.suite == "sdk" else inputs["portable_cases"] + inputs["sdk_cases"])
        if args.verify_xcresult:
            root = ET.Element("testsuite")
            def visit(node):
                if isinstance(node, dict):
                    if node.get("nodeType") == "Test Case":
                        case = ET.SubElement(root, "testcase", name=node.get("name", ""),
                                             classname=node.get("nodeIdentifier", ""))
                        if node.get("result") != "Passed":
                            ET.SubElement(case, "failure")
                    for value in node.values():
                        visit(value)
                elif isinstance(node, list):
                    for value in node:
                        visit(value)
            visit(json.loads(args.verify_xcresult.read_text(encoding="utf-8")))
            verify_cases([root], expected)
        else:
            verify_cases([ET.parse(p).getroot() for p in args.verify_results], expected)
        print(json.dumps({"status": "RESULT_CONTENTS_VALID", "cases": len(expected), "suite": args.suite,
                          "provenance": "Authenticate process/toolchain/artifact separately",
                          "lock_sha256": sha(args.resolved.read_bytes())}))
    else:
        print(json.dumps(inputs, indent=2))


if __name__ == "__main__":
    main()
