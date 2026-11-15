import contextlib
import importlib.util
import io
import hashlib
import json
import sys
import os
from pathlib import Path
import shlex
import shutil
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("hanlin_metadata_wrapper", ROOT / "Scripts/NativeScript/build-step-metadata-generator-wrapper.py")
WRAPPER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(WRAPPER)
HEADER_SPEC = importlib.util.spec_from_file_location("metadata_public_headers", ROOT / "Scripts/NativeScript/metadata_public_headers.py")
HEADERS = importlib.util.module_from_spec(HEADER_SPEC)
HEADER_SPEC.loader.exec_module(HEADERS)


class NativeScriptMetadataWrapperTests(unittest.TestCase):
    def compiler_library(self):
        clang = shutil.which("clang")
        if sys.platform == "darwin":
            clang = WRAPPER.subprocess.check_output(["xcrun", "--find", "clang"], text=True).strip()
            path = Path(clang).resolve().parent.parent / "lib/libclang.dylib"
        else:
            path = Path(clang).parent / "libclang.dll" if clang else Path("missing")
        if not path.is_file():
            self.skipTest("Actual installed libclang is required for header-role fixtures")
        return path

    def test_actual_compiler_distinguishes_cpp_only_from_c_objc_and_mixed_declarations(self):
        cases = [
            ("namespace api { class Thing {}; int work(); }", HEADERS.CPP_ROLE),
            ("namespace api { class Thing { public: int method(); }; inline int work() { return 1; } }", HEADERS.CPP_ROLE),
            ("struct Opaque; using CppAlias = Opaque* (*)(); namespace api { class Thing {}; }", HEADERS.CPP_ROLE),
            ("struct Opaque;", HEADERS.PUBLIC_ROLE),
            ("extern \"C\" int c_api();", HEADERS.PUBLIC_ROLE),
            ("@interface NativeThing @end", HEADERS.PUBLIC_ROLE),
            ("namespace api { class Thing {}; } extern \"C\" int c_api();", HEADERS.PUBLIC_ROLE),
            ("namespace api { class Thing {}; } int c_compatible_api(void);", HEADERS.PUBLIC_ROLE),
            ("namespace api { extern \"C\" int nested_c_api(); }", HEADERS.PUBLIC_ROLE),
            ('#define API extern "C"\nnamespace api { API int macro_api(); }', HEADERS.PUBLIC_ROLE),
            ('namespace api { extern "C" int __attribute__((overloadable)) overloaded_c_api(int); }', HEADERS.PUBLIC_ROLE),
            ("namespace api { extern \"C\" int c_global; class Thing {}; }", HEADERS.PUBLIC_ROLE),
            ("namespace api { class Thing {}; } struct CRecord { int value; };", HEADERS.PUBLIC_ROLE),
            ("namespace api { class Thing {}; } enum CEnum { SomeValue };", HEADERS.PUBLIC_ROLE),
            ("namespace api { class Thing {}; } typedef int CValue; extern CValue global;", HEADERS.PUBLIC_ROLE),
            ("#define C_API(name) extern \"C\" int name();\nnamespace api { class Thing {}; } C_API(expanded_api)", HEADERS.PUBLIC_ROLE),
        ]
        library = self.compiler_library()
        with tempfile.TemporaryDirectory() as name:
            header = Path(name) / "entry.h"
            for source, expected in cases:
                with self.subTest(source=source):
                    header.write_text(source, encoding="utf-8")
                    proof = HEADERS.inspect_header_declarations([header], [], library)
                    self.assertEqual(proof["errors"], [])
                    self.assertEqual(proof["role"], expected)

    def test_verified_producer_roles_keep_search_dependencies_and_public_frameworks(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            cpp = self.framework(root / "products", "ArbitraryCppName")
            (cpp / "Headers/Exported.h").write_text("#pragma once\nnamespace api { class Thing {}; }\n")
            public = self.framework(root / "products", "PublicAPI")
            manifest = HEADERS.produce_role_inventory(cpp.parent, [], self.compiler_library())
            self.assertEqual([r["role"] for r in manifest["frameworks"]], [HEADERS.CPP_ROLE, HEADERS.PUBLIC_ROLE])
            umbrella = root / "input.h"
            with patch.dict(os.environ, {}, clear=True):
                records = HEADERS.write_public_umbrella(root, umbrella, [], [cpp.parent])
            self.assertEqual(records[0]["status"], "INCLUDE_SEARCH_ONLY_CPP")
            self.assertEqual(records[0]["modules"], ["ArbitraryCppName"])
            self.assertNotIn(str(cpp / "Headers/Entry.h"), umbrella.read_text())
            self.assertIn(str(public / "Headers/Entry.h"), umbrella.read_text())
            self.assertTrue((cpp / "Headers/Exported.h").exists())
            self.assertEqual(records[0]["inputSHA256"], HEADERS.framework_inputs(cpp))
            with patch.dict(os.environ, {"SDKROOT": str(root / "different-sdk")}):
                with self.assertRaisesRegex(RuntimeError, "SDK context changed"):
                    HEADERS.write_public_umbrella(root, root / "wrong-context.h", [], [cpp.parent])

    def test_role_receipt_rejects_unknown_role_tampering_future_headers_and_mixed_proof(self):
        library = self.compiler_library()
        for change in ["unknown-role", "changed-header", "future-c-api", "mixed-proof", "wrong-producer"]:
            with self.subTest(change=change), tempfile.TemporaryDirectory() as name:
                root = Path(name)
                framework = self.framework(root / "products", "CppFixture")
                (framework / "Headers/Exported.h").write_text("#pragma once\nnamespace api { class Thing {}; }\n")
                manifest = HEADERS.produce_role_inventory(framework.parent, [], library)
                record = manifest["frameworks"][0]
                if change == "unknown-role":
                    record["role"] = "skip-whatever"
                elif change == "changed-header":
                    (framework / "Headers/Exported.h").write_text("// changed header")
                elif change == "future-c-api":
                    (framework / "Headers/Future.h").write_text('extern "C" int new_public_api();')
                elif change == "mixed-proof":
                    record["proof"]["declarations"].append({"header": "Headers/Exported.h", "category": "public"})
                else:
                    manifest["producerSHA256"] = "0" * 64
                (framework.parent / HEADERS.ROLE_MANIFEST).write_text(json.dumps(manifest))
                with self.assertRaisesRegex(RuntimeError, "Framework input-role"):
                    HEADERS.write_public_umbrella(root, root / "input.h", [], [framework.parent])
                self.assertFalse((root / "input.h").exists())

    def test_failed_actual_role_parse_stays_a_public_root(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            framework = self.framework(root / "products", "BrokenCpp")
            (framework / "Headers/Exported.h").write_text("namespace api { class Broken : Missing {}; }\n")
            manifest = HEADERS.produce_role_inventory(framework.parent, [], self.compiler_library())
            self.assertTrue(manifest["frameworks"][0]["proof"]["errors"])
            self.assertEqual(manifest["frameworks"][0]["role"], HEADERS.PUBLIC_ROLE)
            HEADERS.write_public_umbrella(root, root / "input.h", [], [framework.parent])
            self.assertIn(str(framework / "Headers/Entry.h"), (root / "input.h").read_text())

    def test_regenerated_role_preserves_future_c_api_in_unreferenced_hpp_header(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            framework = self.framework(root / "products", "CppThenMixed")
            (framework / "Headers/Exported.h").write_text("#pragma once\nnamespace api { class Thing {}; }\n")
            library = self.compiler_library()
            first = HEADERS.produce_role_inventory(framework.parent, [], library)
            self.assertEqual(first["frameworks"][0]["role"], HEADERS.CPP_ROLE)
            (framework / "Headers/NewAPI.hpp").write_text('extern "C" int future_public_api();')
            updated = HEADERS.produce_role_inventory(framework.parent, [], library)
            self.assertEqual(updated["frameworks"][0]["role"], HEADERS.PUBLIC_ROLE)
            self.assertTrue(any(d["name"] == "future_public_api" and d["category"] == "public"
                                for d in updated["frameworks"][0]["proof"]["declarations"]))

    def framework(self, directory, name="ExpoModulesCore", module=None):
        framework = directory / (name + ".framework")
        (framework / "Modules").mkdir(parents=True)
        (framework / "Headers").mkdir()
        (framework / "Headers/Entry.h").write_text('#include "Exported.h"\n')
        (framework / "Headers/Exported.h").write_text("@interface EXExportedModule\n@end\n")
        (framework / "Modules/module.modulemap").write_text(
            'framework module ' + (module or name) + ' { umbrella header "Entry.h" export * }')
        return framework

    def test_identical_framework_copies_keep_search_order_and_all_unique_frameworks(self):
        with tempfile.TemporaryDirectory(prefix="Hanlin metadata ") as name:
            root = Path(name)
            # Lexical path order deliberately opposes compiler search priority.
            first = self.framework(root / "z-first")
            second = root / "a-second" / first.name
            shutil.copytree(first, second)
            unique = self.framework(root / "a-second", "OtherModule")
            umbrella = root / "input.h"
            records = HEADERS.write_public_umbrella(root, umbrella, [], [first.parent, second.parent, first.parent])
            self.assertEqual([r["status"] for r in records],
                             ["SELECTED", "DEDUPLICATED_IDENTICAL", "SELECTED"])
            self.assertIn(str(first / "Headers/Entry.h"), umbrella.read_text())
            self.assertNotIn(str(second / "Headers/Entry.h"), umbrella.read_text())
            self.assertIn(str(unique / "Headers/Entry.h"), umbrella.read_text())
            self.assertEqual(records[1]["selectedFrameworkPath"], str(first.resolve()))
            self.assertEqual(records[0]["inputSHA256"], records[1]["inputSHA256"])
            self.assertEqual(records[0]["modules"], ["ExpoModulesCore"])
            self.assertEqual(json.loads(umbrella.with_suffix(".inventory.json").read_text()), records)

    def test_differing_transitive_header_copy_fails_and_retains_both_manifests(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            first = self.framework(root / "first")
            second = root / "second" / first.name
            shutil.copytree(first, second)
            (second / "Headers/Exported.h").write_text("@interface DifferentExportedModule\n@end\n")
            umbrella = root / "input.h"
            with self.assertRaisesRegex(RuntimeError, "Conflicting framework/module headers") as error:
                HEADERS.write_public_umbrella(root, umbrella, [], [first.parent, second.parent])
            self.assertIn(str(first.resolve()), str(error.exception))
            self.assertIn(str(second.resolve()), str(error.exception))
            self.assertFalse(umbrella.exists())
            records = json.loads(umbrella.with_suffix(".inventory.json").read_text())
            self.assertEqual(records[1]["status"], "CONFLICT")
            self.assertEqual(records[0]["inputSHA256"]["Headers/Entry.h"], records[1]["inputSHA256"]["Headers/Entry.h"])
            self.assertNotEqual(records[0]["inputSHA256"]["Headers/Exported.h"], records[1]["inputSHA256"]["Headers/Exported.h"])

    def test_changed_module_map_or_missing_private_header_is_not_an_identical_copy(self):
        for change in ["module-map", "private-header"]:
            with self.subTest(change=change), tempfile.TemporaryDirectory() as name:
                root = Path(name)
                first = self.framework(root / "first")
                (first / "PrivateHeaders").mkdir()
                (first / "PrivateHeaders/Internal.h").write_text("// private declaration")
                second = root / "second" / first.name
                shutil.copytree(first, second)
                if change == "module-map":
                    with (second / "Modules/module.modulemap").open("a") as stream:
                        stream.write("\n// changed module map")
                else:
                    (second / "PrivateHeaders/Internal.h").unlink()
                with self.assertRaisesRegex(RuntimeError, "Conflicting framework/module headers"):
                    HEADERS.write_public_umbrella(root, root / "input.h", [], [first.parent, second.parent])

    def test_module_identity_collision_across_framework_names_fails(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            first = self.framework(root / "first")
            second = self.framework(root / "second", "Renamed", module="ExpoModulesCore")
            (second / "Headers/Exported.h").write_text("// different declaration")
            with self.assertRaisesRegex(RuntimeError, "Conflicting framework/module headers"):
                HEADERS.write_public_umbrella(root, root / "input.h", [], [first.parent, second.parent])

    def test_explicit_framework_paths_precede_sdk_default_without_importing_duplicates(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            explicit = self.framework(root / "build-products")
            sdk_copy = root / "System/Library/Frameworks" / explicit.name
            shutil.copytree(explicit, sdk_copy)
            records = HEADERS.write_public_umbrella(root, root / "input.h", [], [explicit.parent])
            self.assertEqual(records[0]["path"], str(explicit.resolve()))
            self.assertEqual(records[1]["status"], "DEDUPLICATED_IDENTICAL")

    def test_nested_submodules_do_not_conflict_with_unrelated_framework_owners(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            for framework_name in ["One", "Two"]:
                framework = self.framework(root / "products", framework_name)
                (framework / "Modules/module.modulemap").write_text(
                    '/* module Wrong {} */ framework module ' + framework_name +
                    ' { umbrella header "Entry.h" module Common { export * } }\n'
                    'extern module Shared "External{Map}.modulemap"')
            records = HEADERS.write_public_umbrella(root, root / "input.h", [], [root / "products"])
            self.assertEqual([r["modules"] for r in records], [["One"], ["Two"]])
            self.assertTrue(all(r["status"] == "SELECTED" for r in records))

    def test_framework_entry_selection_excludes_internal_roots_and_explicit_private_headers(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            public = root / "System/Library/Frameworks/Public.framework"
            internal = root / "System/Library/SubFrameworks/FocusEngine.framework"
            for framework in [public, internal]:
                (framework / "Modules").mkdir(parents=True)
                (framework / "Headers").mkdir()
                (framework / "Headers/Entry.h").write_text("// public header fixture")
                (framework / "Headers/Private.h").write_text("// explicit private header fixture")
                (framework / "Modules/module.modulemap").write_text('framework module Entry {\n umbrella "."\n private header "Private.h"\n}')
            umbrella = root / "input.h"
            records = HEADERS.write_public_umbrella(root, umbrella, [])
            self.assertEqual(len(records), 1)
            self.assertIn(str(public / "Headers/Entry.h"), umbrella.read_text())
            self.assertNotIn("FocusEngine", umbrella.read_text())
            self.assertNotIn("Private.h", umbrella.read_text())

    def test_real_clang_errors_reject_partial_metadata_even_when_required_classes_exist(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            binary = b"\0".join(n.encode() for n in WRAPPER.REQUIRED_METADATA_NAMES) + b"\0"
            (root / "metadata-arm64.bin").write_bytes(binary)
            diagnostic = root / "metadata-generation-stderr-arm64.txt"
            with patch.dict(os.environ, {"SRCROOT": str(root), "CONFIGURATION_BUILD_DIR": str(root)}), \
                 contextlib.redirect_stdout(io.StringIO()):
                for text in ["/SDK/Header.h:12:3: error: bad declaration\n", "fatal error: missing SDK header\n"]:
                    diagnostic.write_text(text)
                    self.assertFalse(WRAPPER.retain_and_check_metadata("arm64", "iphonesimulator"))
                diagnostic.write_text("verbose: selector initWithValue:error: is available\n")
                self.assertTrue(WRAPPER.retain_and_check_metadata("arm64", "iphonesimulator"))

    def test_objc_headers_keep_their_existing_owner_and_import_paths_roundtrip_spaces(self):
        with tempfile.TemporaryDirectory(prefix="Hanlin metadata ") as name:
            root = Path(name)
            header = root / "Runtime-Swift.h"
            header.write_text("// generated header")
            module = root / "module.modulemap"
            WRAPPER.write_swift_module_map(module, header, "arm64")
            text = module.read_text()
            self.assertIn(str(header.resolve()), text)
            self.assertNotIn("HanlinNativeServicesBridge.h", text)
            flags = shlex.split(WRAPPER.metadata_flags(root, module, ROOT / "Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptCoreSupport/include"))
            self.assertEqual(flags[0], "-fno-modules")
            self.assertIn(f"-fmodule-map-file={module}", flags)
            self.assertNotIn("-include", flags)

    def test_upstream_success_without_bridge_metadata_fails_and_keeps_diagnostics(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            generator = root / "generator"
            generator.mkdir()
            (generator / "build-step-metadata-generator-upstream.py").write_text(
                'def generate_metadata():\n    generator_call = ["./objc-metadata-generator", "-verbose",]\n    # clang arguments\n')
            objroot = root / "intermediates"
            header = objroot / "GeneratedModuleMaps-iphonesimulator/HanlinNativeScriptRuntime-Swift.h"
            header.parent.mkdir(parents=True)
            header.write_text("// generated header")
            products = root / "products"
            products.mkdir()
            diagnostic = products / "metadata-generation-stderr-arm64.txt"
            diagnostic.write_text("error: missing native module\n")
            (products / "metadata-arm64.bin").write_bytes(b"NSObject\0UIView\0")
            tool = root / "build/nativescript-metadata-tool"
            (tool / "bin").mkdir(parents=True)
            (tool / "bin/objc-metadata-generator").write_bytes(b"tool fixture")
            scripts = root / "Scripts/NativeScript"
            scripts.mkdir(parents=True)
            (scripts / "build-metadata-tool.py").write_text("# pinned source fixture")
            (tool / "provenance.json").write_text(json.dumps({
                "generatorSHA256": hashlib.sha256(b"tool fixture").hexdigest(),
                "patchSourceSHA256": hashlib.sha256((scripts / "build-metadata-tool.py").read_bytes()).hexdigest()}))
            sdk = root / "sdk"
            framework = sdk / "System/Library/Frameworks/UIKit.framework"
            (framework / "Modules").mkdir(parents=True)
            (framework / "Headers").mkdir()
            (framework / "Headers/UIKit.h").write_text("// SDK fixture")
            (framework / "Modules/module.modulemap").write_text('framework module UIKit { umbrella header "UIKit.h" }')
            env = {"OBJROOT": str(objroot), "SRCROOT": str(root), "TARGET_TEMP_DIR": str(root / "target"),
                   "PLATFORM_NAME": "iphonesimulator", "CONFIGURATION_BUILD_DIR": str(products), "SDKROOT": str(sdk)}
            with patch.dict(os.environ, env), patch.object(WRAPPER, "__file__", str(generator / "wrapper.py")), \
                 patch.object(WRAPPER.sys, "argv", ["wrapper", "arm64"]), \
                 patch.dict(sys.modules, {"metadata_public_headers": HEADERS}), \
                 patch.object(WRAPPER.subprocess, "run") as run, contextlib.redirect_stdout(io.StringIO()):
                run.return_value.returncode = 0
                self.assertEqual(WRAPPER.main(), 1)
            retained = root / "build/acceptance/nativescript-metadata/iphonesimulator-arm64"
            self.assertEqual((retained / diagnostic.name).read_bytes(), diagnostic.read_bytes())
            self.assertEqual((retained / "metadata-arm64.bin").read_bytes(), b"NSObject\0UIView\0")
            self.assertIn('"HanlinNativeServicesBridge": false', (retained / "visibility.json").read_text())
            # Discovery errors must also keep their provenance before cleanup;
            # the generator must never run after differing copies are found.
            duplicate = root / "duplicate-products/UIKit.framework"
            shutil.copytree(framework, duplicate)
            (duplicate / "Headers/UIKit.h").write_text("// conflicting SDK declaration")
            env["FRAMEWORK_SEARCH_PATHS"] = shlex.quote(str(duplicate.parent))
            with patch.dict(os.environ, env), patch.object(WRAPPER, "__file__", str(generator / "wrapper.py")), \
                 patch.object(WRAPPER.sys, "argv", ["wrapper", "arm64"]), \
                 patch.dict(sys.modules, {"metadata_public_headers": HEADERS}), \
                 patch.object(WRAPPER.subprocess, "run") as run:
                with self.assertRaisesRegex(RuntimeError, "Conflicting framework/module headers"):
                    WRAPPER.main()
                run.assert_not_called()
            inventory = json.loads((retained / "HanlinMetadataInput.inventory.json").read_text())
            self.assertEqual(inventory[-1]["status"], "CONFLICT")
            self.assertEqual(inventory[0]["path"], str(duplicate.resolve()))


if __name__ == "__main__":
    unittest.main()
