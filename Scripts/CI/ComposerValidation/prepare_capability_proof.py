"""Stage complete production files for the isolated capability component proof.

This prepares inputs only. The parity/session suites and UI selector require the
real app target: their complete source closure includes ChatViewBottom and the
compact workspace. They must not be replaced with sliced tests or model stubs.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


SOURCES = (
    "AI_HLY/Downstream/ChatInput/HanlinMorphComposer.swift",
    "AI_HLY/Downstream/ChatInput/HanlinComposerPopupCoordinator.swift",
    "AI_HLY/Downstream/ChatInput/OrganizerDock/HanlinOrganizerDockState.swift",
    "AI_HLY/Downstream/ChatInput/HanlinDetachedCapabilityChips.swift",
    "AI_HLY/Downstream/ChatInput/HanlinComposerActionBridge.swift",
    "AI_HLY/Model/AllModels.swift",
    "AI_HLY/Downstream/ChatPresentation/ProviderModelCatalogMetadata.swift",
)
TEST_SOURCE = "AI_HLYTests/HanlinMorphComposerTests.swift"
COMPONENT_CASES = (
    "heightAndOverflow",
    "remainingViewportBudget",
    "backSwipeThreshold",
    "pageIdentity",
    "coordinatorNavigationPreservesOpenState",
    "capabilityRoutesReturnToOpenHome",
)
APP_INPUTS = (
    "AI_HLYTests/HanlinOrganizerDockParityTests.swift",
    "AI_HLYUITests/HanlinMorphComposerUITests.swift",
)
APP_SELECTORS = (
    "AI_HLYTests/ComposerActionsParityTests/detachedCapabilitiesProjectRealModeState",
    "AI_HLYTests/ChatComposerSessionBridgeTests/toolUseBindingRemainsScopedToItsChat",
    "AI_HLYUITests/HanlinMorphComposerUITests/testEnabledToolsChipOpensSettingsAndContextMenuDisables",
)


def prepare(repo: Path, source_sha: str, destination: Path) -> dict:
    if not re.fullmatch(r"[0-9a-f]{40}", source_sha):
        raise ValueError("An exact lowercase 40-character source commit is required")
    # A new output prevents mixing sources or stale build products across packets.
    destination.mkdir(parents=True, exist_ok=False)
    hashes = {}

    def blob(path: str) -> bytes:
        content = subprocess.check_output(
            ["git", "-C", str(repo), "show", f"{source_sha}:{path}"]
        )
        hashes[path] = hashlib.sha256(content).hexdigest()
        return content

    # Resolve every input before writing any package source. Worktree bytes are
    # never used, so a producer's continuing edits cannot enter this proof.
    contents = {path: blob(path) for path in (*SOURCES, TEST_SOURCE, *APP_INPUTS)}
    test_text = contents[TEST_SOURCE].decode("utf-8-sig")
    for case in COMPONENT_CASES:
        if len(re.findall(r"\bfunc\s+" + re.escape(case) + r"\s*\(", test_text)) != 1:
            raise ValueError(f"Missing or duplicate component case: {case}")
    for selector in APP_SELECTORS:
        case = selector.rsplit("/", 1)[-1]
        if not any(re.search(r"\bfunc\s+" + re.escape(case) + r"\s*\(",
                             contents[path].decode("utf-8-sig")) for path in APP_INPUTS):
            raise ValueError(f"Missing actual app selector: {selector}")
    for path in (*SOURCES, TEST_SOURCE):
        folder = "Tests/AI_HanlinTests" if path == TEST_SOURCE else "Sources/AI_Hanlin"
        target = destination / folder / Path(path).name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(contents[path])
        if target.read_bytes() != contents[path]:
            raise ValueError(f"Copy mismatch: {path}")
    manifest = Path(__file__).with_name("Package.swift").read_bytes()
    (destination / "Package.swift").write_bytes(manifest)
    result = {
        "status": "PREPARED_NOT_EXECUTED",
        "source_commit": source_sha,
        "consumer_module": "AI_Hanlin",
        "component_sources": list(SOURCES),
        "component_cases": list(COMPONENT_CASES),
        "actual_app_selectors_not_executed": list(APP_SELECTORS),
        "input_sha256": hashes,
        "harness_manifest_sha256": hashlib.sha256(manifest).hexdigest(),
        "scope": "Complete production component sources, including real SwiftData AllModels and metadata dependency; Morph route tests only. No parity/session/UI or physical-device acceptance.",
        "app_closure": [
            "HanlinOrganizerDockParityTests.swift -> HanlinCompactChatWorkspace -> ChatViewWrapper / ChatViewBottom",
            "ChatComposerSessionBridgeTests -> HanlinComposerSessionBridge -> ChatViewBottom.shouldEnableSend",
            "Actual app target and its metadata prerequisites are required; no sliced tests or replacement consumer types.",
        ],
    }
    (destination / "proof-inputs.json").write_text(
        json.dumps(result, indent=2) + "\n", encoding="utf-8", newline="\n"
    )
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = prepare(args.repo.resolve(), args.source_sha, args.output.resolve())
    print(json.dumps({key: result[key] for key in
                      ("status", "source_commit", "component_cases", "actual_app_selectors_not_executed")}))
