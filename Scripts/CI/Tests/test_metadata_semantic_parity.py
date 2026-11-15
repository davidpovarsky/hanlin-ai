import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("metadata_semantic_parity", Path(__file__).resolve().parents[2] / "NativeScript/metadata_semantic_parity.py")
parity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(parity)


class MetadataSemanticParityTests(unittest.TestCase):
    def test_generic_refinement_preserves_the_existing_protocol_bound(self):
        original = {"Type": "Id", "WithProtocols": ["NSCopying"]}
        candidate = {"Type": "TypeArgument", "Name": "KeyType", "UnderlyingType": {"Type": "Id", "WithProtocols": []}, "WithProtocols": ["NSCopying"]}
        self.assertEqual(parity.compare_models(original, candidate)["status"], "EXECUTED_PASS")
        candidate["WithProtocols"] = []
        self.assertEqual(parity.compare_models(original, candidate)["status"], "FAILED")

    def test_added_method_is_retained_but_cannot_hide_a_missing_selector(self):
        original = {"InstanceMethods": [{"Name": "existing:", "Signature": ["Int", "Id"]}]}
        candidate = {"InstanceMethods": [{"Name": "added", "Signature": ["Void"]}, *original["InstanceMethods"]]}
        report = parity.compare_models(original, candidate)
        self.assertEqual(report["status"], "EXECUTED_PASS")
        self.assertEqual(report["additions"][0]["path"], "/InstanceMethods/added")
        candidate["InstanceMethods"].pop()
        self.assertEqual(parity.compare_models(original, candidate)["status"], "FAILED")

    def test_signature_order_width_and_record_layout_must_remain_exact(self):
        original = {"Signature": ["Int", "Id"], "Fields": [{"name": "x", "offset": 0}]}
        for candidate in [{**original, "Signature": ["Id", "Int"]}, {**original, "Signature": ["Long", "Id"]},
                          {**original, "Fields": [{"name": "x", "offset": 8}]}]:
            self.assertEqual(parity.compare_models(original, candidate)["status"], "FAILED")

    def test_duplicate_selector_or_unreviewed_generic_field_fails_closed(self):
        original = {"Items": [{"Name": "NSObject"}]}
        self.assertEqual(parity.compare_models(original, {"Items": original["Items"] * 2})["status"], "FAILED")
        with self.assertRaises(ValueError):
            parity.erase_generic_encoding({"Type": "TypeArgument", "Name": "T", "UnderlyingType": {"Type": "Id"}, "unknownABI": True})
