"""Pure admission controls; synthetic bytes are never native/producer evidence."""
from contextlib import ExitStack
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "ProductSplit"))
import prepare_widget_fixtures as producer
import observe_widget_state as reader

ORIGINAL_SOURCE_PATHS = (
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests.swift",
    "Scripts/ProductSplit/run_paired_acceptance.py",
    "Scripts/ProductSplit/observe_shortcut_surfaces.py",
    "Scripts/ProductSplit/observe_widget_state.py",
    "Scripts/CI/Tests/test_widget_state_observer.py",
    "Fixtures/Widgets/Hanlin-Expo-Widget-Interactive-Matrix.hanlinExpo",
    "Fixtures/Widgets/SHA256.json",
)


class WidgetFixtureProducerControls(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.source = "a" * 40
        self.evidence = self.root / "build/app-split-evidence/widget-fixture-producer"
        self.git = {}
        for name in set(producer.CODE_INPUTS) | set(ORIGINAL_SOURCE_PATHS[:5]):
            self.write(name, ("unchanged source " + name + "\n").encode())
            self.git[name] = (self.root / name).read_bytes()
        archives = ["Hanlin-Expo-Widget-Counter.hanlinExpo", "Hanlin-Expo-Widget-Visuals.hanlinExpo",
                    "Hanlin-ScriptWidget-Dashboard.scripting", "Hanlin-ScriptWidget-Actions.scripting",
                    "Hanlin-Mixed-Native-Widget.hanlinExpo", "Hanlin-Widget-Legacy-Regression.scripting",
                    "Hanlin-Widget-Invalid-Cases.hanlinExpo", "Hanlin-Expo-Widget-Interactive-Matrix.hanlinExpo"]
        self.git[producer.MANIFEST] = json.dumps([{"archive": name} for name in archives]).encode()
        self.authored = {str(Path(mirror) / name): ("authored original recipe " + name).encode()
                         for name in archives for mirror in producer.MIRRORS}
        self.authored[producer.MANIFEST] = self.git[producer.MANIFEST]
        for name, raw in self.authored.items():
            self.write(name, raw)
            self.git.setdefault(name, b"older Git archive with original selected version")
        self.expected = {name: {"sha256": producer.digest(raw), "bytes": len(raw)}
                         for name, raw in self.authored.items()}
        versions = {"@expo/ui": "58.0.30", "expo-widgets": "58.0.30", "react": "19.3.0"}
        self.write_json(producer.EFFECTIVE_INPUTS[0], {"dependencies": versions})
        self.write_json(producer.EFFECTIVE_INPUTS[1], {"packages": {"": {"dependencies": versions},
                        **{"node_modules/" + name: {"version": value} for name, value in versions.items()}}})
        resolved = {"schemaVersion": 1, "versions": {"expo": versions}}
        self.write_json(producer.EFFECTIVE_INPUTS[2], resolved)
        self.write_json(producer.EFFECTIVE_INPUTS[3], {**resolved, "status": "applied-awaiting-native-build",
                        "packageLockSHA256": {"Expo": producer.digest((self.root / producer.EFFECTIVE_INPUTS[1]).read_bytes())}})
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.dict(os.environ, {"GITHUB_ACTIONS": "true", "GITHUB_SHA": self.source,
            "GITHUB_WORKSPACE": str(self.root), "GITHUB_RUN_ID": "123", "GITHUB_RUN_ATTEMPT": "2",
            "SPLIT_EVIDENCE": str(self.evidence.parent), producer.RECEIPT_ENV: str(self.evidence / "receipt.json")}))
        self.stack.enter_context(patch.object(producer, "git_bytes", side_effect=lambda root, source, name: self.git[name]))
        self.stack.enter_context(patch.object(producer, "source_head"))
        self.node = {"path": "/synthetic-owned-node", "version": "v24.5.0", "sha256": "b" * 64, "bytes": 100}
        self.stack.enter_context(patch.object(producer, "node_identity", return_value=self.node))
        self.recipe = self.stack.enter_context(patch.object(producer, "recipe_identity", side_effect=lambda *args: copy.deepcopy(self.expected)))
        self.run = self.stack.enter_context(patch.object(producer.subprocess, "run", side_effect=self.original_producer))
        producer.prepare(self.root, self.source, self.evidence)
        self.valid = (self.evidence / "receipt.json").read_bytes()

    def write(self, name, raw):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(raw)

    def write_json(self, name, value):
        self.write(name, (json.dumps(value, sort_keys=True) + "\n").encode())

    def original_producer(self, argv, *, cwd, stdout, stderr, timeout):
        self.assertEqual(argv, ["node", "Scripts/Widgets/build-sample-packages.mjs"])
        self.assertEqual(cwd, self.root)
        self.assertEqual(timeout, 60)
        for name, raw in self.authored.items():
            self.write(name, raw)
        stdout.write(b"synthetic original producer output\n")
        return subprocess.CompletedProcess(argv, 0)

    def receipt(self, change):
        value = json.loads(self.valid)
        change(value)
        (self.evidence / "receipt.json").write_text(json.dumps(value) + "\n")

    def validate(self):
        return producer.validate_receipt(self.root, self.source)

    def test_original_command_once_and_all_twenty_five_outputs_remain_bound(self):
        self.assertEqual(self.run.call_count, 1)
        self.assertEqual(len(self.validate()), 25)
        self.assertEqual(self.run.call_count, 1, "Read-only admission must not invoke the producer again")
        self.assertEqual(self.recipe.call_count, 2)

    def test_source_identity_preserves_seven_entries_and_all_five_git_code_checks(self):
        def git_read(argv, **kwargs):
            return (self.source + "\n").encode() if argv[-1] == "HEAD" else self.git[argv[-1].split(":", 1)[1]]
        with patch.object(reader.subprocess, "check_output", side_effect=git_read):
            self.assertEqual(reader.SOURCE_PATHS, ORIGINAL_SOURCE_PATHS)
            self.assertEqual(set(reader.source_identity(self.root, self.source)), set(ORIGINAL_SOURCE_PATHS))
            for name in ORIGINAL_SOURCE_PATHS[:5]:
                with self.subTest(name=name):
                    self.write(name, self.git[name] + b"unapproved edit")
                    with self.assertRaises(reader.original.ObservationError):
                        reader.source_identity(self.root, self.source)
                    self.write(name, self.git[name])

    def test_missing_wrong_path_and_symbolic_receipt_cannot_admit(self):
        for value in ("", str(self.evidence / "unrelated.json")):
            with patch.dict(os.environ, {producer.RECEIPT_ENV: value}), self.assertRaises(producer.FixturePreparationError):
                self.validate()
        path = self.evidence / "receipt.json"
        path.rename(self.evidence / "retained.json")
        path.symlink_to(self.evidence / "retained.json")
        with self.assertRaises(producer.FixturePreparationError):
            self.validate()

    def test_wrong_source_run_attempt_and_typed_schema_are_rejected(self):
        for key, value in [("sourceSHA", "c" * 40), ("schema", True),
                           ("github", {"runID": "124", "runAttempt": "2"}),
                           ("github", {"runID": "123", "runAttempt": "1"})]:
            with self.subTest(key=key, value=value):
                self.receipt(lambda doc: doc.update({key: value}))
                with self.assertRaises(producer.FixturePreparationError):
                    self.validate()

    def test_original_execution_times_exit_command_and_before_after_are_required(self):
        changes = [lambda d: d["producer"].update(exitCode=1),
                   lambda d: d["producer"].update(exitCode=False),
                   lambda d: d["producer"].update(argv=["node", "other.mjs"]),
                   lambda d: d.update(startedAt=d["finishedAt"] + 1),
                   lambda d: d.update(finishedAt=time.time() - 210 * 60 - 1),
                   lambda d: d.update(elapsedSeconds=float("nan")),
                   lambda d: d["inputsAfter"]["node"].update(sha256="d" * 64)]
        for index, change in enumerate(changes):
            with self.subTest(index=index):
                self.receipt(change)
                with self.assertRaises(producer.FixturePreparationError):
                    self.validate()

    def test_producer_helper_samples_zip_and_resolver_code_cannot_be_dirty(self):
        for name in producer.CODE_INPUTS:
            with self.subTest(name=name):
                self.write(name, self.git[name] + b"dirty")
                with self.assertRaises(producer.FixturePreparationError):
                    self.validate()
                self.write(name, self.git[name])

    def test_actual_package_lock_and_resolver_versions_must_agree(self):
        for index, mutate in [(0, lambda d: d["dependencies"].update({"@expo/ui": "58.0.29"})),
                              (1, lambda d: d["packages"]["node_modules/expo-widgets"].update(version="58.0.29")),
                              (2, lambda d: d["versions"]["expo"].update(react="19.2.0")),
                              (3, lambda d: d.update(status="failed-inputs-restored"))]:
            name = producer.EFFECTIVE_INPUTS[index]
            before = (self.root / name).read_bytes()
            value = json.loads(before)
            mutate(value)
            self.write_json(name, value)
            with self.subTest(name=name), self.assertRaises(producer.FixturePreparationError):
                self.validate()
            self.write(name, before)

    def test_self_consistent_archive_manifest_and_receipt_tampering_fails_authored_recipe(self):
        for name, raw in self.authored.items():
            self.write(name, raw + b"unauthored bytes")
        forged = producer.output_identity(self.root, self.expected)
        self.receipt(lambda doc: doc.update(outputs=forged))
        with self.assertRaisesRegex(producer.FixturePreparationError, "authored recipe"):
            self.validate()

    def test_missing_extra_or_typed_output_and_changed_log_cannot_pass(self):
        first = next(iter(self.expected))
        changes = [lambda d: d["outputs"].pop(first),
                   lambda d: d["outputs"].update({"unexpected": self.expected[first]}),
                   lambda d: d["outputs"][first].update(bytes=float(self.expected[first]["bytes"])),
                   lambda d: d["stderr"].update(bytes=False)]
        for index, change in enumerate(changes):
            self.receipt(change)
            with self.subTest(index=index), self.assertRaises(producer.FixturePreparationError):
                self.validate()
        (self.evidence / "receipt.json").write_bytes(self.valid)
        (self.evidence / "producer.stdout.log").write_bytes(b"changed")
        with self.assertRaises(producer.FixturePreparationError):
            self.validate()

    def test_current_output_symbolic_or_hard_link_is_rejected(self):
        first = self.root / next(iter(self.expected))
        saved = first.with_name("retained-owned-test-input")
        first.rename(saved)
        first.symlink_to(saved)
        with self.assertRaises(producer.FixturePreparationError):
            self.validate()
        first.unlink()
        os.link(saved, first)
        with self.assertRaises(producer.FixturePreparationError):
            self.validate()

    def test_failed_original_command_preserves_logs_without_success_receipt(self):
        self.evidence.rename(self.evidence.with_name("prior-owned-test-evidence"))
        def fail(argv, **kwargs):
            kwargs["stderr"].write(b"actual simulated producer failure\n")
            return subprocess.CompletedProcess(argv, 7)
        self.run.side_effect = fail
        with self.assertRaises(producer.FixturePreparationError):
            producer.prepare(self.root, self.source, self.evidence)
        self.assertFalse((self.evidence / "receipt.json").exists())
        self.assertEqual(json.loads((self.evidence / "failure.json").read_text())["status"], "FAILED")
        self.assertIn(b"producer failure", (self.evidence / "producer.stderr.log").read_bytes())

    def test_input_mutation_during_original_producer_never_publishes_success(self):
        self.evidence.rename(self.evidence.with_name("prior-owned-test-evidence"))
        def mutate(argv, **kwargs):
            result = self.original_producer(argv, **kwargs)
            name = "Scripts/Widgets/samples.mjs"
            self.write(name, self.git[name] + b"changed during producer")
            return result
        self.run.side_effect = mutate
        with self.assertRaises(producer.FixturePreparationError):
            producer.prepare(self.root, self.source, self.evidence)
        self.assertFalse((self.evidence / "receipt.json").exists())
        self.assertTrue((self.evidence / "failure.json").is_file())


if __name__ == "__main__":
    unittest.main()
