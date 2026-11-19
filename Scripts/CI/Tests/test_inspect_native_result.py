#!/usr/bin/env python3
"""Focused regression tests for Scripts/CI/inspect_native_result.py."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

_REPO_ROOT = str(Path(__file__).resolve().parents[3])
if _REPO_ROOT not in sys.path:
    sys.path.insert(0, _REPO_ROOT)

from Scripts.CI import inspect_native_result


class InspectNativeResultTests(unittest.TestCase):
    def _run_main_with_fake_archive(
        self,
        tmp: Path,
        run_id: str,
        selected_tests: str,
        artifact_names: list[str],
    ) -> tuple[Path, list[list[str]]]:
        work_dir = tmp / "work"
        work_dir.mkdir(parents=True, exist_ok=True)
        runner_temp = tmp / "runner-temp"
        runner_temp.mkdir(parents=True, exist_ok=True)
        recorded_cmds: list[list[str]] = []

        def fake_check_output(cmd: list[str], *args, **kwargs) -> bytes:
            recorded_cmds.append(cmd)
            if cmd[:2] == ["gh", "api"] and cmd[2].endswith(f"/runs/{run_id}"):
                return json.dumps({
                    "status": "completed",
                    "head_sha": "deadbeef",
                    "conclusion": "failure",
                }).encode("utf-8")
            if cmd[:2] == ["gh", "api"] and cmd[2].endswith(f"/runs/{run_id}/artifacts"):
                return json.dumps({
                    "artifacts": [{"name": name, "expired": False} for name in artifact_names]
                }).encode("utf-8")
            raise AssertionError(f"Unexpected check_output call: {cmd}")

        def fake_run(cmd: list[str], *args, **kwargs) -> subprocess.CompletedProcess[str]:
            recorded_cmds.append(cmd)
            stdout = kwargs.get("stdout")
            if stdout is not None:
                stdout.write("{}")
            return subprocess.CompletedProcess(cmd, 0)

        env = {
            "SOURCE_RUN_ID": run_id,
            "GITHUB_REPOSITORY": "davidpovarsky/hanlin-ai",
            "RUNNER_TEMP": str(runner_temp),
            "SELECTED_TESTS": selected_tests,
        }
        old_cwd = Path.cwd()
        try:
            os.chdir(work_dir)
            with patch.dict(os.environ, env, clear=False), \
                 patch.object(inspect_native_result.subprocess, "check_output", side_effect=fake_check_output), \
                 patch.object(inspect_native_result.subprocess, "run", side_effect=fake_run):
                inspect_native_result.main()
        finally:
            os.chdir(old_cwd)

        return work_dir / "native-result-inspection", recorded_cmds

    def test_paired_routing_and_duplicate_metadata_selection(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp = Path(tmp_dir)
            raw = tmp / "runner-temp" / "native-result-44466308930"
            evidence_root = raw / "app-split-evidence"
            paired_dir = evidence_root / "paired-product"
            (paired_dir / "Paired.xcresult").mkdir(parents=True)
            (evidence_root / "acceptance.json").write_text(json.dumps({"source": "root"}), encoding="utf-8")
            (paired_dir / "acceptance.json").write_text(json.dumps({"source": "paired-product"}), encoding="utf-8")

            out, cmds = self._run_main_with_fake_archive(
                tmp=tmp,
                run_id="44466308930",
                selected_tests="AI_HLYUITests/HanlinPairedProductUITests/testPairedFlow(),HanlinShareInboxUITests/testShareInbox",
                artifact_names=["app-split-44466308930"],
            )

            self.assertEqual(json.loads((out / "acceptance.json").read_text(encoding="utf-8")), {"source": "paired-product"})
            origins = json.loads((out / "selected-test-origins.json").read_text(encoding="utf-8"))
            self.assertEqual(
                origins,
                [
                    {"index": 0, "target": "AI_HLYUITests", "test": "HanlinPairedProductUITests/testPairedFlow()", "bundle": "Paired.xcresult"},
                    {"index": 1, "target": "AI_HLYUITests", "test": "HanlinShareInboxUITests/testShareInbox()", "bundle": "Paired.xcresult"},
                ],
            )
            xcrun_cmds = [cmd for cmd in cmds if cmd and cmd[0] == "xcrun"]
            self.assertTrue(xcrun_cmds)
            for cmd in xcrun_cmds:
                path_arg = cmd[cmd.index("--path") + 1]
                self.assertTrue(path_arg.endswith("Paired.xcresult"), cmd)

    def test_ordinary_miniapps_routing_and_duplicate_metadata_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp = Path(tmp_dir)
            raw = tmp / "runner-temp" / "native-result-44466308930"
            evidence_root = raw / "app-split-evidence"
            (evidence_root / "MiniApps.xcresult").mkdir(parents=True)
            (evidence_root / "acceptance.json").write_text(json.dumps({"source": "miniapps"}), encoding="utf-8")

            out, _ = self._run_main_with_fake_archive(
                tmp=tmp,
                run_id="44466308930",
                selected_tests="HanlinMiniAppsUITests/SomeMiniAppUITests/testLaunch",
                artifact_names=["app-split-44466308930"],
            )

            self.assertEqual(json.loads((out / "acceptance.json").read_text(encoding="utf-8")), {"source": "miniapps"})
            origins = json.loads((out / "selected-test-origins.json").read_text(encoding="utf-8"))
            self.assertEqual(
                origins,
                [{"index": 0, "target": "HanlinMiniAppsUITests", "test": "SomeMiniAppUITests/testLaunch()", "bundle": "MiniApps.xcresult"}],
            )

            # Duplicate acceptance.json without paired mode must still fail closed.
            (evidence_root / "nested").mkdir()
            (evidence_root / "nested" / "acceptance.json").write_text("{}", encoding="utf-8")
            with self.assertRaises(AssertionError):
                self._run_main_with_fake_archive(
                    tmp=tmp,
                    run_id="44466308930",
                    selected_tests="HanlinMiniAppsUITests/SomeMiniAppUITests/testLaunch",
                    artifact_names=["app-split-44466308930"],
                )

    def test_ambiguous_and_invalid_paired_selections_fail_closed(self) -> None:
        with self.assertRaises(AssertionError):
            inspect_native_result._resolve_mode(
                "44466308930",
                "AI_HLYUITests/HanlinPairedProductUITests/testA,HanlinMiniAppsUITests/SomeMiniAppUITests/testB",
                {"app-split-44466308930"},
            )
        with self.assertRaises(AssertionError):
            inspect_native_result._resolve_mode(
                "44466308930",
                "HanlinMiniAppsUITests/HanlinPairedProductUITests/testA",
                {"app-split-44466308930"},
            )
        with tempfile.TemporaryDirectory() as tmp_dir:
            raw = Path(tmp_dir)
            (raw / "app-split-evidence" / "MiniApps.xcresult").mkdir(parents=True)
            (raw / "app-split-evidence" / "paired-product" / "Paired.xcresult").mkdir(parents=True)
            with self.assertRaises(AssertionError):
                inspect_native_result._resolve_selections(
                    raw,
                    "AI_HLYUITests/HanlinMorphComposerUITests/testDismissModelPickerKeepsSelectedModelAndDraft",
                    motion=False,
                    split=True,
                    paired=False,
                )


if __name__ == "__main__":
    unittest.main()
