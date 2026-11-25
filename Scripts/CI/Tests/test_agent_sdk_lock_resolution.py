"""Bounded fixtures for the original lock-producer guard; no Swift or Apple tools run."""
from __future__ import annotations

import contextlib
import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "Scripts/CI/IntegrationValidation/resolve_agent_sdk_locks.sh"
APP_LOCK = "AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
PACKAGES = (
    "HanlinPlatform", "HanlinAgentSDK", "HanlinParityMiniApp",
    "HanlinTextStudioMiniApp", "HanlinSefariaMiniApp", "HanlinWikipediaMiniApp",
)
CACHE = {"opentelemetry-swift-core", "swift-atomics"}


def original_block(marker: str) -> str:
    """Exercise the checked-in producer code, not a reimplemented predicate."""
    source = SCRIPT.read_text()
    return source.split(marker + "\n", 1)[1].split("\nPY\n", 1)[0]


VALIDATOR = original_block('python3 - "$scratch" "$evidence" "$producer_sha" <<\'PY\'')
TOOLCHAIN = original_block('python3 - "$evidence/xcode.txt" <<\'PY\'')


def encode(value) -> bytes:
    return (json.dumps(value, indent=2) + "\n").encode()


class AgentSDKLockResolutionGuardTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="hanlin-lock-guard-")
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name)
        self.scratch = self.repository / "resolved"
        self.evidence = self.repository / "evidence"
        self.evidence.mkdir()
        self.canonical = json.loads((ROOT / APP_LOCK).read_text())
        self.canonical_pins = {p["identity"]: p for p in self.canonical["pins"]}
        self.producer = self.canonical_pins["swift-ai-sdk"]["state"]["revision"]
        self.before = {}
        self.after = {}
        for name in PACKAGES:
            original = json.loads((ROOT / "Packages" / name / "Package.resolved").read_text())
            # Simulate the real pre-OTel lock even after the repository's locks
            # are subsequently normalized by the original Apple producer.
            old = copy.deepcopy(original)
            old["pins"] = [p for p in old["pins"] if p["identity"] not in CACHE]
            self.before[name] = old
            new = copy.deepcopy(old)
            new["pins"] += [copy.deepcopy(self.canonical_pins[k]) for k in sorted(CACHE)]
            self.after[name] = new
        canonical_path = self.repository / APP_LOCK
        canonical_path.parent.mkdir(parents=True)
        canonical_path.write_bytes(encode(self.canonical))
        manifest = "Packages/HanlinPlatform/Package.swift"
        manifest_path = self.scratch / manifest
        manifest_path.parent.mkdir(parents=True)
        manifest_path.write_bytes((ROOT / manifest).read_bytes())
        self.inputs = {
            APP_LOCK: hashlib.sha256(canonical_path.read_bytes()).hexdigest(),
            manifest: hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
        }
        (self.evidence / "input-sha256.json").write_bytes(encode(self.inputs))

    def run_guard(self):
        for name, value in self.after.items():
            path = self.scratch / "Packages" / name / "Package.resolved"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(encode(value))

        def original_git(command):
            self.assertEqual(command[:2], ["git", "show"])
            prefix, name, filename = command[2].split("/")
            self.assertEqual(prefix, "HEAD:Packages")
            self.assertEqual(filename, "Package.resolved")
            return encode(self.before[name])

        with contextlib.chdir(self.repository), patch.object(
            sys, "argv", ["-", str(self.scratch), str(self.evidence), self.producer]
        ), patch("subprocess.check_output", side_effect=original_git):
            exec(compile(VALIDATOR, str(SCRIPT) + ":lock-guard", "exec"), {})
        return json.loads((self.evidence / "summary.json").read_text())

    def mutate_all(self, identity, field, value):
        for graph in self.after.values():
            pin = next(p for p in graph["pins"] if p["identity"] == identity)
            destination = pin["state"] if field in {"revision", "version"} else pin
            destination[field] = value

    def test_accepts_only_canonical_cache_additions_in_all_six_graphs(self):
        summary = self.run_guard()
        self.assertEqual(summary["status"], "RESOLUTION_PASS")
        self.assertEqual(summary["graphs"], 6)
        self.assertEqual(summary["builds"], 0)
        self.assertEqual(summary["tests"], 0)
        self.assertFalse(summary["unrelated_pins_changed"])
        self.assertEqual(summary["cache_dependency_pins"],
                         {k: self.canonical_pins[k] for k in sorted(CACHE)})
        rows = json.loads((self.evidence / "resolution.json").read_text())
        self.assertEqual(len(rows), 6)
        for row in rows:
            self.assertEqual(row["previously_unlocked_existing_dependencies"], sorted(CACHE))
        self.assertEqual(
            (self.evidence / "canonical-app-Package.resolved").read_bytes(),
            (self.repository / APP_LOCK).read_bytes(),
        )

    def test_normalized_graphs_remain_idempotent(self):
        self.before = copy.deepcopy(self.after)
        self.assertEqual(self.run_guard()["graphs"], 6)
        rows = json.loads((self.evidence / "resolution.json").read_text())
        self.assertTrue(all(not row["previously_unlocked_existing_dependencies"] for row in rows))

    def test_preserves_unrelated_pin_drift_rejection(self):
        self.mutate_all("swift-argument-parser", "revision", "0" * 40)
        with self.assertRaisesRegex(AssertionError, "unrelated pin changed"):
            self.run_guard()

    def test_rejects_unknown_additions_even_if_present_in_every_graph(self):
        for graph in self.after.values():
            graph["pins"].append({
                "identity": "unrelated-package", "kind": "remoteSourceControl",
                "location": "https://example.invalid/unrelated.git",
                "state": {"revision": "0" * 40, "version": "1.0.0"},
            })
        with self.assertRaisesRegex(AssertionError, "unexpected identity addition"):
            self.run_guard()

    def test_rejects_cache_revision_version_origin_and_kind_drift(self):
        original = copy.deepcopy(self.after)
        for identity, field, value in [
            ("opentelemetry-swift-core", "revision", "0" * 40),
            ("swift-atomics", "version", "9.9.9"),
            ("opentelemetry-swift-core", "location", "https://example.invalid/otel.git"),
            ("swift-atomics", "kind", "localSourceControl"),
        ]:
            with self.subTest(identity=identity, field=field):
                self.after = copy.deepcopy(original)
                self.mutate_all(identity, field, value)
                with self.assertRaisesRegex(AssertionError, "cache dependency differs from canonical app lock"):
                    self.run_guard()

    def test_rejects_missing_required_cache_dependency(self):
        for graph in self.after.values():
            graph["pins"] = [p for p in graph["pins"] if p["identity"] != "swift-atomics"]
        with self.assertRaisesRegex(AssertionError, "required cache dependency missing"):
            self.run_guard()

    def test_preserves_dependency_removal_rejection(self):
        for graph in self.after.values():
            graph["pins"] = [p for p in graph["pins"] if p["identity"] != "zipfoundation"]
        with self.assertRaisesRegex(AssertionError, "dependency removed"):
            self.run_guard()

    def test_preserves_existing_miniapp_only_swiftyjson_inheritance(self):
        for name in PACKAGES:
            if name.endswith("MiniApp"):
                self.before[name]["pins"] = [
                    p for p in self.before[name]["pins"] if p["identity"] != "swiftyjson"
                ]
        self.assertEqual(self.run_guard()["graphs"], 6)
        self.before["HanlinPlatform"]["pins"] = [
            p for p in self.before["HanlinPlatform"]["pins"] if p["identity"] != "swiftyjson"
        ]
        with self.assertRaisesRegex(AssertionError, "unexpected identity addition"):
            self.run_guard()

    def test_preserves_exact_producer_revision_rejection(self):
        self.mutate_all("swift-ai-sdk", "revision", "0" * 40)
        with self.assertRaises(AssertionError):
            self.run_guard()

    def test_rejects_noncanonical_reference_dependency(self):
        for pin in self.canonical["pins"]:
            if pin["identity"] == "swift-atomics":
                pin["state"]["version"] = "9.9.9"
        (self.repository / APP_LOCK).write_bytes(encode(self.canonical))
        with self.assertRaisesRegex(AssertionError, "canonical cache dependency version mismatch"):
            self.run_guard()

    def test_rejects_canonical_reference_change_after_input_capture(self):
        path = self.repository / APP_LOCK
        path.write_bytes(path.read_bytes() + b"\n")
        with self.assertRaisesRegex(AssertionError, "AI_HLY.xcodeproj"):
            self.run_guard()

    def test_requires_retained_actual_xcode27_metadata(self):
        path = self.evidence / "xcode.txt"
        path.write_text("Xcode 27.0\nBuild version 18A123\n")
        with patch.object(sys, "argv", ["-", str(path)]):
            exec(compile(TOOLCHAIN, str(SCRIPT) + ":toolchain", "exec"), {})
        for value in ["Xcode 26.4\nBuild version 17F123\n", "Xcode 27.0\n", "fabricated"]:
            with self.subTest(value=value):
                path.write_text(value)
                with patch.object(sys, "argv", ["-", str(path)]), self.assertRaises(AssertionError):
                    exec(compile(TOOLCHAIN, str(SCRIPT) + ":toolchain", "exec"), {})


if __name__ == "__main__":
    unittest.main()
