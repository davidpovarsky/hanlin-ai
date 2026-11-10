from pathlib import Path
import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
MANIFEST = REPOSITORY / "Scripts/Runtime/Patches/v8-drumbrake-5c595adf.json"
SPEC = importlib.util.spec_from_file_location("source_patcher", REPOSITORY / "Scripts/Runtime/apply-node-source-patches.py")
patcher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(patcher)


class DrumBrakeBackportTests(unittest.TestCase):
    def test_all_production_targets_change_and_original_evidence_is_pinned(self):
        manifest = json.loads(MANIFEST.read_bytes())
        self.assertEqual(manifest["upstreamCommit"], "5c595adf56abcb89251882a2dbf800972500989a")
        self.assertEqual(len(manifest["files"]), 10)
        original = REPOSITORY / manifest["upstreamPatch"]["path"]
        self.assertEqual(hashlib.sha256(original.read_bytes()).hexdigest(), manifest["upstreamPatch"]["sha256"])
        for change in manifest["files"]:
            self.assertTrue(change["path"].startswith("deps/v8/src/"))
            self.assertNotEqual(change["beforeSHA256"], change["afterSHA256"])
            self.assertTrue(change["replacements"])
            for replacement in change["replacements"]:
                self.assertTrue(replacement["before"])
                self.assertNotEqual(replacement["before"], replacement["after"])

    @unittest.skipUnless(os.environ.get("HANLIN_PINNED_NODE_SOURCE"), "Requires authentic pinned Node production sources")
    def test_actual_sources_reproduce_upstream_with_only_documented_jspi_context_adaptation(self):
        manifest = json.loads(MANIFEST.read_bytes())
        lock = json.loads((REPOSITORY / "RuntimeDependencies.lock.json").read_bytes())
        selected = next(item for item in lock["node"]["sourcePatches"] if item["upstreamCommit"] == manifest["upstreamCommit"])
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            actual, expected = base / "actual", base / "expected"
            for change in manifest["files"]:
                original = Path(os.environ["HANLIN_PINNED_NODE_SOURCE"]) / change["path"]
                self.assertEqual(patcher.digest(original.read_bytes()), change["beforeSHA256"])
                for tree in (actual, expected):
                    destination = tree / change["path"]
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(original, destination)
            selected_lock = base / "lock.json"
            selected_lock.write_text(json.dumps({"node": {"commit": lock["node"]["commit"], "sourcePatches": [selected]}}), encoding="utf-8")
            patcher.apply_patches(actual, selected_lock, REPOSITORY)
            patcher.apply_patches(actual, selected_lock, REPOSITORY)
            # Give Git an explicit disposable repository root. A parent repo's
            # subdirectory path filtering must never turn this into a no-op.
            subprocess.run(["git", "init", "--quiet", str(expected)], check=True)
            raw = (REPOSITORY / manifest["upstreamPatch"]["path"]).read_bytes()
            pieces = raw.split(b"diff --git ")
            production = pieces[0] + b"".join(b"diff --git " + part for part in pieces[1:]
                if not part.startswith((b"a/test/", b"a/src/execution/isolate.cc ")))
            reference = base / "upstream-production.patch"
            reference.write_bytes(production)
            subprocess.run(["git", "-c", "core.autocrlf=false", "-c", "core.eol=lf", "apply", "--directory=deps/v8", str(reference)], cwd=expected, check=True)
            isolate = expected / "deps/v8/src/execution/isolate.cc"
            text = isolate.read_bytes().decode("utf-8")
            for anchor, guard in (
                ("bool Isolate::IsWasmJSPIRequested(DirectHandle<NativeContext> context) {\n#ifdef V8_ENABLE_WEBASSEMBLY\n", "  if (v8_flags.wasm_jitless) return false;\n\n"),
                ("void Isolate::WasmInitJSPIFeature() {\n", "  if (v8_flags.wasm_jitless) return;\n\n"),
            ):
                self.assertEqual(text.count(anchor), 1)
                text = text.replace(anchor, anchor + guard, 1)
            isolate.write_bytes(text.encode("utf-8"))
            for change in manifest["files"]:
                result = (actual / change["path"]).read_bytes()
                self.assertEqual(patcher.digest(result), change["afterSHA256"])
                self.assertEqual(result, (expected / change["path"]).read_bytes())
