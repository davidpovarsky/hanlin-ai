from __future__ import annotations

from pathlib import Path
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
WORKFLOW_PATH = REPOSITORY_ROOT / ".github/workflows/build-ios26-unsigned-ipa.yml"
SIMULATOR_LIVENESS_CHECK = (
    'xcrun simctl spawn "$SIMULATOR_UDID" /bin/kill -0 "$APP_PID"'
)


class ShellWorkflowSourceTests(unittest.TestCase):
    def test_app_liveness_is_checked_inside_the_simulator(self) -> None:
        source = WORKFLOW_PATH.read_text(encoding="utf-8")
        liveness_lines = [
            line.strip()
            for line in source.splitlines()
            if '/bin/kill -0 "$APP_PID"' in line
        ]

        self.assertEqual(len(liveness_lines), 3)
        self.assertTrue(
            all(SIMULATOR_LIVENESS_CHECK in line for line in liveness_lines),
            "Simulator PIDs must not be checked from the macOS host namespace",
        )


if __name__ == "__main__":
    unittest.main()
