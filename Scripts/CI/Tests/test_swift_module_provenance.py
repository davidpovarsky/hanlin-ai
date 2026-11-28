"""Failure-only compiler evidence controls; no Xcode, Simulator, or native tests."""
from pathlib import Path
import ast
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import types
import unittest
import uuid
from unittest.mock import Mock, patch


ROOT = Path(__file__).resolve().parents[3]
SCRIPTS = ROOT / "Scripts/ProductSplit"
spec = importlib.util.spec_from_file_location(
    "_swift_module_capture_controls", SCRIPTS / "capture_swift_module_provenance.py")
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)


class SwiftModuleProvenanceTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.derived = self.root / "DerivedData"
        self.evidence = self.root / "evidence"
        self.derived.mkdir()
        self.evidence.mkdir()
        self.counter = 0

    def put(self, relative, data):
        path = self.derived / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def collect(self):
        self.counter += 1
        output = self.evidence / ("collection-" + str(self.counter))
        output.mkdir()
        derived = capture.owned_directory(self.derived)
        evidence = capture.owned_directory(output)
        try:
            report = capture.collect(derived, evidence, time.monotonic() + 10)
        finally:
            os.close(evidence)
            os.close(derived)
        self.assertEqual(json.loads((output / "receipt.json").read_text()), report)
        return report, output

    def command(self, paired):
        # Execute the unchanged actual function AST with portable dependencies.
        # This avoids importing either native runner's unrelated module setup.
        name = "run_paired_acceptance.py" if paired else "run_native_acceptance.py"
        path = SCRIPTS / name
        tree = ast.parse(path.read_text())
        function = next(node for node in tree.body
                        if isinstance(node, ast.FunctionDef) and node.name == "command")
        namespace = {
            "Path": Path, "hashlib": hashlib, "json": json, "os": os,
            "subprocess": subprocess, "sys": sys, "threading": threading,
            "time": time, "uuid": uuid, "ROOT": self.root,
            "EVIDENCE": self.evidence, "EXTRA26_ORIGINAL54_DEADLINE": None,
            "COMMAND_HEARTBEAT_SECONDS": 60,
        }
        exec(compile(ast.Module(body=[function], type_ignores=[]), str(path), "exec"), namespace)
        return namespace

    def test_actual_named_artifacts_maps_hashes_and_deduplicated_blobs(self):
        producer = capture.PRODUCER + "/" + capture.MODULE + ".swiftmodule"
        product = capture.MODULE_DIRECTORIES[1] + "/arm64-apple-ios-simulator.swiftmodule"
        explicit = capture.EXPLICIT_MODULES + "/" + capture.MODULE + "-ABC123.swiftmodule"
        dependency = capture.IMPORTER + "/HanlinMiniApps-dependencies-1.json"
        values = {producer: b"actual producer module", product: b"actual producer module",
                  explicit: b"actual distinct import module",
                  dependency: b'{"swift":{"HanlinPlatformContracts":{"modulePath":"actual/path"}}}'}
        for path, data in values.items():
            self.put(path, data)
        before = {path: capture.identity((self.derived / path).stat()) for path in values}
        report, output = self.collect()
        rows = {row["path"]: row for row in report["files"] if row["status"] == "CAPTURED"}
        self.assertEqual(set(rows), set(values))
        for path, data in values.items():
            self.assertEqual(rows[path]["sha256"], hashlib.sha256(data).hexdigest())
            self.assertEqual((output / rows[path]["blob"]).read_bytes(), data)
            self.assertEqual(capture.identity((self.derived / path).stat()), before[path])
        self.assertEqual(rows[producer]["blob"], rows[product]["blob"])
        self.assertEqual(len(list((output / "blobs").iterdir())), 3)
        self.assertEqual(report["bytesRetained"], sum(len(data) for data in set(values.values())))

    def test_unrelated_source_and_other_module_files_are_never_read(self):
        paths = [
            capture.PRODUCER + "/HanlinShortcutValueCodec.swift",
            capture.PRODUCER + "/unrelated.json",
            capture.EXPLICIT_MODULES + "/OtherModule-A.swiftmodule",
            capture.MODULE_DIRECTORIES[0] + "/README.swift",
        ]
        for path in paths:
            self.put(path, b"unrelated source must remain outside capture")
        report, output = self.collect()
        self.assertFalse(any(row["status"] == "CAPTURED" for row in report["files"]))
        self.assertEqual(report["bytesRead"], 0)
        self.assertEqual(list((output / "blobs").iterdir()), [])

    def test_symlink_file_parent_and_anchor_cannot_escape(self):
        outside = self.root / "outside"
        outside.mkdir()
        secret = outside / "arm64.swiftmodule"
        secret.write_bytes(b"outside bytes")
        target = self.put(capture.PRODUCER + "/" + capture.MODULE + ".swiftmodule", b"remove")
        target.unlink()
        target.symlink_to(secret)
        directory = self.derived / capture.MODULE_DIRECTORIES[0]
        directory.parent.mkdir(parents=True, exist_ok=True)
        directory.symlink_to(outside, target_is_directory=True)
        report, output = self.collect()
        self.assertFalse(any(row["status"] == "CAPTURED" for row in report["files"]))
        self.assertEqual(report["bytesRead"], 0)
        self.assertEqual(secret.read_bytes(), b"outside bytes")
        self.assertEqual(list((output / "blobs").iterdir()), [])
        alias = self.root / "alias"
        alias.symlink_to(self.derived, target_is_directory=True)
        with self.assertRaises(OSError):
            capture.owned_directory(alias)
        descriptor = capture.owned_directory(self.derived)
        try:
            with self.assertRaises(ValueError):
                capture.open_directory("../outside", descriptor)
        finally:
            os.close(descriptor)

    def test_hardlink_fifo_and_directory_are_rejected_without_reading(self):
        hardlink = self.put(capture.PRODUCER + "/" + capture.MODULE + ".swiftmodule", b"one inode")
        os.link(hardlink, self.root / "linked")
        fifo = self.derived / capture.PRODUCER / (capture.MODULE + ".swiftdoc")
        os.mkfifo(fifo)
        (self.derived / capture.PRODUCER / (capture.MODULE + ".swiftinterface")).mkdir()
        report, output = self.collect()
        rows = {row["path"]: row for row in report["files"]}
        for path in (hardlink, fifo, fifo.with_name(capture.MODULE + ".swiftinterface")):
            self.assertEqual(rows[path.relative_to(self.derived).as_posix()]["status"],
                             "REJECTED_FILE_IDENTITY")
        self.assertEqual(report["bytesRead"], 0)
        self.assertEqual(list((output / "blobs").iterdir()), [])

    def test_file_read_and_retained_byte_limits_report_partial_evidence(self):
        paths = [capture.PRODUCER + "/" + capture.MODULE + suffix
                 for suffix in (".swiftmodule", ".swiftdoc")]
        for path, value in zip(paths, (b"abcdef", b"ghijkl")):
            self.put(path, value)
        for constant, value, expected in [
                ("MAX_FILE_BYTES", 5, "FILE_SIZE_LIMIT"),
                ("MAX_READ_BYTES", 6, "TOTAL_READ_LIMIT"),
                ("MAX_RETAINED_BYTES", 6, "TOTAL_RETAINED_LIMIT")]:
            with self.subTest(limit=constant), patch.object(capture, constant, value):
                report, _ = self.collect()
                self.assertEqual(report["status"], "PARTIAL_LIMIT")
                self.assertTrue(any(row["status"] == expected for row in report["files"]))
                self.assertLessEqual(report["bytesRead"], capture.MAX_READ_BYTES)
                self.assertLessEqual(report["bytesRetained"], capture.MAX_RETAINED_BYTES)

    def test_candidate_and_directory_limits_do_not_claim_complete_capture(self):
        self.put(capture.PRODUCER + "/" + capture.MODULE + ".swiftmodule", b"first")
        for index in range(4):
            self.put(capture.EXPLICIT_MODULES + "/" + capture.MODULE + "-" + str(index) + ".swiftmodule",
                     str(index).encode())
        with patch.object(capture, "MAX_CANDIDATES", 1):
            report, _ = self.collect()
            self.assertEqual(len(report["files"]), 1)
            self.assertIn("CANDIDATE_LIMIT", report["limitReasons"])
            self.assertEqual(report["status"], "PARTIAL_LIMIT")
        with patch.object(capture, "MAX_DIRECTORY_ENTRIES", 1):
            report, _ = self.collect()
            self.assertIn("DIRECTORY_ENTRY_LIMIT", report["limitReasons"])
            self.assertTrue(all(row["entriesExamined"] <= 1 for row in report["directories"]))

    def test_file_changed_during_read_is_not_retained(self):
        path = self.put(capture.PRODUCER + "/" + capture.MODULE + ".swiftmodule", b"before")
        original_read = os.read
        changed = False

        def mutate(descriptor, size):
            nonlocal changed
            data = original_read(descriptor, size)
            if not changed:
                changed = True
                path.write_bytes(b"after different size")
            return data

        with patch.object(capture.os, "read", side_effect=mutate):
            report, output = self.collect()
        row = next(row for row in report["files"] if row["path"] == path.relative_to(self.derived).as_posix())
        self.assertEqual(row["status"], "CHANGED_DURING_READ")
        self.assertNotIn("blob", row)
        self.assertEqual(list((output / "blobs").iterdir()), [])

    def test_expired_or_invalid_original_deadline_never_launches_capture(self):
        for deadline in (time.monotonic() - 1, float("inf"), float("nan"), True):
            with self.subTest(deadline=deadline), patch.object(capture.subprocess, "run") as run:
                result = capture.capture_failed_build(
                    self.derived, self.evidence, "build.log", 65, "a" * 64, deadline)
                self.assertEqual(result["status"], "NO_ORIGINAL_BUILD_TIME_REMAINING")
                run.assert_not_called()
                self.assertFalse((self.evidence / "swift-module-provenance").exists())

    def test_preexisting_capture_is_never_overwritten(self):
        output = self.evidence / "swift-module-provenance"
        output.mkdir()
        old = output / "controller.json"
        old.write_bytes(b"prior attempt")
        with patch.object(capture.subprocess, "run") as run:
            result = capture.capture_failed_build(
                self.derived, self.evidence, "build.log", 65, "a" * 64, time.monotonic() + 30)
        self.assertEqual(result["status"], "CAPTURE_UNAVAILABLE")
        run.assert_not_called()
        self.assertEqual(old.read_bytes(), b"prior attempt")

    def test_timeout_preserves_partial_receipt_and_original_failed_exit(self):
        output = self.evidence / "swift-module-provenance"

        def timeout(argv, **options):
            self.assertGreater(options["timeout"], 0)
            self.assertLessEqual(options["timeout"], 0.5)
            self.assertEqual(len(options["pass_fds"]), 2)
            (output / "receipt.json").write_text('{"status":"COLLECTING"}\n')
            raise subprocess.TimeoutExpired(argv, options["timeout"])

        with patch.object(capture.subprocess, "run", side_effect=timeout):
            result = capture.capture_failed_build(
                self.derived, self.evidence, "build.log", 65, "a" * 64, time.monotonic() + 0.5)
        self.assertEqual(result["status"], "COLLECTOR_TIMED_OUT")
        self.assertEqual(result["originalExitCode"], 65)
        self.assertEqual(json.loads((output / "receipt.json").read_text())["status"], "COLLECTING")
        self.assertEqual(json.loads((output / "controller.json").read_text()), result)

    def test_real_portable_child_retains_bound_artifact_without_native_command(self):
        path = self.put(capture.PRODUCER + "/" + capture.MODULE + ".swiftmodule", b"portable owned module")
        result = capture.capture_failed_build(
            self.derived, self.evidence, "build.log", 65, "a" * 64, time.monotonic() + 10)
        self.assertEqual(result["status"], "COLLECTOR_EXITED")
        self.assertEqual(result["childExitCode"], 0)
        report = json.loads((self.evidence / "swift-module-provenance/receipt.json").read_text())
        row = next(row for row in report["files"] if row["status"] == "CAPTURED")
        self.assertEqual(row["sha256"], hashlib.sha256(path.read_bytes()).hexdigest())
        self.assertLessEqual(result["childTimeoutSeconds"], 8)

    def test_paired_failed_build_preserves_actual_error_log_and_journal_when_capture_fails(self):
        namespace = self.command(paired=True)
        argv = [sys.executable, "-c", "print('original compiler error'); raise SystemExit(65)"]
        with patch.dict(sys.modules, {"capture_swift_module_provenance": capture}), \
                patch.dict(os.environ, {"SPLIT_DERIVED_DATA": str(self.derived)}), \
                patch.object(capture, "capture_failed_build", side_effect=OSError("unavailable")) as collect:
            with self.assertRaisesRegex(RuntimeError, "exit 65; inspect mini-build.log"):
                namespace["command"](argv, "mini-build.log", timeout=2)
        self.assertEqual(collect.call_count, 1)
        self.assertEqual((self.evidence / "mini-build.log").read_bytes(), b"original compiler error\n")
        record = json.loads((self.evidence / "commands.jsonl").read_text())
        self.assertEqual(record["argv"], argv)
        self.assertEqual(record["exit"], 65)
        event = json.loads((self.evidence / "active-command.json").read_text())
        self.assertEqual((event["status"], event["completion_recorded"], event["exit"]),
                         ("completed", True, 65))
        self.assertEqual(event["timeout"], 2)

    def test_success_other_phase_and_allowed_paired_failure_never_capture(self):
        namespace = self.command(paired=True)
        with patch.dict(sys.modules, {"capture_swift_module_provenance": capture}), \
                patch.object(capture, "capture_failed_build") as collect:
            namespace["command"]([sys.executable, "-c", "pass"], "mini-build.log", timeout=2)
            with self.assertRaisesRegex(RuntimeError, "exit 65; inspect ai-build.log"):
                namespace["command"]([sys.executable, "-c", "raise SystemExit(65)"], "ai-build.log", timeout=2)
            namespace["command"]([sys.executable, "-c", "raise SystemExit(65)"],
                                 "mini-build.log", timeout=2, allow_failure=True)
        collect.assert_not_called()

    def test_standalone_error_and_timeout_keep_original_exception_and_output(self):
        namespace = self.command(paired=False)
        with patch.dict(sys.modules, {"capture_swift_module_provenance": capture}), \
                patch.dict(os.environ, {"SPLIT_DERIVED_DATA": str(self.derived)}), \
                patch.object(capture, "capture_failed_build", side_effect=OSError("unavailable")):
            with self.assertRaisesRegex(RuntimeError, "exit 65; see build.log"):
                namespace["command"](
                    [sys.executable, "-c", "print('original error'); raise SystemExit(65)"],
                    "build.log", timeout=2)
            self.assertEqual((self.evidence / "build.log").read_bytes(), b"original error\n")
            original = subprocess.TimeoutExpired(["original"], 2, output=b"partial original error")
            namespace["subprocess"] = types.SimpleNamespace(
                run=Mock(side_effect=original), PIPE=subprocess.PIPE, STDOUT=subprocess.STDOUT,
                TimeoutExpired=subprocess.TimeoutExpired)
            with self.assertRaises(subprocess.TimeoutExpired) as raised:
                namespace["command"](["original"], "build.log", timeout=2)
        self.assertIs(raised.exception, original)
        self.assertEqual((self.evidence / "build.log").read_bytes(), b"partial original error")
        records = [json.loads(line) for line in (self.evidence / "commands.jsonl").read_text().splitlines()]
        self.assertEqual([record["exit"] for record in records], [65, -1])

    def test_paired_capture_remains_inside_original54_preparation_inclusive_deadline(self):
        namespace = self.command(paired=True)
        clock = types.SimpleNamespace(limit=Mock(return_value=2), remaining=Mock(return_value=-1))
        namespace["EXTRA26_ORIGINAL54_DEADLINE"] = clock
        with patch.dict(sys.modules, {"capture_swift_module_provenance": capture}), \
                patch.dict(os.environ, {"SPLIT_DERIVED_DATA": str(self.derived)}), \
                patch.object(capture, "capture_failed_build", wraps=capture.capture_failed_build) as collect:
            with self.assertRaisesRegex(RuntimeError, "exit 65; inspect mini-build.log"):
                namespace["command"]([sys.executable, "-c", "raise SystemExit(65)"],
                                     "mini-build.log", timeout=3600)
        clock.limit.assert_called_once_with("mini-build.log", 3600)
        clock.remaining.assert_called_once_with()
        self.assertLess(collect.call_args.args[-1], time.monotonic())
        self.assertFalse((self.evidence / "swift-module-provenance").exists())


if __name__ == "__main__":
    unittest.main()
