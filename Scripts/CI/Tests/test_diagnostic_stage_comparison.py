import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("compare_chat_stages", Path(__file__).parents[2] / "Diagnostics" / "compare_chat_stages.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class StageComparisonTests(unittest.TestCase):
    def test_unicode_first_divergence_uses_both_scalar_and_byte_offsets(self):
        result = module.compare_text("ש🙂abc", "ש🙂a�c")
        self.assertEqual(result["status"], "DIVERGED")
        self.assertEqual(result["firstDifferentScalar"], 3)
        self.assertEqual(result["firstDifferentUTF8Byte"], 7)

    def test_prefix_loss_is_not_a_match(self):
        self.assertEqual(module.compare_text("hello", "hell")["firstDifferentScalar"], 4)

    def test_empty_pair_matches_without_inventing_an_answer(self):
        self.assertEqual(module.compare_text("", "")["status"], "MATCH")

    def test_truncation_is_not_misreported_as_provider_corruption(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "manifest.json"
            manifest.write_text(json.dumps({"truncated": True, "droppedByteCount": 3}), encoding="utf-8")
            self.assertEqual(module.compare_session(manifest)["status"], "INCOMPLETE_CAPTURE")

    def test_manifest_path_traversal_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "manifest.json"
            manifest.write_text(json.dumps({"snapshotsFile": "../outside.json"}), encoding="utf-8")
            with self.assertRaises(ValueError):
                module.compare_session(manifest)

    def test_actual_correlation_identifies_the_first_changed_layer_without_leaking_text(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "manifest.json").write_text(json.dumps({"runID": "run", "snapshotsFile": "snapshots.json", "eventsFile": "events.jsonl"}), encoding="utf-8")
            (root / "events.jsonl").write_text(json.dumps({"stage": "transport.request", "attemptID": "attempt", "roundID": "round"}) + "\n", encoding="utf-8")
            snapshots = {"attempt.response.choices.0.delta.content": "PRIVATE_SOURCE_שלום🙂",
                         "round.SwiftAISDK.content": "PRIVATE_SOURCE_שלום�",
                         "round.StreamData.content": "PRIVATE_SOURCE_שלום�"}
            (root / "snapshots.json").write_text(json.dumps(snapshots), encoding="utf-8")
            result = module.compare_session(root / "manifest.json")
            self.assertEqual(result["status"], "DIVERGED")
            self.assertEqual(result["rounds"][0]["firstDivergence"]["toStage"], "round.SwiftAISDK.content")
            self.assertNotIn("PRIVATE_SOURCE", json.dumps(result))


if __name__ == "__main__":
    unittest.main()
