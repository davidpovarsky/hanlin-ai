"""Execute adversarial inventory tests and record their actual result once."""
from pathlib import Path
from collections import Counter
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RecordedResult(unittest.TextTestResult):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.passed = []

    def addSuccess(self, test):
        super().addSuccess(test)
        self.passed.append(test.id())


def main():
    suite = unittest.defaultTestLoader.discover(str(ROOT / "Tests/ProductSplit"), pattern="test_parity_inventory.py")
    result = unittest.TextTestRunner(verbosity=2, resultclass=RecordedResult).run(suite)
    decisions = json.loads((ROOT / "docs/product-split/legacy-ui-decisions.json").read_text(encoding="utf-8"))
    counts = Counter(d["historical_choice"] for d in decisions["decisions"])
    choices_valid = decisions["count"] == 26 and counts == {"KEEP": 14, "RESTORE_TRIAL": 11, "OPEN": 1}
    valid = result.wasSuccessful() and choices_valid
    report = {"status": "EXECUTED_PASS" if valid else "FAILED", "tests_run": result.testsRun,
              "passed": result.passed, "failures": len(result.failures), "errors": len(result.errors),
              "legacy_decision_count": decisions["count"], "legacy_choice_counts": dict(counts),
              "scope": "Inventory validation, not UI or feature behavior acceptance"}
    (ROOT / "docs/product-split/validator-results.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8", newline="\n")
    raise SystemExit(not valid)


if __name__ == "__main__":
    main()
