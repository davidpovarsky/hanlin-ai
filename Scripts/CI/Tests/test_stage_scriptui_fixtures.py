from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import MagicMock

SCRIPT_PATH = Path(__file__).parents[1] / "stage_scriptui_fixtures.py"
SPEC = importlib.util.spec_from_file_location("stage_scriptui_fixtures", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
stager = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(stager)


class StageScriptUIFixturesTests(unittest.TestCase):
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

            # Verify files staged in Files container Documents
            files_docs = mock_files_container / "Documents"
            self.assertTrue(files_docs.exists())
            self.assertTrue((files_docs / "HanlinScriptUIValid.scripting").exists())


if __name__ == "__main__":
    unittest.main()
