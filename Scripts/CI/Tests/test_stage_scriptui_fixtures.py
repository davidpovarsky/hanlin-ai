from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import MagicMock, patch

SCRIPT_PATH = Path(__file__).parents[1] / "stage_scriptui_fixtures.py"
SPEC = importlib.util.spec_from_file_location("stage_scriptui_fixtures", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
stager = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(stager)


class StageScriptUIFixturesTests(unittest.TestCase):
    def test_required_install_or_container_failure_fails_closed(self) -> None:
        for failed_command, expected in [("install", "INSTALL_FAILED"), ("get_app_container", "CONTAINER_NOT_FOUND")]:
            with self.subTest(command=failed_command), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                app = root / "Host.app"
                app.mkdir()
                calls = []

                def runner(cmd, **kwargs):
                    calls.append(cmd)
                    code = 124 if failed_command in cmd else 0
                    return subprocess.CompletedProcess(cmd, code, "", "timeout" if code else "")

                result = stager.stage_fixtures("sim", app_path=app, fixtures_dir=root / "Fixtures", runner=runner)
                self.assertFalse(result["staged"])
                self.assertEqual(result["status"], expected)
                self.assertFalse(any("com.apple.DocumentsApp" in cmd for cmd in calls))

    def test_optional_files_timeout_preserves_required_staging(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            container = root / "AppData"
            container.mkdir()
            calls = []

            def runner(cmd, **kwargs):
                calls.append((cmd, kwargs))
                if "com.apple.DocumentsApp" in cmd:
                    self.assertEqual(kwargs["timeout_seconds"], 5.0)
                    return subprocess.CompletedProcess(cmd, 124, "", "timeout")
                self.assertEqual(kwargs["timeout_seconds"], 20.0)
                return subprocess.CompletedProcess(cmd, 0, str(container), "")

            result = stager.stage_fixtures("sim", fixtures_dir=root / "Fixtures", runner=runner)
            self.assertTrue(result["staged"])
            self.assertEqual(result["status"], "SUCCESS")
            self.assertTrue((container / "Documents" / "ExpoSwiftUIProbeA.hanlinExpo").is_file())
            self.assertEqual(len(calls), 2)
            self.assertIn("optional", result["logs"][-1])

    def test_shared_bounded_runner_converts_timeout_to_failure(self) -> None:
        command = ["xcrun", "simctl", "get_app_container"]
        with patch.object(subprocess, "run", side_effect=subprocess.TimeoutExpired(command, 5)) as execute:
            result = stager.run_bounded(command, timeout_seconds=5.0)
        self.assertEqual(result.returncode, 124)
        self.assertEqual(execute.call_args.kwargs["timeout"], 5.0)

    def test_missing_required_bundle_or_fixtures_never_succeeds(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            runner = MagicMock()
            result = stager.stage_fixtures("sim", app_path=root / "Missing.app", fixtures_dir=root / "Fixtures", runner=runner)
            self.assertEqual(result["status"], "INSTALL_FAILED")
            with patch.object(stager, "create_fixtures", return_value=[]), patch.object(Path, "glob", return_value=[]):
                result = stager.stage_fixtures("sim", fixtures_dir=root / "Empty", runner=runner)
            self.assertEqual(result["status"], "FIXTURES_MISSING")
            runner.assert_not_called()

    def test_dry_run_mode(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            fix_dir = tmp_path / "Fixtures"
            log_file = tmp_path / "stage.log"

            res = stager.stage_fixtures(
                simulator_udid="SIM-1234",
                fixtures_dir=fix_dir,
                log_file=log_file,
                dry_run=True,
            )

            self.assertTrue(res["staged"])
            self.assertTrue(res["dry_run"])
            self.assertTrue(log_file.exists())
            log_text = log_file.read_text(encoding="utf-8")
            self.assertIn("Dry run enabled", log_text)
            self.assertTrue((fix_dir / "HanlinScriptUIValid.scripting").exists())
            self.assertTrue((fix_dir / "HanlinScriptUIMalformed.scripting").exists())
            self.assertTrue((fix_dir / "HanlinScriptUIAppB.scripting").exists())

    def test_mocked_simctl_execution_stages_into_app_container(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            fix_dir = tmp_path / "Fixtures"
            app_dir = tmp_path / "TestApp.app"
            app_dir.mkdir(parents=True, exist_ok=True)
            mock_app_container = tmp_path / "SimulatorData" / "Containers" / "App"
            mock_app_container.mkdir(parents=True, exist_ok=True)
            mock_files_container = tmp_path / "SimulatorData" / "Containers" / "Files"
            mock_files_container.mkdir(parents=True, exist_ok=True)

            def mock_runner(cmd, **kwargs):
                if "install" in cmd:
                    self.assertEqual(kwargs["timeout_seconds"], 180.0)
                mock = MagicMock()
                mock.returncode = 0
                if "get_app_container" in cmd:
                    if "com.apple.DocumentsApp" in cmd:
                        mock.stdout = str(mock_files_container)
                    else:
                        mock.stdout = str(mock_app_container)
                else:
                    mock.stdout = ""
                mock.stderr = ""
                return mock

            res = stager.stage_fixtures(
                simulator_udid="SIM-UDID-5678",
                app_path=app_dir,
                bundle_id="com.davidpovarsky.AI-HLY",
                fixtures_dir=fix_dir,
                runner=mock_runner,
            )

            self.assertTrue(res["staged"])
            self.assertEqual(res["app_container"], str(mock_app_container))

            # Verify files staged in app container Documents
            app_docs = mock_app_container / "Documents"
            self.assertTrue(app_docs.exists())
            self.assertTrue((app_docs / "HanlinScriptUIValid.scripting").exists())
            self.assertTrue((app_docs / "HanlinScriptUIMalformed.scripting").exists())
            self.assertTrue((app_docs / "HanlinScriptUIAppB.scripting").exists())
            self.assertTrue((app_docs / "ExpoSwiftUIProbeA.hanlinExpo").exists())
            self.assertTrue((app_docs / "ExpoSwiftUIProbeB.hanlinExpo").exists())
            self.assertTrue((app_docs / "ExpoSwiftUIMalformed.hanlinExpo").exists())
            for name in ("Hanlin-ScriptWidget-Actions.scripting", "Hanlin-ScriptWidget-Dashboard.scripting", "Hanlin-Widget-Legacy-Regression.scripting"):
                self.assertEqual((app_docs / name).read_bytes(), (SCRIPT_PATH.parents[2] / "AI_HLYUITests" / "Fixtures" / name).read_bytes())

            # Verify files staged in Files container Documents
            files_docs = mock_files_container / "Documents"
            self.assertTrue(files_docs.exists())
            self.assertTrue((files_docs / "HanlinScriptUIValid.scripting").exists())
            self.assertTrue((files_docs / "ExpoSwiftUIProbeA.hanlinExpo").exists())
            self.assertTrue((files_docs / "Hanlin-ScriptWidget-Actions.scripting").exists())


if __name__ == "__main__":
    unittest.main()
