"""Original-CPython module resolution: real sources, no imported fixture code."""
import contextlib
import hashlib
import importlib.machinery
import json
from pathlib import Path
import runpy
import sys
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[3]
HELPER = ROOT / "AI_HLY/Downstream/AgentSkills/Analysis/Resources/hanlin_python_ast.py"
inspect_modules = runpy.run_path(str(HELPER))["inspect_python_module_requirements"]


@contextlib.contextmanager
def search_path(root):
    previous = sys.path[:]
    sys.path.insert(0, str(root))
    try:
        yield
    finally:
        sys.path[:] = previous


def inspect(*names, **options):
    return inspect_modules([{"kind": "moduleReference", "value": name} for name in names], **options)


class PythonSkillModuleFactsTests(unittest.TestCase):
    def test_stdlib_submodules_resolve_without_importing_their_parent(self):
        before = {name for name in sys.modules if name == "urllib" or name.startswith("urllib.")}
        report = inspect("sys", "json", "urllib.request", "urllib.parse", "pathlib", "argparse")
        self.assertEqual(report["scope"], "native-skill-isolated")
        self.assertTrue(report["resolutionOnly"])
        self.assertTrue(all(item["status"] == "available" for item in report["modules"]), report)
        self.assertEqual(before, {name for name in sys.modules if name == "urllib" or name.startswith("urllib.")})
        urllib_request = next(item for item in report["modules"] if item["name"] == "urllib.request")
        self.assertGreaterEqual(len(urllib_request["sourceFiles"]), 1)
        for source in urllib_request["sourceFiles"]:
            data = Path(source["path"]).read_bytes()
            self.assertEqual(source["sha256"], hashlib.sha256(data).hexdigest())

    def test_real_package_and_parent_code_are_never_executed(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            package = root / "corpus_no_import"
            package.mkdir()
            marker = root / "import-side-effect"
            (package / "__init__.py").write_text(
                "from pathlib import Path\nPath(" + repr(str(marker)) + ").write_text('executed')\n",
                encoding="utf-8")
            (package / "child.py").write_text("raise AssertionError('must not execute')\n", encoding="utf-8")
            with search_path(root):
                report = inspect("corpus_no_import.child")
            fact = report["modules"][0]
            self.assertEqual(fact["status"], "available", fact)
            self.assertEqual(len(fact["sourceFiles"]), 2)
            self.assertFalse(marker.exists())
            self.assertNotIn("corpus_no_import", sys.modules)
            self.assertNotIn("corpus_no_import.child", sys.modules)

    def test_custom_meta_path_path_hook_and_cached_finder_are_not_called(self):
        calls = []
        class Trap:
            def find_spec(self, *args):
                calls.append(args)
                raise AssertionError("custom finder executed")
        def hook(path):
            calls.append(path)
            raise AssertionError("custom path hook executed")
        original_meta = sys.meta_path[:]
        original_hooks = sys.path_hooks[:]
        original_cache = sys.path_importer_cache
        try:
            sys.meta_path.insert(0, Trap())
            self.assertEqual(inspect("json")["modules"][0]["status"], "unknown")
            sys.meta_path[:] = original_meta
            sys.path_hooks.insert(0, hook)
            self.assertEqual(inspect("json")["modules"][0]["status"], "unknown")
            sys.path_hooks[:] = original_hooks
            with tempfile.TemporaryDirectory() as folder, search_path(folder):
                sys.path_importer_cache = {**original_cache, folder: Trap()}
                self.assertEqual(inspect("json")["modules"][0]["status"], "unknown")
            self.assertEqual(calls, [])
        finally:
            sys.meta_path[:] = original_meta
            sys.path_hooks[:] = original_hooks
            sys.path_importer_cache = original_cache

    def test_source_change_and_deletion_cannot_keep_the_old_identity(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "corpus_mutable.py"
            source.write_text("value = 1\n", encoding="utf-8")
            with search_path(folder):
                first = inspect("corpus_mutable")["modules"][0]
                source.write_text("value = 2\n", encoding="utf-8")
                second = inspect("corpus_mutable")["modules"][0]
                source.unlink()
                removed = inspect("corpus_mutable")["modules"][0]
            self.assertEqual(first["status"], "available")
            self.assertEqual(second["status"], "available")
            self.assertNotEqual(first["sourceFiles"][0]["sha256"], second["sourceFiles"][0]["sha256"])
            self.assertEqual(removed["status"], "unknown")
            self.assertNotIn("corpus_mutable", sys.modules)

    def test_native_extension_and_namespace_do_not_become_false_ready(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "corpus_namespace").mkdir()
            (root / "corpus_namespace" / "child.py").write_text("raise AssertionError\n", encoding="utf-8")
            extension = root / ("corpus_uninitialized_native" + importlib.machinery.EXTENSION_SUFFIXES[0])
            extension.write_bytes(b"not a loadable native library")
            with search_path(root):
                report = inspect("corpus_namespace.child", "corpus_uninitialized_native", "corpus_missing")
            self.assertTrue(all(item["status"] == "unknown" for item in report["modules"]), report)
            self.assertNotIn("corpus_uninitialized_native", sys.modules)

    def test_original_zip_finder_binds_to_the_actual_archive_without_import(self):
        with tempfile.TemporaryDirectory() as folder:
            archive = Path(folder) / "original.zip"
            with zipfile.ZipFile(archive, "w") as bundle:
                bundle.writestr("corpus_zip/__init__.py", "raise AssertionError('parent executed')\n")
                bundle.writestr("corpus_zip/child.py", "raise AssertionError('child executed')\n")
            with search_path(archive):
                fact = inspect("corpus_zip.child")["modules"][0]
            self.assertEqual(fact["status"], "available", fact)
            self.assertEqual(len(fact["sourceFiles"]), 1)
            self.assertEqual(fact["sourceFiles"][0]["sha256"], hashlib.sha256(archive.read_bytes()).hexdigest())
            self.assertNotIn("corpus_zip", sys.modules)
            self.assertNotIn("corpus_zip.child", sys.modules)

    def test_budgets_and_invalid_names_remain_unknown_and_restore_cache(self):
        cache = sys.path_importer_cache
        report = inspect(*("corpus_module_" + str(index) for index in range(65)))
        self.assertEqual(len(report["modules"]), 64)
        self.assertTrue(all(item["status"] == "unknown" for item in report["modules"]))
        invalid = inspect(".relative", "not/a/module", "bad..name")
        self.assertTrue(all(item["status"] == "unknown" for item in invalid["modules"]))
        with tempfile.TemporaryDirectory() as folder, search_path(folder):
            (Path(folder) / "corpus_large.py").write_bytes(b"x" * 1024)
            too_large = inspect("corpus_large", maximum_source_bytes=128)
            self.assertEqual(too_large["modules"][0]["status"], "unknown")
        self.assertIs(sys.path_importer_cache, cache)


    def test_equality_traps_and_missing_bootstrap_dependencies_execute_no_custom_code(self):
        import types
        import _frozen_importlib_external as external
        calls = []
        class Trap:
            def __eq__(self, other):
                calls.append("eq")
                raise AssertionError("custom equality executed")
            def __ne__(self, other):
                calls.append("ne")
                raise AssertionError("custom inequality executed")
            def find_spec(self, *args):
                calls.append("finder")
                raise AssertionError("custom finder executed")
        previous_meta = sys.meta_path[:]
        previous_hooks = sys.path_hooks[:]
        previous_cache = sys.path_importer_cache
        try:
            sys.meta_path[0] = Trap()
            self.assertEqual(inspect("json")["modules"][0]["status"], "unknown")
            sys.meta_path[:] = previous_meta

            original = importlib.machinery.FileFinder.path_hook(*external._get_supported_file_loaders())
            def cell(value):
                return (lambda: value).__closure__[0]
            contents = [entry.cell_contents for entry in original.__closure__]
            contents[0] = Trap()
            counterfeit = types.FunctionType(original.__code__, original.__globals__,
                closure=tuple(cell(value) for value in contents))
            sys.path_hooks[:] = [counterfeit]
            self.assertEqual(inspect("json")["modules"][0]["status"], "unknown")
            sys.path_hooks[:] = previous_hooks

            with tempfile.TemporaryDirectory() as folder, search_path(folder):
                finder = importlib.machinery.FileFinder(folder, *external._get_supported_file_loaders())
                finder._loaders[0] = (finder._loaders[0][0], Trap())
                sys.path_importer_cache = {**previous_cache, folder: finder}
                self.assertEqual(inspect("json")["modules"][0]["status"], "unknown")
            sys.path_importer_cache = previous_cache

            module = types.ModuleType("corpus_opaque_loader")
            module.__spec__ = importlib.machinery.ModuleSpec(module.__name__, Trap())
            sys.modules[module.__name__] = module
            try:
                self.assertEqual(inspect(module.__name__)["modules"][0]["status"], "unknown")
            finally:
                sys.modules.pop(module.__name__, None)

            # Missing dependencies must stay unknown, without importing them or
            # consulting a custom finder while attempting to inspect that finder.
            dependency = sys.modules.pop("_frozen_importlib_external")
            sys.meta_path[0] = Trap()
            try:
                fact = inspect("json")["modules"][0]
                self.assertEqual(fact["reason"], "inspectionDependencyUnavailable")
            finally:
                sys.modules["_frozen_importlib_external"] = dependency
                sys.meta_path[:] = previous_meta
            self.assertEqual(calls, [])
        finally:
            sys.meta_path[:] = previous_meta
            sys.path_hooks[:] = previous_hooks
            sys.path_importer_cache = previous_cache

    def test_original_job_runner_uses_identical_paths_for_inspection_and_actual_skill_id(self):
        import os
        runner_path = ROOT / "AI_HLY/Downstream/RuntimeCore/Python/Resources/HanlinPythonExecution.py"
        runner = runpy.run_path(str(runner_path))["_run"]
        original_environment = dict(os.environ)
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            package = root / "installed-package"
            package.mkdir()
            reports = []
            for index, identity in enumerate(("hanlin-skill-analysis", "maintained-real-skill")):
                workspace = root / ("workspace-" + str(index))
                workspace.mkdir()
                environment = {"SKILL_ID": identity}
                if index:
                    environment.update({
                        "CAIRO_GENIZAH_STATE_DIR": str(workspace),
                        "SKILL_RESOURCE_DIR": str(root / "original-resource"),
                        "TMPDIR": str(workspace), "TEMP": str(workspace),
                        "PATH": original_environment.get("PATH", ""), "LANG": "en_US.UTF-8"
                    })
                result = runner({
                    "workspace": str(workspace), "outputDirectory": str(root / ("job-" + str(index))),
                    "environment": environment, "packageDirectories": [str(package)],
                    "source": "import json, os, sys\nprint(json.dumps({'path':sys.path, 'has_pythonpath':'PYTHONPATH' in os.environ}))"
                }, lambda: False, lambda: 0)
                self.assertEqual(result["exitCode"], 0, result)
                reports.append(json.loads(result["stdout"]))
            self.assertEqual(reports[0], reports[1])
            self.assertIn(str(package), reports[0]["path"])
            self.assertFalse(reports[0]["has_pythonpath"])
            self.assertNotIn(str(root / "workspace-0"), reports[0]["path"])
            self.assertNotIn(str(root / "workspace-1"), reports[0]["path"])
        self.assertEqual(dict(os.environ), original_environment)



class IsolatedPythonSkillModuleFactsTests(unittest.TestCase):
    def test_original_interpreter_resolution_contract(self):
        result = subprocess.run([sys.executable, "-I", "-S", __file__, "-v"],
            capture_output=True, text=True, encoding="utf-8", timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        print("PYTHON_MODULE_FACTS_ISOLATED\n" + result.stdout + result.stderr)


def load_tests(loader, tests, pattern):
    # Use a reproducible original-interpreter baseline and separately reject
    # custom hooks. This portable host does not prove the native iOS configuration.
    case = PythonSkillModuleFactsTests if sys.flags.isolated and sys.flags.no_site else IsolatedPythonSkillModuleFactsTests
    return loader.loadTestsFromTestCase(case)


if __name__ == "__main__":
    unittest.main()
