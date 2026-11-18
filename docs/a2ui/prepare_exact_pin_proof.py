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
import subprocess
import tarfile
import io
import xml.etree.ElementTree as ET

REPOSITORY = Path(__file__).resolve().parents[2]
UPSTREAM = "https://github.com/a2ui-project/a2ui"
REVISION = "3ed9601862ecc78027e20ac80ad8b1b98a5d9079"
CONSUMER_MODULE = "AI_Hanlin"
PORTABLE_CASE_COUNT = 8
SDK_CASE_COUNT = 38
MEDIA_CASES = ["customMediaCatalogResolvesYouTubeThroughOfficialGraphAndBinding",
               "customMediaCannotAlterOfficialCatalogOrAdmitScriptFields",
               "galleryAndLinkSourcesResolveThroughTheOfficialCatalogAndBindings",
               "richMediaSchemasRejectUnboundedCollectionsMissingSourcesAndScripts"]
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
MEDIA_SOURCES = "AI_HLY/Downstream/ChatPresentation/Media"
TEST = "AI_HLYTests/A2UITests.swift"
MEDIA_POLICY_TEST = "AI_HLYTests/HanlinRemoteMediaURLTests.swift"
FIXTURES = "AI_HLYTests/A2UIFixtures"
SDK_SHA = "18813519eada1db152bd206d5c7bd922ddc987ee"
APP_SDK_SHA = "d1eedf9ed73b4f6c7c64f488caf92494602db865"
APP_SOURCE = "AI_HLY/Downstream/ChatPresentation/AgentSDK/HanlinA2UIAppPresentation.swift"
APP_TEST = "AI_HLYTests/HanlinA2UIAppPresentationTests.swift"
APP_CONTRACT = "AI_HLY/Downstream/ChatCore/HanlinAppAgentPresentationContracts.swift"
APP_CASES = [
    "originalRowAndUIRunMapToCanonicalSurfaceWithoutTextInference",
    "foreignAndAmbiguousBindingsCannotRetargetAnExistingRow",
    "realRendererActionQueuesOriginalBindingAndRevokesBeforeAsyncContinuation",
    "canonicalHistoryKeepsOriginalDisplayBindingWithoutRestoringAuthority",
    "sourceReplacementIsObservedOutsideViewBody",
]
PRODUCER_SHA = "e7bf34111e603ca977becd007dd4e5bb109af857"
CONSUMER_SOURCE = "AI_HLY/Downstream/ChatPresentation/AgentSDK/HanlinA2UIAgentPresentationAdapter.swift"
CONSUMER_TEST = "AI_HLYTests/HanlinA2UIAgentPresentationTests.swift"
VALIDATOR_SOURCE = "AI_HLY/Downstream/ChatPresentation/AgentSDK/HanlinA2UICompleteBatchValidator.swift"
VALIDATOR_TEST = "AI_HLYTests/HanlinA2UICompleteBatchValidatorTests.swift"
VALIDATOR_CASES = [
    "completeBatchUsesOfficialSchemasAndResolvesForwardReferences",
    "finalGraphRejectsMissingRootDanglingReferencesAndSchemaErrors",
    "independentOwnersReuseWireAndPartIDsWithoutSharingGraphs",
    "wholeBatchFramingRejectsBeforeAnyScratchConstruction",
    "canonicalOrderKindsProtocolAndResourceBoundsArePreserved",
    "scratchProcessorsDisposeOnSuccessAndFailureWithoutRPCAuthority",
]
CONSUMER_CASES = [
    "bufferedEOFRetainsRealRendererActionAndSeparateRunIdentity",
    "canonicalRecordReplayKeepsBytesAndCannotRestoreActions",
    "invalidationRejectsQueuedOriginalEventsAndKeys",
    "malformedCompletePartStaysUnavailableAndPreservesAdjacentText",
    "completedRunBudgetRevokesBeforeUnboundedIdentityGrowth",
    "canonicalMessagesCanReusePartIDWithoutSharingFormState",
]
PROJECTION_CASES = ["modelPartUsesMessageIdentityWithoutToolCall",
    "orderedModelProjectionPreservesTextAndRegisteredSurface",
    "modelProjectionRejectsForeignIdentityAndAmbiguousParts", "modelProjectionNeverFollowsReplacedGeneration"]
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


