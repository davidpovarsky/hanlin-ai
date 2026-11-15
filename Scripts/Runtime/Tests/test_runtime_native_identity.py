from pathlib import Path
import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).parents[1] / "runtime_native_identity.py"
SPEC = importlib.util.spec_from_file_location("native_identity", SCRIPT)
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)
REPOSITORY = SCRIPT.parents[2]

class NativeIdentityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.lock = json.loads((REPOSITORY / "RuntimeDependencies.lock.json").read_text(encoding="utf-8"))
        files = list(module.NATIVE_SCRIPTS) + [item["path"] for item in self.lock["node"].get("sourcePatches", [])]
        for patch in self.lock["node"].get("sourcePatches", []):
            manifest = json.loads((REPOSITORY / patch["path"]).read_bytes())
            for original in ([manifest["upstreamPatch"]] if manifest.get("upstreamPatch") else []) + manifest.get("upstreamPatches", []):
                files.append(original["path"])
        adapter = self.lock["node"].get("buildConfiguration", {}).get("adapter", {}).get("path")
        if adapter:
            files.append(adapter)
        for name in files:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(REPOSITORY / name, target)
        self.write_lock()

    def write_lock(self):
        (self.root / "RuntimeDependencies.lock.json").write_text(json.dumps(self.lock), encoding="utf-8")

    def test_host_packages_and_metadata_do_not_invalidate_unchanged_binary_inputs(self):
        before = module.native_identity(self.root)
        self.lock["nodeHostPackages"]["fixture"] = {"version": "2.0.0"}
        self.lock["runtimeBundle"]["sha256"] = "a" * 64
        self.write_lock()
        self.assertEqual(module.native_identity(self.root), before)

    def test_actual_native_build_script_or_patch_change_invalidates_reuse(self):
        before = module.native_identity(self.root)
        script = self.root / module.NATIVE_SCRIPTS[0]
        script.write_bytes(script.read_bytes() + b"\necho changed-native-build\n")
        self.assertNotEqual(module.native_identity(self.root), before)
        shutil.copyfile(REPOSITORY / module.NATIVE_SCRIPTS[0], script)
        patch = self.root / self.lock["node"]["sourcePatches"][0]["path"]
        patch.write_bytes(patch.read_bytes() + b" ")
        self.assertNotEqual(module.native_identity(self.root), before)

    def test_python_archive_or_node_revision_change_invalidates_reuse(self):
        before = module.native_identity(self.root)
        self.lock["python"]["archive"]["sha256"] = "b" * 64
        self.write_lock()
        self.assertNotEqual(module.native_identity(self.root), before)
        self.lock = json.loads((REPOSITORY / "RuntimeDependencies.lock.json").read_text(encoding="utf-8"))
        self.lock["node"]["commit"] = "c" * 40
        self.write_lock()
        self.assertNotEqual(module.native_identity(self.root), before)

    def test_original_upstream_evidence_bytes_are_native_inputs(self):
        before = module.native_identity(self.root)
        manifest = next(json.loads((self.root / item["path"]).read_bytes())
            for item in self.lock["node"]["sourcePatches"]
            if json.loads((self.root / item["path"]).read_bytes()).get("upstreamPatch"))
        original = self.root / manifest["upstreamPatch"]["path"]
        original.write_bytes(original.read_bytes() + b"\nmodified upstream evidence\n")
        self.assertNotEqual(module.native_identity(self.root), before)

    def test_pointer_representation_changes_invalidate_all_old_native_outputs(self):
        before = module.native_identity(self.root)
        self.lock["node"]["buildConfiguration"]["pointerCompression"] = not self.lock["node"]["buildConfiguration"]["pointerCompression"]
        self.write_lock()
        self.assertNotEqual(module.native_identity(self.root), before)

    def test_each_additional_hardening_evidence_file_invalidates_reuse(self):
        before = module.native_identity(self.root)
        for pin in self.lock["node"]["sourcePatches"]:
            manifest = json.loads((self.root / pin["path"]).read_bytes())
            for original in manifest.get("upstreamPatches", []):
                path = self.root / original["path"]
                data = path.read_bytes()
                path.write_bytes(data + b"modified extra evidence")
                self.assertNotEqual(module.native_identity(self.root), before)
                path.write_bytes(data)

    def test_windows_text_checkout_matches_the_actual_macos_lf_instructions(self):
        for name in module.NATIVE_SCRIPTS:
            target = self.root / name
            target.write_bytes(target.read_bytes().replace(b"\r\n", b"\n"))
        before = module.native_identity(self.root)
        for name in module.NATIVE_SCRIPTS:
            target = self.root / name
            target.write_bytes(target.read_bytes().replace(b"\n", b"\r\n"))
        self.assertEqual(module.native_identity(self.root), before)

    def test_consumer_gate_rejects_modified_native_inputs_instead_of_reusing_them(self):
        self.lock["runtimeBundle"]["nativeInputSHA256"] = module.native_identity(self.root)
        self.write_lock()
        command = [sys.executable, str(SCRIPT), "--repository", str(self.root), "--verify-reuse"]
        self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
        target = self.root / module.NATIVE_SCRIPTS[0]
        target.write_bytes(target.read_bytes() + b"\nchanged\n")
        result = subprocess.run(command, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"Build and verify a new native bundle", result.stderr)

if __name__ == "__main__":
    unittest.main()
