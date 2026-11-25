"""Prevent recursive lock evidence while retaining full source immutability."""
import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPOSITORY / "Scripts/CI/IntegrationValidation"))
import run_cache_app_native as subject

WORKSPACE_LOCK = "AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
PACKAGE_LOCK = "Packages/Fixture/Package.resolved"
HISTORICAL_LOCK = "docs/evidence/before-locks/docs/old/after-locks/Packages/Fixture/Package.resolved"


class ActiveLockClassificationTests(unittest.TestCase):
    def test_actual_tracked_graph_has_exactly_nine_active_locks(self):
        raw = subprocess.check_output([
            "git", "-c", "safe.directory=" + str(REPOSITORY), "-C", str(REPOSITORY),
            "ls-files", "-z"])
        inventory = dict.fromkeys(raw.decode().rstrip("\0").split("\0"), "tracked")
        selected = {name for name in inventory if subject.is_active_package_lock(name, inventory)}
        packages = ("HanlinAgentSDK", "HanlinParityMiniApp", "HanlinPlatform",
                    "HanlinSefariaMiniApp", "HanlinSkillFormat", "HanlinSwiftUIBridgeGenerator",
                    "HanlinTextStudioMiniApp", "HanlinWikipediaMiniApp")
        self.assertEqual(selected, {WORKSPACE_LOCK} | {
            "Packages/" + package + "/Package.resolved" for package in packages})
        historical = {name for name in inventory if name.startswith("docs/")
                      and Path(name).name == "Package.resolved"}
        self.assertTrue(historical, "The actual historical evidence must exercise this regression")
        self.assertTrue(selected.isdisjoint(historical))

    def test_only_original_locations_with_captured_package_manifests_are_active(self):
        inventory = {
            "Package.resolved": "root",
            WORKSPACE_LOCK: "app",
            "Packages/Fixture/Package.swift": "manifest",
            PACKAGE_LOCK: "package",
            "Packages/NoManifest/Package.resolved": "orphan",
            "Packages/Fixture/Nested/Package.swift": "nested-manifest",
            "Packages/Fixture/Nested/Package.resolved": "nested",
            "Other.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved": "other",
            HISTORICAL_LOCK: "historical",
        }
        selected = {name for name in inventory if subject.is_active_package_lock(name, inventory)}
        self.assertEqual(selected, {"Package.resolved", WORKSPACE_LOCK, PACKAGE_LOCK})


class FullSourceSnapshotTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        base = Path(self.temporary.name)
        self.repository, self.evidence = base / "repository", base / "evidence"
        self.repository.mkdir()
        self.evidence.mkdir()
        self.contents = {
            "Config.xcconfig": "unchanged original configuration\n",
            "Sources/Original.swift": "struct Original {}\n",
            WORKSPACE_LOCK: '{"pins":["app"]}\n',
            "Packages/Fixture/Package.swift": "// actual package manifest\n",
            PACKAGE_LOCK: '{"pins":["package"]}\n',
            "Packages/NoManifest/Package.resolved": '{"pins":["not-an-active-package"]}\n',
            HISTORICAL_LOCK: '{"pins":["historical-proof"]}\n',
        }
        for name, content in self.contents.items():
            path = self.repository / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        # The original snapshot also captures a present untracked root lock.
        (self.repository / "Package.resolved").write_text('{"pins":["root"]}\n')
        self.addCleanup(mock.patch.stopall)
        mock.patch.object(subject, "ROOT", self.repository).start()
        mock.patch.object(subject, "WORKFLOW",
                          self.repository / ".github/workflows/build-ios26-unsigned-ipa.yml").start()
        mock.patch.object(subject, "git", side_effect=self.git).start()

    def git(self, *arguments):
        if arguments == ("ls-files", "-z"):
            return ("\0".join(self.contents) + "\0").encode()
        if arguments == ("rev-parse", "HEAD"):
            return b"same-sealed-source\n"
        if arguments == ("diff", "--binary", "HEAD", "--", "."):
            return b""
        self.fail("Unexpected external command in snapshot fixture: " + repr(arguments))

    def snapshot(self, label):
        return subject.snapshot(self.evidence, label)

    def test_all_tracked_bytes_stay_hashed_but_historical_locks_are_not_recopied(self):
        before = self.snapshot("before")
        self.assertEqual(set(before["files"]), set(self.contents) | {"Package.resolved"})
        for name, content in self.contents.items():
            self.assertEqual(before["files"][name], hashlib.sha256(content.encode()).hexdigest())
        expected = {"Package.resolved", WORKSPACE_LOCK, PACKAGE_LOCK}
        self.assertEqual(set(before["locks"]), expected)
        copies = {str(path.relative_to(self.evidence / "before-locks"))
                  for path in (self.evidence / "before-locks").rglob("Package.resolved")}
        self.assertEqual(copies, expected)

    def test_historical_proof_mutation_fails_both_phases_even_though_it_is_not_a_graph_input(self):
        before = self.snapshot("before")
        (self.repository / HISTORICAL_LOCK).write_text('{"pins":["changed-historical-proof"]}\n')
        after = self.snapshot("after")
        self.assertEqual(subject.preparation_inputs(before["files"]),
                         subject.preparation_inputs(after["files"]))
        for phase in ("prepare", "test"):
            with self.subTest(phase=phase):
                changed, changed_locks, unexpected = subject.compare_sources(before, after, phase)
                self.assertEqual(changed, [HISTORICAL_LOCK])
                self.assertEqual(changed_locks, [])
                self.assertTrue(unexpected, "Historical proof changes must never receive the resolver allowance")

    def test_active_lock_change_invalidates_prepared_inputs_and_remains_immutable_during_test(self):
        before = self.snapshot("before")
        (self.repository / PACKAGE_LOCK).write_text('{"pins":["new-canonical-revision"]}\n')
        after = self.snapshot("after")
        self.assertNotEqual(subject.preparation_inputs(before["files"]),
                            subject.preparation_inputs(after["files"]))
        self.assertEqual(subject.compare_sources(before, after, "prepare"),
                         ([PACKAGE_LOCK], [PACKAGE_LOCK], False))
        self.assertEqual(subject.compare_sources(before, after, "test"),
                         ([PACKAGE_LOCK], [PACKAGE_LOCK], True))

    def test_other_source_and_source_head_changes_are_still_rejected(self):
        before = self.snapshot("before")
        (self.repository / "Sources/Original.swift").write_text("struct Changed {}\n")
        after = self.snapshot("after")
        self.assertTrue(subject.compare_sources(before, after, "prepare")[2])
        same_files_new_commit = dict(before, sourceSHA="different-source-commit")
        self.assertTrue(subject.compare_sources(before, same_files_new_commit, "prepare")[2])

    def test_missing_historical_tracked_file_is_still_an_error(self):
        (self.repository / HISTORICAL_LOCK).unlink()
        with self.assertRaisesRegex(RuntimeError, "Tracked inputs are not materialized"):
            self.snapshot("missing")


if __name__ == "__main__":
    unittest.main()