def package_text(platform: str, consumer: bool = False) -> str:
    text = PACKAGE.replace('.macOS("27.0")', '.iOS("27.0")') if platform == "ios" else PACKAGE
    if platform == "ios":
        text = text.replace('let products: [Target.Dependency] = [', '''let products: [Target.Dependency] = [
    .product(name: "SwiftSoup", package: "SwiftSoup"),''')
        text = text.replace('dependencies: [', '''dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", revision: "bba848db50462894e7fc0891d018dfecad4ef11e"),''', 1)
    if consumer:
        text = text.replace('swift-tools-version: 6.1', 'swift-tools-version: 6.2')
        text = text.replace('let products: [Target.Dependency] = [', '''let products: [Target.Dependency] = [
    .product(name: "HanlinAgentCore", package: "HanlinAgentSDK"),
    .product(name: "HanlinHostContracts", package: "HanlinAgentSDK"),
    .product(name: "HanlinPersistenceAdapters", package: "HanlinAgentSDK"),
    .product(name: "HanlinPlatformContracts", package: "HanlinPlatform"),
    .product(name: "HanlinChatCore", package: "HanlinPlatform"),
    .product(name: "AISDKProvider", package: "swift-ai-sdk"),''')
        text = text.replace('dependencies: [', f'''dependencies: [
        .package(path: "../Packages/HanlinAgentSDK"),
        .package(path: "../Packages/HanlinPlatform"),
        .package(url: "https://github.com/davidpovarsky/swift-ai-sdk.git", revision: "{PRODUCER_SHA}"),''', 1)
    return text


def plan(platform: str = "macos", consumer: bool = False, app: bool = False) -> dict:
    sdk_source = APP_SDK_SHA if app else SDK_SHA
    source = (REPOSITORY / TEST).read_text(encoding="utf-8")
    if re.findall(r"^@testable import (\w+)$", source, re.MULTILINE) != [CONSUMER_MODULE]:
        raise ValueError("Test import must match the actual AI_Hanlin consumer; do not add a module alias")
    ingress, sdk = source.split("struct A2UISDKTests", 1)
    cases = lambda text: re.findall(r"^\s+@Test func (\w+)\(", text, re.MULTILINE)
    portable, native = cases(ingress), cases(sdk)
    if (len(portable) != PORTABLE_CASE_COUNT or len(native) != SDK_CASE_COUNT
            or len(set(portable + native)) != CASE_COUNT):
        raise ValueError(f"Expected exactly {PORTABLE_CASE_COUNT} portable and {SDK_CASE_COUNT} enabled SDK cases; update the proof contract")
    if not set(OWNERSHIP_CASES + MEDIA_CASES).issubset(native):
        raise ValueError("Missing exact affected ownership case")
    paths = sorted((REPOSITORY / SOURCES).glob("*.swift"))
    media_cases = list(MEDIA_CASES)
    if platform == "ios":
        paths += sorted((REPOSITORY / MEDIA_SOURCES).glob("*.swift"))
        paths += [REPOSITORY / MEDIA_POLICY_TEST]
        policy_cases = re.findall(r"@Test func (\w+)\(", (REPOSITORY / MEDIA_POLICY_TEST).read_text(encoding="utf-8"))
        if len(set(policy_cases)) != 7:
            raise ValueError("Expected seven media source/address admission controls")
        media_cases += policy_cases
    paths += [REPOSITORY / TEST] + sorted((REPOSITORY / FIXTURES).iterdir())
    if consumer:
        paths += [REPOSITORY / CONSUMER_SOURCE, REPOSITORY / CONSUMER_TEST,
                  REPOSITORY / VALIDATOR_SOURCE, REPOSITORY / VALIDATOR_TEST]
        suite_source = (REPOSITORY / CONSUMER_TEST).read_text(encoding="utf-8").split("struct HanlinA2UIAgentPresentationTests {", 1)[1]
        actual = re.findall(r"^    func (\w+)\(", suite_source, re.MULTILINE)
        if actual != CONSUMER_CASES:
            raise ValueError("Unexpected consumer integration test identities")
        actual = re.findall(r"@Test func (\w+)\(", (REPOSITORY / VALIDATOR_TEST).read_text(encoding="utf-8"))
        if actual != VALIDATOR_CASES:
            raise ValueError("Unexpected pure validator test identities")
    if app:
        paths += [REPOSITORY / APP_SOURCE, REPOSITORY / APP_TEST]
        suite = (REPOSITORY / APP_TEST).read_text(encoding="utf-8").split("struct HanlinA2UIAppPresentationTests {", 1)[1]
        if re.findall(r"^    func (\w+)\(", suite, re.MULTILINE) != APP_CASES:
            raise ValueError("Unexpected actual application-consumer test identities")
    files = [{"path": p.relative_to(REPOSITORY).as_posix(), "sha256": sha(p.read_bytes())}
             for p in paths if p.is_file()]
    if app:
        original = subprocess.check_output(["git", "show", sdk_source + ":" + APP_CONTRACT], cwd=REPOSITORY)
        files.append({"path": APP_CONTRACT, "sha256": sha(original), "source_git_sha": sdk_source})
    result = {"status": "PREPARED_NOT_EXECUTED", "upstream": UPSTREAM, "revision": REVISION,
            "consumer_module": CONSUMER_MODULE, "test_module": "AI_HLYTests",
            "portable_cases": portable, "sdk_cases": native, "ownership_cases": OWNERSHIP_CASES,
            "media_cases": media_cases, "files": files, "target_platform": platform,
            "harness_manifest_sha256": sha(package_text(platform, consumer).encode()),
            "native_execution": "NOT_RUN", "platform": platform + "27 / current stable Xcode"}
    if consumer:
        result.update(consumer_cases=CONSUMER_CASES, projection_cases=PROJECTION_CASES, validator_cases=VALIDATOR_CASES,
                      sdk_source_sha=sdk_source, producer_revision=PRODUCER_SHA,
                      sdk_tree_ids={name: subprocess.check_output(["git", "rev-parse", f"{sdk_source}:Packages/{name}"], cwd=REPOSITORY, text=True).strip()
                                    for name in ["HanlinAgentSDK", "HanlinPlatform"]})
    if app:
        result.update(app_cases=APP_CASES, scope="actual app presentation protocol/consumer; ChatView/SwiftData owner/native model/XCUITest NOT_RUN")
    return result


