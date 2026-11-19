"""Read an owned completed xcresult. No build, simulator launch or test execution."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile

EVIDENCE_FILES = (
    "08-downstream-unit-test-results.json",
    "08-downstream-unit-tests.log",
    "08-nativescript-production-ui-tests.log",
    "06-diagnostics-build-provenance.json",
    "acceptance.json",
    "storage-summary.json",
    "test-summary.json",
    "fixture-provenance.log",
)
PAIRED_SUITES = frozenset({"HanlinPairedProductUITests", "HanlinShareInboxUITests"})


def _parse_selector(raw_selector: str) -> tuple[str | None, str]:
    selected = raw_selector.strip().removesuffix("()")
    target = None
    if selected.count("/") == 2:
        target, selected = selected.split("/", 1)
    assert re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*/[A-Za-z_][A-Za-z_0-9]*", selected), "Select exact original methods"
    return target, selected


def _resolve_mode(run: str, requested: str, names: set[str]) -> tuple[bool, bool, bool, str]:
    motion = run == "43771756937" or bool(requested) and all(s.strip().startswith("MotionUITests/") for s in requested.split(","))
    split = not motion and bool(requested) and f"app-split-{run}" in names
    paired = False
    if split:
        parsed = [_parse_selector(s) for s in requested.split(",")]
        paired_flags = [suite_method.split("/", 1)[0] in PAIRED_SUITES for _, suite_method in parsed]
        if any(paired_flags):
            assert all(paired_flags) and all(t in (None, "AI_HLYUITests") for t, _ in parsed), "Ambiguous or invalid paired test selection"
            paired = True
    artifact = (f"app-split-{run}" if split else f"chat-motion-ui-{run}"
                if motion and f"chat-motion-ui-{run}" in names else "AI_Hanlin-iOS26-simulator-smoke-logs")
    assert artifact in names, "Original native evidence artifact is unavailable"
    return motion, split, paired, artifact


def _resolve_selections(raw: Path, requested: str, motion: bool, split: bool, paired: bool) -> list[tuple[str, str, Path]]:
    default_target = "AI_HLYUITests" if paired else "HanlinMiniAppsUITests" if split else "MotionUITests" if motion else "AI_HLYUITests"
    default_tests = ["MotionUITests/testBRapidReversalPresetSwitchAndPersistence()", "MotionUITests/testCReadableLongContentRTLTypeOrientationAndCompletion()"] if motion else ["HanlinMorphComposerUITests/testDismissModelPickerKeepsSelectedModelAndDraft()"]
    allowed = {"AI_HLYUITests"} if paired else {"HanlinMiniAppsUITests"} if split else {"MotionUITests"} if motion else {"AI_HLYTests", "AI_HLYUITests"}
    selections = []
    for raw_selected in requested.split(",") if requested else default_tests:
        explicit_target, selected = _parse_selector(raw_selected)
        target = explicit_target if explicit_target is not None else default_target
        assert target in allowed, "Wrong original native test target"
        if paired:
            assert selected.split("/", 1)[0] in PAIRED_SUITES, "Wrong original paired test suite"
        bundle_name = ("Paired.xcresult" if paired else "MiniApps.xcresult" if split else "Motion.xcresult"
                       if motion else "DownstreamTestsResult.xcresult" if target == "AI_HLYTests" else "NativeScriptProductionE2EResult.xcresult")
        bundles = list(raw.rglob(bundle_name))
        assert len(bundles) == 1, "Expected exactly one original native result: " + bundle_name
        selections.append((target, selected + "()", bundles[0]))
    assert 1 <= len(selections) <= 20, "Bound the original attachment inspection"
    return selections


def _copy_evidence_files(raw: Path, out: Path, preferred_parent: Path | None = None) -> None:
    for name in EVIDENCE_FILES:
        if preferred_parent is not None and (preferred_parent / name).is_file():
            shutil.copyfile(preferred_parent / name, out / name)
            continue
        matches = list(raw.rglob(name))
        assert len(matches) <= 1, "Ambiguous original evidence file: " + name
        if matches:
            shutil.copyfile(matches[0], out / name)


def _export_selections(out: Path, selections: list[tuple[str, str, Path]]) -> None:
    (out / "selected-tests.json").write_text(json.dumps([test for _, test, _ in selections], indent=2))
    (out / "selected-test-origins.json").write_text(json.dumps([
        {"index": index, "target": target, "test": test, "bundle": bundle.name}
        for index, (target, test, bundle) in enumerate(selections)
    ], indent=2))
    exported_bundles = set()
    for index, (target, test, bundle) in enumerate(selections):
        if bundle not in exported_bundles:
            name = "tests.json" if not exported_bundles else target + "-tests.json"
            with (out / name).open("w") as log:
                subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(bundle), "--format", "json"], stdout=log, check=True)
            exported_bundles.add(bundle)
        folder = out / f"case-{index}"
        subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(bundle), "--output-path", str(folder), "--test-id", test], check=True)
        with (out / f"case-{index}-activities.json").open("w") as log:
            result = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "activities", "--path", str(bundle), "--test-id", test, "--format", "json"], stdout=log, stderr=subprocess.STDOUT)
        assert result.returncode == 0


def main() -> None:
    run = os.environ["SOURCE_RUN_ID"]
    assert run.isdigit()
    repo = os.environ["GITHUB_REPOSITORY"]
    out = Path("native-result-inspection")
    out.mkdir(exist_ok=True)
    source = json.loads(subprocess.check_output(["gh", "api", f"repos/{repo}/actions/runs/{run}"]))
    assert source["status"] == "completed"
    (out / "source-run.json").write_text(json.dumps({"run": run, "head": source["head_sha"], "conclusion": source["conclusion"]}, indent=2))
    raw = Path(os.environ["RUNNER_TEMP"]) / f"native-result-{run}"
    requested = os.environ.get("SELECTED_TESTS", "").strip()
    available = json.loads(subprocess.check_output(["gh", "api", f"repos/{repo}/actions/runs/{run}/artifacts"]))
    names = {a["name"] for a in available["artifacts"] if not a["expired"]}
    motion, split, paired, artifact = _resolve_mode(run, requested, names)
    subprocess.run(["gh", "run", "download", run, "--repo", repo, "--name", artifact, "--dir", str(raw)], check=True)
    if motion:
        archive = next(raw.rglob("Motion.xcresult.tar.gz"))
        with tarfile.open(archive) as packed:
            packed.extractall(raw / "expanded", filter="data")
    selections = _resolve_selections(raw, requested, motion, split, paired)
    _copy_evidence_files(raw, out, selections[0][2].parent if paired else None)
    _export_selections(out, selections)


if __name__ == "__main__":
    main()
