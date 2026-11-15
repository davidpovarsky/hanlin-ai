from pathlib import Path
import ast
import importlib.util
import os
import shutil
import tempfile
import unittest

SCRIPT = Path(__file__).parents[1] / "configure-node-wasm.py"
SPEC = importlib.util.spec_from_file_location("node_wasm_configuration", SCRIPT)
adapter = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(adapter)

@unittest.skipUnless(os.environ.get("HANLIN_PINNED_NODE_SOURCE"), "Requires the actual hash-pinned Node source, not a synthetic GYP fixture")
class NodeWasmConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        source = Path(os.environ["HANLIN_PINNED_NODE_SOURCE"])
        for name in adapter.PREIMAGES:
            output = self.root / name
            output.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source / name, output)

    def test_actual_pinned_build_graph_enables_existing_interpreter_sources_and_explicit_bounds_checks(self):
        changes = adapter.proposed_changes(self.root)
        for output, contents, _ in changes:
            output.write_bytes(contents)
        features = ast.literal_eval((self.root / "tools/v8_gypfiles/features.gypi").read_text())
        self.assertEqual(features["variables"]["v8_enable_drumbrake%"], 1)
        self.assertIn("V8_DRUMBRAKE_BOUNDS_CHECKS", str(features["target_defaults"]))
        graph = ast.literal_eval((self.root / "tools/v8_gypfiles/v8.gyp").read_text())
        base = next(target for target in graph["targets"] if target["target_name"] == "v8_base_without_compiler")
        for source in adapter.INTERPRETER_SOURCES:
            self.assertIn("<(V8_ROOT)/" + source, str(base["conditions"]))
        initializers = next(target for target in graph["targets"] if target["target_name"] == "v8_initializers")
        self.assertIn("interpreter-builtins-arm64.cc", str(initializers["conditions"]))
        configure = (self.root / "tools/ios_framework_prepare.sh").read_text()
        self.assertEqual(configure.count("--v8-options='--jitless --wasm-jitless'"), 3)
        self.assertEqual(configure.count("--experimental-enable-pointer-compression"), 3)
        self.assertNotIn("--no-jitless", configure)
        # Repeat preparation keeps the authenticated source outputs unchanged.
        self.assertEqual([data for _, data, _ in adapter.proposed_changes(self.root)], [data for _, data, _ in changes])

    def test_changed_upstream_source_is_rejected_before_any_disposable_source_edit(self):
        untouched = self.root / "tools/v8_gypfiles/features.gypi"
        before = untouched.read_bytes()
        path = self.root / "tools/v8_gypfiles/v8.gyp"
        path.write_bytes(path.read_bytes() + b"\n# different upstream bytes\n")
        with self.assertRaisesRegex(ValueError, "Unexpected pinned Node build preimage"):
            adapter.proposed_changes(self.root)
        self.assertEqual(untouched.read_bytes(), before)

if __name__ == "__main__":
    unittest.main()