def prepare(destination: Path, inputs: dict) -> None:
    if sys.platform != "darwin":
        raise ValueError("Harness creation requires the separately authorized macOS execution host")
    destination = destination.resolve()
    if destination.is_relative_to(REPOSITORY) or destination.exists():
        raise ValueError("Use a fresh temporary directory outside the product checkout")
    destination.mkdir()
    for entry in inputs["files"]:
        relative = entry["path"]
        data = (subprocess.check_output(["git", "show", entry["source_git_sha"] + ":" + relative], cwd=REPOSITORY)
                if "source_git_sha" in entry else (REPOSITORY / relative).read_bytes())
        if sha(data) != entry["sha256"]:
            raise ValueError(f"Input changed while preparing proof: {relative}")
        if relative.startswith(SOURCES + "/") or relative.startswith(MEDIA_SOURCES + "/") or relative in [CONSUMER_SOURCE, VALIDATOR_SOURCE, APP_SOURCE, APP_CONTRACT]:
            target = destination / "Sources" / CONSUMER_MODULE / Path(relative).name
        elif relative in [TEST, MEDIA_POLICY_TEST, CONSUMER_TEST, VALIDATOR_TEST, APP_TEST]:
            target = destination / "Tests/AI_HLYTests" / Path(relative).name
        else:
            target = destination / "Tests/AI_HLYTests/A2UIFixtures" / Path(relative).name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    consumer = "sdk_source_sha" in inputs
    if consumer:
        archive = subprocess.check_output(["git", "archive", "--format=tar", inputs["sdk_source_sha"],
                                          "Packages/HanlinAgentSDK", "Packages/HanlinPlatform"], cwd=REPOSITORY)
        with tarfile.open(fileobj=io.BytesIO(archive)) as content:
            content.extractall(destination.parent, filter="data")
    (destination / "Package.swift").write_text(package_text(inputs["target_platform"], consumer), encoding="utf-8")
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
    parser.add_argument("--platform", choices=["macos", "ios"], default="macos")
    parser.add_argument("--sdk-consumer", action="store_true")
    parser.add_argument("--app-consumer", action="store_true")
    parser.add_argument("--suite", choices=["all", "sdk", "ownership", "media", "consumer", "app"], default="all",
                        help="Verify only SDK identities when portable framing is unaffected")
    args = parser.parse_args()
    inputs = plan(args.platform, args.sdk_consumer or args.app_consumer, args.app_consumer)
    def check_lock(path: Path) -> None:
        lock = json.loads(path.read_text(encoding="utf-8"))
        verify_pin(lock)
        if args.sdk_consumer or args.app_consumer:
            producer = [p for p in lock["pins"] if p.get("identity") == "swift-ai-sdk"]
            if len(producer) != 1 or producer[0]["state"].get("revision") != PRODUCER_SHA:
                raise ValueError("Canonical producer revision changed")
    if args.self_test:
        print(json.dumps({"local_validator_self_checks": self_test(inputs),
                          "data": "synthetic XML/lock; not native execution", "sdk": "NOT_RUN"}))
    elif args.verify_pin:
        check_lock(args.verify_pin)
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
        check_lock(args.resolved)
        expected = (inputs["app_cases"] + inputs["consumer_cases"] + inputs["projection_cases"] if args.suite == "app" else inputs["consumer_cases"] + inputs["ownership_cases"] + inputs["validator_cases"] if args.suite == "consumer" else inputs["media_cases"] if args.suite == "media" else inputs["ownership_cases"]
                    if args.suite == "ownership" else inputs["sdk_cases"]
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
