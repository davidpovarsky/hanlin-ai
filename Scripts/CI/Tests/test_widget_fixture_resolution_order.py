"""Keep native Widget fixtures on the exact graph resolved for each original build."""
from copy import deepcopy
from pathlib import Path
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/build-ios26-unsigned-ipa.yml"
JOBS = ("build-ios26-unsigned-ipa", "full-app-simulator-smoke")
PRODUCER = "node Scripts/Widgets/build-sample-packages.mjs"
RESOLVER = "node Scripts/MiniApps/resolve-upstreams.mjs --apply"
CAPTURE = 'git diff --binary > "$LOG_DIR/miniapp-upstream-inputs.patch"'


def validate_fixture_order(document):
    for job in JOBS:
        steps = document["jobs"][job]["steps"]
        matches = [(index, step) for index, step in enumerate(steps)
                   if RESOLVER in step.get("run", "")]
        assert len(matches) == 1, (job, "one original resolver step is required")
        step_index, step = matches[0]
        lines = [line.strip() for line in step["run"].splitlines() if line.strip()]
        resolver = [index for index, line in enumerate(lines) if line.startswith(RESOLVER)]
        producer = [index for index, line in enumerate(lines) if line == PRODUCER]
        assert len(resolver) == len(producer) == 1, (job, "one resolver and one producer")
        assert producer[0] == resolver[0] + 1, (job, "resolve successfully before producing fixtures")
        assert lines.index("set -euo pipefail") < resolver[0], (job, "resolver failure must stop the step")
        captures = [index for index, line in enumerate(lines)
                    if line.startswith("trap ") and line.endswith(" EXIT") and CAPTURE in line]
        assert len(captures) == 1 and captures[0] < resolver[0], (job, "capture all generated binary changes on exit")
        upload = steps[step_index + 1]
        assert upload["name"] == "Preserve current original MiniApp build inputs"
        assert upload["if"] == "always()"
        assert "${{ env.LOG_DIR }}/miniapp-upstream-*" in upload["with"]["path"].splitlines()


class WidgetFixtureResolutionOrderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflow = yaml.safe_load(WORKFLOW.read_text())

    def test_both_original_builds_produce_widgets_inside_the_recorded_resolution_step(self):
        validate_fixture_order(self.workflow)

    def test_stale_order_missing_producer_and_missing_binary_capture_are_rejected(self):
        for job in JOBS:
            for defect in ("before_resolution", "missing_producer", "missing_capture", "missing_upload"):
                candidate = deepcopy(self.workflow)
                steps = candidate["jobs"][job]["steps"]
                index = next(i for i, step in enumerate(steps) if RESOLVER in step.get("run", ""))
                step = steps[index]
                lines = step["run"].splitlines()
                if defect == "before_resolution":
                    lines.remove(PRODUCER)
                    resolver = next(i for i, line in enumerate(lines) if line.startswith(RESOLVER))
                    lines.insert(resolver, PRODUCER)
                elif defect == "missing_producer":
                    lines.remove(PRODUCER)
                elif defect == "missing_capture":
                    lines = [line for line in lines if CAPTURE not in line]
                else:
                    steps[index + 1]["with"]["path"] = "build/acceptance/miniapp-upstreams\n"
                step["run"] = "\n".join(lines) + "\n"
                with self.subTest(job=job, defect=defect):
                    with self.assertRaises(AssertionError):
                        validate_fixture_order(candidate)


if __name__ == "__main__":
    unittest.main()
