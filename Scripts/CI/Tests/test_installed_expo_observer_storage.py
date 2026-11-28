"""Controlled filesystem inputs for original native observer storage paths.
No simulator, actual installation, system action, or native outcome is created.
"""
from pathlib import Path
import copy
import json
import sys
import tempfile
import unittest
from unittest.mock import patch

# Keep the original shared discovery process's module/path state unchanged.
with patch.object(sys, "path", [str(Path(__file__).resolve().parents[2] / "ProductSplit"), *sys.path]), \
        patch.dict(sys.modules):
    import observe_shortcut_surfaces as shared
    import observe_shortcut_concurrency as concurrency


class InstalledExpoStorageTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.app_id = "hanlin.longrunning.expo"
        self.installation = "controlled-current-installation"
        self.request = {"fixtureAppID": self.app_id, "challenge": "fresh-ui-challenge", "baselineCounter": 0}
        # Same serialized shape written by the unchanged original proof.prepare.
        self.state = {"schemaVersion": 1, "appID": self.app_id,
                      "challenge": self.request["challenge"], "counter": 0, "lastResult": None}

    def write(self, path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value) + "\n")
        return path

    def package_state(self, installation=None):
        return (self.root / "Library" / "Application Support" / "HanlinPackages" /
                (self.installation if installation is None else installation) / "State")

    def app_state(self, app_id=None):
        return (self.root / "Library" / "Application Support" / "Hanlin" / "MiniApps" /
                (self.app_id if app_id is None else app_id) / "State")

    def test_current_installed_expo_preparation_uses_the_original_package_scope(self):
        expected = self.write(self.package_state() / "surface-proof.json", self.state)
        # The baseline uses the original public reader call; the candidate adds
        # only its explicit already-validated installation argument at this call.
        documents = shared.proof_documents(self.root, self.app_id,
                                          expo_installed_package_id=self.installation)
        prepared = shared.prepared_proof(self.request, documents)
        self.assertEqual(Path(prepared["path"]), expected)
        self.assertEqual(prepared["value"], self.state)

    def test_package_binding_never_falls_back_to_an_app_or_foreign_installation(self):
        self.write(self.app_state() / "surface-proof.json", self.state)
        self.write(self.package_state("foreign-installation") / "surface-proof.json", self.state)
        documents = shared.proof_documents(self.root, self.app_id,
                                          expo_installed_package_id=self.installation)
        with self.assertRaisesRegex(shared.ObservationError, "Exactly one actual private state"):
            shared.prepared_proof(self.request, documents)

    def test_package_state_keeps_the_original_typed_preparation_guards(self):
        path = self.package_state() / "surface-proof.json"
        for field, value in (("appID", "foreign-app"), ("challenge", "foreign-ui-challenge"),
                             ("counter", False), ("counter", 0.0),
                             ("lastResult", {}), ("schemaVersion", 2)):
            with self.subTest(field=field, value=value):
                wrong = copy.deepcopy(self.state)
                wrong[field] = value
                self.write(path, wrong)
                documents = shared.proof_documents(self.root, self.app_id,
                                                  expo_installed_package_id=self.installation)
                with self.assertRaisesRegex(shared.ObservationError, "Exactly one actual private state"):
                    shared.prepared_proof(self.request, documents)

    def test_package_journals_read_only_the_exact_installation(self):
        expected = self.write(self.package_state() / "surface-invocation-token-nonce.json",
                              {"token": "controlled-token", "nonce": "controlled-nonce"})
        self.write(self.package_state("foreign-installation") / expected.name, {"foreign": True})
        self.write(self.app_state() / expected.name, {"legacy": True})
        documents = concurrency.journal_documents(self.root, self.app_id,
                                                 expo_installed_package_id=self.installation)
        self.assertEqual([Path(row["path"]) for row in documents], [expected])
        self.assertEqual(documents[0]["value"], {"token": "controlled-token", "nonce": "controlled-nonce"})

    def test_package_path_rejects_empty_absolute_and_traversing_installation_ids(self):
        for installation in ("", ".", "..", "/outside", "../outside", "nested/outside",
                             "nested\\outside", "invalid\0name", 7, True):
            with self.subTest(installation=installation):
                with self.assertRaises(shared.ObservationError):
                    shared.proof_documents(self.root, self.app_id,
                                           expo_installed_package_id=installation)
                with self.assertRaises(shared.ObservationError):
                    concurrency.journal_documents(self.root, self.app_id,
                                                  expo_installed_package_id=installation)

    def test_package_state_and_files_cannot_follow_symbolic_links(self):
        outside = self.root / "outside"
        self.write(outside / "surface-proof.json", self.state)
        package = self.package_state().parent
        package.mkdir(parents=True)
        self.package_state().symlink_to(outside, target_is_directory=True)
        with self.assertRaises(shared.ObservationError):
            shared.proof_documents(self.root, self.app_id, expo_installed_package_id=self.installation)
        with self.assertRaises(shared.ObservationError):
            concurrency.journal_documents(self.root, self.app_id, expo_installed_package_id=self.installation)
        self.package_state().unlink()
        self.package_state().mkdir()
        (self.package_state() / "surface-proof.json").symlink_to(outside / "surface-proof.json")
        with self.assertRaises(shared.ObservationError):
            shared.proof_documents(self.root, self.app_id, expo_installed_package_id=self.installation)

    def test_package_journals_keep_the_original_inventory_bound(self):
        for index in range(513):
            self.write(self.package_state() / ("surface-invocation-" + str(index) + ".json"), {})
        with self.assertRaisesRegex(shared.ObservationError, "bounded pilot"):
            concurrency.journal_documents(self.root, self.app_id, expo_installed_package_id=self.installation)

    def test_original_nativescript_app_window_paths_and_ambiguity_are_preserved(self):
        app_id = "hanlin.longrunning.nativescript"
        request = {**self.request, "fixtureAppID": app_id}
        state = {**self.state, "appID": app_id}
        app_state = self.app_state(app_id)
        owner = app_state.parent / "Windows" / "actual-owner" / "State"
        expected = self.write(owner / "surface-proof.json", state)
        self.write(app_state / "surface-proof.json", {**state, "challenge": "older-ui-challenge"})
        documents = shared.proof_documents(self.root, app_id)
        self.assertEqual(Path(shared.prepared_proof(request, documents)["path"]), expected)
        one = self.write(owner / "surface-invocation-owner.json", {"owner": True})
        two = self.write(app_state / "surface-invocation-legacy.json", {"legacy": True})
        self.assertEqual({Path(row["path"]) for row in concurrency.journal_documents(self.root, app_id)},
                         {one, two})
        self.write(app_state / "surface-proof.json", state)
        with self.assertRaisesRegex(shared.ObservationError, "Exactly one actual private state"):
            shared.prepared_proof(request, shared.proof_documents(self.root, app_id))


if __name__ == "__main__":
    unittest.main()
