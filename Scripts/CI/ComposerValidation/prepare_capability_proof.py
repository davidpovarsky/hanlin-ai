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
    "AI_HLY/Downstream/ChatInput/NativeMultilineTextEditor.swift",
)
TEST_SOURCE = "AI_HLYTests/HanlinMorphComposerTests.swift"
EDITOR_TEST_SOURCE = "AI_HLYTests/NativeComposerLineSizingTests.swift"
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
EDITOR_SELECTORS = (
    "AI_HLYTests/NativeComposerLineSizingTests/wrappedLinesAndScrolling",
    "AI_HLYTests/NativeComposerLineSizingTests/fontAndViewport",
)


def prepare(repo: Path, source_sha: str, destination: Path, include_editor_tests: bool = False) -> dict:
    if not re.fullmatch(r"[0-9a-f]{40}", source_sha):
        raise ValueError("An exact lowercase 40-character source commit is required")
    # A new output prevents mixing sources or stale build products across packets.
    if destination.exists():
        raise ValueError("The proof output must be a new directory")
    hashes = {}

    def blob(path: str) -> bytes:
        content = subprocess.check_output(
            ["git", "-C", str(repo), "show", f"{source_sha}:{path}"]
        )
        hashes[path] = hashlib.sha256(content).hexdigest()
        return content

    # Resolve every input before writing any package source. Worktree bytes are
    # never used, so a producer's continuing edits cannot enter this proof.
    tests = (TEST_SOURCE, EDITOR_TEST_SOURCE) if include_editor_tests else (TEST_SOURCE,)
    contents = {path: blob(path) for path in (*SOURCES, *tests, *APP_INPUTS)}
    test_text = contents[TEST_SOURCE].decode("utf-8-sig")
    # Include every actual case in each complete owner file. The minimum names
    # below protect the earlier contract without silently omitting added cases.
    def case_names(text: str) -> list[str]:
        names = re.findall(r"@Test(?:\([^\n]*\))?\s+func\s+(\w+)\s*\(", text)
        if not names or len(names) != len(set(names)):
            raise ValueError("Missing or duplicate test declarations in a whole owner file")
        return names

    morph_cases = case_names(test_text)
    editor_cases = []
    for case in COMPONENT_CASES:
        if len(re.findall(r"\bfunc\s+" + re.escape(case) + r"\s*\(", test_text)) != 1:
            raise ValueError(f"Missing or duplicate component case: {case}")
    for selector in (*APP_SELECTORS, *EDITOR_SELECTORS):
        case = selector.rsplit("/", 1)[-1]
        if not any(re.search(r"\bfunc\s+" + re.escape(case) + r"\s*\(",
                             contents[path].decode("utf-8-sig")) for path in (*APP_INPUTS, *tests)):
            raise ValueError(f"Missing actual app selector: {selector}")
    if include_editor_tests:
        editor_text = contents[EDITOR_TEST_SOURCE].decode("utf-8-sig")
        editor_cases = case_names(editor_text)
        parity_text = contents[APP_INPUTS[0]].decode("utf-8-sig")
        if not re.search(r"\bstruct\s+NativeComposerLineSizingTests\b", editor_text):
            raise ValueError("The whole owner editor suite is required")
        if re.search(r"\bstruct\s+NativeComposerLineSizingTests\b", parity_text):
            raise ValueError("Editor suite is still duplicated in the parity file")
    destination.mkdir(parents=True, exist_ok=False)
    for path in (*SOURCES, *tests):
        folder = "Tests/AI_HanlinTests" if path in tests else "Sources/AI_Hanlin"
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
        "component_cases": morph_cases,
        "editor_cases": editor_cases,
        "component_test_sources": list(tests),
        "expected_case_ids": [f"HanlinMorphComposerTests/{case}()" for case in morph_cases]
            + [f"NativeComposerLineSizingTests/{case}()" for case in editor_cases],
        "actual_app_selectors_not_executed": list(APP_SELECTORS),
        "editor_selectors_not_executed":
            [f"AI_HLYTests/NativeComposerLineSizingTests/{case}" for case in editor_cases]
            if include_editor_tests else list(EDITOR_SELECTORS),
        "editor_test_file_staged": include_editor_tests,
        "input_sha256": hashes,
        "harness_manifest_sha256": hashlib.sha256(manifest).hexdigest(),
        "scope": "Whole production component files, including real SwiftData AllModels, metadata dependency and UIKit editor. Only the complete test files listed here are staged. No parity/session/manual-dock/app-UI or physical-device acceptance; preparation itself never asserts execution.",
        "app_closure": [
            "HanlinOrganizerDockParityTests.swift -> HanlinCompactChatWorkspace -> ChatViewWrapper / ChatViewBottom",
            "ChatComposerSessionBridgeTests -> HanlinComposerSessionBridge -> ChatViewBottom.shouldEnableSend",
            "Actual app target and its metadata prerequisites are required; no sliced tests or replacement consumer types.",
        ],
        "focused_editor_test_boundary": {
            "required_owner_file": "AI_HLYTests/NativeComposerLineSizingTests.swift",
            "owner_action": "Relocate the complete NativeComposerLineSizingTests suite from the parity file, preserving both case bodies and assertions, before staging that whole new file.",
            "production_closure": ["AI_HLY/Downstream/ChatInput/NativeMultilineTextEditor.swift"],
            "frameworks": ["SwiftUI", "UIKit", "UniformTypeIdentifiers", "Testing"],
            "project_registration": "AI_HLYTests uses a synchronized root group; no project file membership change is needed for the new owner test file.",
            "not_covered": "Mounted ChatViewBottom, observer refresh, manual dock resize and app UI still require their real tests; UIKit measurement cases cannot establish those results.",
        },
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
    parser.add_argument("--with-editor-tests", action="store_true",
                        help="Require the owner's separately relocated whole UIKit suite")
    args = parser.parse_args()
    result = prepare(args.repo.resolve(), args.source_sha, args.output.resolve(), args.with_editor_tests)
    print(json.dumps({key: result[key] for key in
                      ("status", "source_commit", "component_cases", "actual_app_selectors_not_executed")}))
