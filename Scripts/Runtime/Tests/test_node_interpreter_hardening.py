from pathlib import Path
import hashlib
import importlib.util
import json
import os
import shutil
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("patcher", REPOSITORY / "Scripts/Runtime/apply-node-source-patches.py")
patcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patcher)
MANIFEST = REPOSITORY / "Scripts/Runtime/Patches/v8-drumbrake-hardening-2026.json"


class InterpreterHardeningTests(unittest.TestCase):
    def test_original_evidence_and_real_release_guards_are_retained_without_test_skips(self):
        manifest = json.loads(MANIFEST.read_bytes())
        originals = [manifest["upstreamPatch"], *manifest["upstreamPatches"]]
        self.assertEqual(len(originals), 3)
        for original in originals:
            data = (REPOSITORY / original["path"]).read_bytes()
            self.assertTrue(data.startswith(("From " + original["upstreamCommit"] + " ").encode()))
            self.assertEqual(hashlib.sha256(data).hexdigest(), original["sha256"])
        self.assertEqual(len(manifest["files"]), 4)
        after = []
        for change in manifest["files"]:
            self.assertTrue(change["path"].startswith("deps/v8/src/"))
            self.assertNotEqual(change["beforeSHA256"], change["afterSHA256"])
            for replacement in change["replacements"]:
                self.assertTrue(replacement["adaptation"])
                self.assertNotIn("SBXCHECK", replacement["after"], "SBXCHECK is debug-only in this actual Node configuration")
                after.append(replacement["after"])
        combined = "\n".join(after)
        self.assertIn("CHECK_EQ(trusted_data->module(), module_)", combined)
        self.assertIn("CHECK_EQ(*instance_object_, *instance)", combined)
        self.assertIn("CHECK_EQ(sig->return_count(), return_values.size())", combined)

    @unittest.skipUnless(os.environ.get("HANLIN_PINNED_NODE_SOURCE"), "Requires authentic pinned production sources")
    def test_full_real_fix_chain_is_identical_from_raw_intermediate_and_final_checkpoints(self):
        lock = json.loads((REPOSITORY / "RuntimeDependencies.lock.json").read_bytes())
        final = {}
        for pin in lock["node"]["sourcePatches"]:
            for change in json.loads((REPOSITORY / pin["path"]).read_bytes())["files"]:
                final[change["path"]] = change["afterSHA256"]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in final:
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(Path(os.environ["HANLIN_PINNED_NODE_SOURCE"]) / name, target)
            selected = root / "before-hardening.json"
            selected.write_text(json.dumps({"node": {**lock["node"], "sourcePatches": lock["node"]["sourcePatches"][:-1]}}), encoding="utf-8")
            # Existing FD and original type/GC backports, then new hardening.
            patcher.apply_patches(root, selected, REPOSITORY)
            patcher.apply_patches(root, REPOSITORY / "RuntimeDependencies.lock.json", REPOSITORY)
            first = {name: (root / name).read_bytes() for name in final}
            self.assertEqual({name: hashlib.sha256(data).hexdigest() for name, data in first.items()}, final)
            patcher.apply_patches(root, REPOSITORY / "RuntimeDependencies.lock.json", REPOSITORY)
            self.assertEqual(first, {name: (root / name).read_bytes() for name in final})
            for name in final:
                shutil.copyfile(Path(os.environ["HANLIN_PINNED_NODE_SOURCE"]) / name, root / name)
            patcher.apply_patches(root, REPOSITORY / "RuntimeDependencies.lock.json", REPOSITORY)
            self.assertEqual(first, {name: (root / name).read_bytes() for name in final})
            interpreter = (root / "deps/v8/src/wasm/interpreter/wasm-interpreter.cc").read_text(encoding="utf-8")
            self.assertIn("static_assert(COMPRESS_POINTERS_BOOL)", interpreter)


if __name__ == "__main__":
    unittest.main()
