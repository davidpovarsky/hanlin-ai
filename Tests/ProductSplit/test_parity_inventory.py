import copy
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("parity_inventory", ROOT / "Scripts/ProductSplit/parity_inventory.py")
inventory = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(inventory)


class ParityValidatorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import json
        cls.document = json.loads((ROOT / "docs/product-split/feature-delta-278.json").read_text(encoding="utf-8"))
        _, cls.original = inventory.historical()

    def validate_mutation(self, mutation):
        value = copy.deepcopy(self.document)
        mutation(value)
        self.assertTrue(inventory.validate(value, self.original))

    def test_complete_inventory(self):
        self.assertEqual([], inventory.validate(self.document, self.original))

    def test_missing_id_rejected(self):
        self.validate_mutation(lambda v: v["rows"].pop())

    def test_duplicate_id_rejected(self):
        self.validate_mutation(lambda v: v["rows"].append(v["rows"][0]))

    def test_unexpected_id_rejected(self):
        self.validate_mutation(lambda v: v["rows"][0].update(id="UNKNOWN-01"))

    def test_unproven_pass_rejected(self):
        self.validate_mutation(lambda v: v["rows"][0].update(acceptance_status="EXECUTED_PASS"))

    def test_missing_owner_or_evidence_rejected(self):
        self.validate_mutation(lambda v: v["rows"][0].update(owner_target="", source_evidence=[]))

    def test_changed_historical_description_rejected(self):
        self.validate_mutation(lambda v: v["rows"][0].update(historical_feature="invented"))

    def test_wrong_source_digest_rejected(self):
        self.validate_mutation(lambda v: v["rows"][0]["source_evidence"][0].update(sha256="0" * 64))

    def test_missing_required_status_fields_rejected(self):
        self.validate_mutation(lambda v: v["rows"][0].update(migration="", permissions="", unresolved_decision=""))

    def test_target_revision_must_be_exact_commit(self):
        self.validate_mutation(lambda v: v.update(target_revision="HEAD"))

    def test_target_project_fingerprint_cannot_be_changed(self):
        self.validate_mutation(lambda v: v["target_project"].update(sha256="0" * 64))

    def test_source_anchor_must_match_selected_target_revision(self):
        self.validate_mutation(lambda v: v["rows"][0]["source_evidence"][0].update(revision="0" * 40))


if __name__ == "__main__":
    unittest.main()
