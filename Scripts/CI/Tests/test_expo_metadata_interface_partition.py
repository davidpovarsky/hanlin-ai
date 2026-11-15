"""Real pinned-input reconciliation and fail-closed interface-contract checks.

No test here establishes native projection/ABI equivalence. Production schema1
has no approved transformation and cannot enable one through a status boolean.
"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
HELPER = ROOT / "Scripts/Expo/metadata-interface-partition.mjs"
CONTRACT = ROOT / "Scripts/Expo/metadata-interface-contract.json"
RN = ROOT / "Packages/HanlinExpoRuntime/Artifacts/ReactNativeHeaders.xcframework/ios-arm64_x86_64-simulator/Headers"
MODULAR = ROOT / "Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks"


class ExpoMetadataInterfacePartitionTests(unittest.TestCase):
    def setUp(self):
        self.node = shutil.which("node")
        if not self.node:
            self.skipTest("Node is required")
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.rn = self.directory / "rn"
        self.modular = self.directory / "modular"
        self.contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
        self.contract_path = self.directory / "contract.json"
        for name in self.contract["rnDependencyClosure"]:
            self.copy(RN / name, self.rn / name)
        for framework, group in self.contract["frameworks"].items():
            for entry in group["headers"] + [group["moduleMap"]]:
                name = framework + "/" + entry["generated"]
                self.copy(MODULAR / name, self.modular / name)
        self.save_contract()

    @staticmethod
    def copy(source, destination):
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)

    def save_contract(self):
        self.contract_path.write_text(json.dumps(self.contract), encoding="utf-8")

    def audit(self, *extra):
        return subprocess.run([
            self.node, str(HELPER), "--rn-headers", str(self.rn),
            "--modular-frameworks", str(self.modular), "--contract", str(self.contract_path), *extra,
        ], capture_output=True, text=True, encoding="utf-8", check=False)

    @staticmethod
    def tree_hashes(root):
        return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in root.rglob("*") if p.is_file()}

    def test_real_pinned_inventory_is_incomplete_and_never_writes_inputs(self):
        before = self.tree_hashes(self.directory)
        result = self.audit()
        self.assertEqual(result.returncode, 2, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["status"], "INCOMPLETE")
        self.assertFalse(report["projectionEnabled"])
        self.assertEqual(report["metadataInputRole"], "PUBLIC")
        self.assertEqual(len(report["sourceChecks"]), 22)
        self.assertEqual(len(report["generatedChecks"]), 22)
        self.assertEqual(report["sourceDrift"], [])
        self.assertTrue(report["missingFacts"])
        self.assertEqual(self.tree_hashes(self.directory), before)
        for group in self.contract["frameworks"].values():
            for header in group["headers"]:
                self.assertIsNone(header["publicCObjCInventory"]["declarations"])
                self.assertIsNone(header["languageRegions"])

    def test_new_objc_or_deployment_branch_invalidates_source_receipt(self):
        header = self.rn / "ReactCommon/CallInvoker.h"
        header.write_bytes(header.read_bytes() + b"\n#if defined(__OBJC__) && __ENVIRONMENT_IPHONE_OS_VERSION_MIN_REQUIRED__ >= 270000\nextern int actual_public_api;\n#endif\n")
        result = self.audit()
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertIn("ReactCommon/CallInvoker.h", json.loads(result.stdout)["sourceDrift"])

    def test_changed_transitive_macro_dependency_invalidates_source_receipt(self):
        header = self.rn / "react/cxxstableapi/UmbrellaGuard.h"
        header.write_bytes(header.read_bytes() + b"\n#define RN_EXTRA_PUBLIC_CONSTANT 7\n")
        result = self.audit()
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertIn("react/cxxstableapi/UmbrellaGuard.h", json.loads(result.stdout)["sourceDrift"])

    def test_differing_generated_jsi_bytes_are_retained_without_alias_or_rewrite(self):
        header = self.modular / "jsi.framework/Headers/jsi.h"
        header.write_bytes(header.read_bytes() + b"\n// independent owner variant\n")
        before = self.tree_hashes(self.directory)
        result = self.audit()
        self.assertEqual(result.returncode, 2, result.stderr)
        report = json.loads(result.stdout)
        row = next(x for x in report["generatedChecks"] if x["input"] == "jsi.framework/Headers/jsi.h")
        self.assertFalse(row["sourceEqual"])
        self.assertFalse(report["projectionEnabled"])
        self.assertEqual(self.tree_hashes(self.directory), before)

    def test_changed_module_map_is_source_drift(self):
        header = self.modular / "jsi.framework/Modules/module.modulemap"
        header.write_bytes(header.read_bytes() + b"\nmodule AddedSurface {}\n")
        result = self.audit()
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertIn("jsi.framework/Modules/module.modulemap", json.loads(result.stdout)["sourceDrift"])

    def test_omitted_transitive_guard_receipt_cannot_report_a_full_source_reconciliation(self):
        del self.contract["rnDependencyClosure"]["react/cxxstableapi/UmbrellaGuard.h"]
        self.save_contract()
        result = self.audit()
        self.assertEqual(result.returncode, 1)
        self.assertIn("Missing transitive source closure", result.stderr)

    def test_status_and_enabled_flags_cannot_activate_unimplemented_projection(self):
        for field, value in [("status", "COMPLETE"), ("productionProjectionEnabled", True), ("schemaVersion", 2)]:
            with self.subTest(field=field):
                original = self.contract[field]
                self.contract[field] = value
                self.save_contract()
                result = self.audit()
                self.assertEqual(result.returncode, 1)
                self.assertIn("incomplete inventory only", result.stderr)
                self.contract[field] = original

    def test_observed_sdk_context_and_perfetto_flag_do_not_approve_a_partition_profile(self):
        observed = self.contract["observedNativeCompilerContexts"][0]
        for macros in [{}, {"WITH_PERFETTO": "1"}]:
            with self.subTest(macros=macros):
                self.contract["approvedCompilerProfiles"] = [{"context": observed, "macros": macros}]
                self.save_contract()
                result = self.audit()
                self.assertEqual(result.returncode, 1)
                self.assertIn("no approved compilation profiles", result.stderr)

    def test_unleased_header_and_contract_path_traversal_are_rejected(self):
        group = self.contract["frameworks"]["jsi.framework"]
        header = group["headers"][0]
        original = dict(header)
        for field, value, reason in [("generated", "Headers/JSIDynamic.h", "scope changed"),
                                     ("source", "../outside.h", "Unsafe contract input path")]:
            with self.subTest(field=field):
                header[field] = value
                self.save_contract()
                result = self.audit()
                self.assertEqual(result.returncode, 1)
                self.assertIn(reason, result.stderr)
                header.clear()
                header.update(original)

    def test_evidence_output_cannot_overwrite_any_input_or_existing_file(self):
        existing = self.directory / "existing.json"
        existing.write_text("owner data", encoding="utf-8")
        before = self.tree_hashes(self.directory)
        for target in [self.rn / "new.json", self.modular / "new.json", existing, self.contract_path]:
            with self.subTest(target=target):
                result = self.audit("--output", str(target))
                self.assertEqual(result.returncode, 1)
        self.assertEqual(self.tree_hashes(self.directory), before)

    def test_valid_new_evidence_output_still_returns_incomplete(self):
        output = self.directory / "report.json"
        result = self.audit("--output", str(output))
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(json.loads(output.read_text())["status"], "INCOMPLETE")

    def test_renamed_framework_and_nested_path_do_not_acquire_preservation_scope(self):
        program = """
            const m = await import(process.argv[1]);
            const cases = [['ReactCommon.framework','CallInvoker.h'], ['jsi.framework','jsi.h'],
              ['NativeScript.framework','jsi.h'], ['jsi.framework','../jsi.h'],
              ['jsi.framework','JSIDynamic.h'], ['other.framework','CallInvoker.h']];
            process.stdout.write(JSON.stringify(cases.map(c => m.preservesPartitionUmbrellaContract(...c))));
        """
        result = subprocess.run([self.node, "--input-type=module", "-e", program, HELPER.as_uri()],
                                capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(result.stdout), [True, True, False, False, False, False])

    def test_even_fabricated_ready_report_cannot_enable_projection(self):
        program = """
            const m = await import(process.argv[1]);
            try { m.assertInterfacePartitionReady({status:'COMPLETE', projectionEnabled:true}); }
            catch (error) { process.stdout.write(error.message); process.exit(7); }
        """
        result = subprocess.run([self.node, "--input-type=module", "-e", program, HELPER.as_uri()],
                                capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 7)
        self.assertIn("no approved API/type contract", result.stdout)

    def test_actual_rn_umbrella_guard_preserves_strict_and_blessed_contexts(self):
        clang = shutil.which("clang")
        if not clang:
            self.skipTest("Actual Clang preprocessor is required")
        guard = self.rn / "react/cxxstableapi/UmbrellaGuard.h"
        for defines, expected in [([], 0), (["RN_STRICT_API"], 1),
                                  (["RN_STRICT_API", "RN_UMBRELLA_CONTEXT"], 0),
                                  (["RN_STRICT_API", "RN_BUILDING"], 0)]:
            with self.subTest(defines=defines):
                result = subprocess.run([clang, "-E", "-x", "c", *["-D" + x for x in defines], str(guard)],
                                        capture_output=True, text=True, check=False)
                self.assertEqual(result.returncode, expected, result.stderr)
                if expected:
                    self.assertIn("Do not include this React Native header directly", result.stderr)
        # The upstream guard must run on every include. A first blessed include
        # must not make a later direct include legal through pragma-once behavior.
        source = self.directory / "repeated.c"
        include = '#include "' + guard.as_posix() + '"\n'
        source.write_text('#define RN_STRICT_API 1\n#define RN_UMBRELLA_CONTEXT 1\n' + include +
                          '#undef RN_UMBRELLA_CONTEXT\n' + include, encoding="utf-8")
        result = subprocess.run([clang, "-E", "-x", "c", str(source)], capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Do not include this React Native header directly", result.stderr)


if __name__ == "__main__":
    unittest.main()
