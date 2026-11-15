import contextlib
import copy
import importlib.util
import io
import hashlib
import json
import sys
import os
import re
from pathlib import Path, PurePosixPath
import shlex
import shutil
import subprocess
import tempfile
import types
import unittest
from unittest.mock import Mock, patch


ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("hanlin_metadata_wrapper", ROOT / "Scripts/NativeScript/build-step-metadata-generator-wrapper.py")
WRAPPER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(WRAPPER)
HEADER_SPEC = importlib.util.spec_from_file_location("metadata_public_headers", ROOT / "Scripts/NativeScript/metadata_public_headers.py")
HEADERS = importlib.util.module_from_spec(HEADER_SPEC)
HEADER_SPEC.loader.exec_module(HEADERS)


class NativeScriptMetadataWrapperTests(unittest.TestCase):
    def setUp(self):
        # Portable fixtures establish their own target context, preserving compiler lookup.
        environment = {key: value for key, value in os.environ.items()
                       if key not in {"SDKROOT", "ARCHS", "PLATFORM_NAME", "IPHONEOS_DEPLOYMENT_TARGET"}}
        reset = patch.dict(os.environ, environment, clear=True)
        reset.start()
        self.addCleanup(reset.stop)

    def produce_roles(self, directory, arguments, library, **options):
        # These portable fixtures use the actual same libclang frontend as their
        # expected consumer; this is not a NativeScript/Apple metadata pass.
        metadata = options.pop("metadata_compiler", {"compiler": HEADERS.compiler_version(library), "arguments": arguments})
        return HEADERS.produce_role_inventory(directory, arguments, library, metadata_compiler=metadata, **options)

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
            for target in [[], ["-target", "arm64-apple-ios27.2-simulator"]]:
                for source, expected in cases:
                    with self.subTest(source=source, target=target):
                        header.write_text(source, encoding="utf-8")
                        proof = HEADERS.inspect_header_declarations([header], target, library)
                        self.assertEqual(proof["errors"], [])
                        self.assertEqual(proof["role"], expected)

    def test_verified_producer_roles_keep_search_dependencies_and_public_frameworks(self):
        with tempfile.TemporaryDirectory() as name, patch.dict(os.environ, {k: v for k, v in os.environ.items() if k not in {"SDKROOT", "ARCHS", "PLATFORM_NAME", "IPHONEOS_DEPLOYMENT_TARGET"}}, clear=True):
            root = Path(name)
            cpp = self.framework(root / "products", "ArbitraryCppName")
            (cpp / "Headers/Exported.h").write_text("#pragma once\n#ifdef __cplusplus\nnamespace api { class Thing {}; }\n#endif\n")
            public = self.framework(root / "products", "PublicAPI")
            manifest = self.produce_roles(cpp.parent, [], self.compiler_library())
            self.assertEqual([r["role"] for r in manifest["frameworks"]], [HEADERS.CPP_ROLE, HEADERS.PUBLIC_ROLE])
            umbrella = root / "input.h"
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
        for change in ["unknown-role", "changed-header", "future-c-api", "mixed-proof", "wrong-producer", "missing-compiler", "missing-objc-audit", "objc-errors", "objc-incomplete", "objc-wrong-mode", "objc-unknown", "objc-public", "objc-arguments", "missing-native-compiler", "changed-native-compiler", "changed-native-arguments"]:
            with self.subTest(change=change), tempfile.TemporaryDirectory() as name:
                root = Path(name)
                framework = self.framework(root / "products", "CppFixture")
                (framework / "Headers/Exported.h").write_text("#pragma once\n#ifdef __cplusplus\nnamespace api { class Thing {}; }\n#endif\n")
                manifest = self.produce_roles(framework.parent, [], library)
                record = manifest["frameworks"][0]
                if change == "unknown-role":
                    record["role"] = "skip-whatever"
                elif change == "changed-header":
                    (framework / "Headers/Exported.h").write_text("// changed header")
                elif change == "future-c-api":
                    (framework / "Headers/Future.h").write_text('extern "C" int new_public_api();')
                elif change == "mixed-proof":
                    record["proof"]["declarations"].append({"header": "Headers/Exported.h", "category": "public"})
                elif change == "wrong-producer":
                    manifest["producerSHA256"] = "0" * 64
                elif change == "missing-compiler":
                    del manifest["compilerLibrarySHA256"]
                elif change == "missing-objc-audit":
                    del record["proof"]["objcCompatibility"]
                elif change == "missing-native-compiler":
                    del manifest["metadataCompiler"]
                elif change == "changed-native-compiler":
                    manifest["metadataCompiler"]["compiler"] = "Unproven frontend"
                elif change == "changed-native-arguments":
                    manifest["metadataCompiler"]["arguments"] = ["-DUNKNOWN_CONTEXT=1"]
                else:
                    objc = record["proof"]["objcCompatibility"]
                    if change == "objc-errors":
                        objc["errors"] = ["fatal error: dependency missing"]
                    elif change == "objc-incomplete":
                        objc["complete"] = False
                    elif change == "objc-wrong-mode":
                        objc["language"] = "objective-c++"
                    elif change == "objc-arguments":
                        objc["arguments"].append("-DUNPROVEN=1")
                    else:
                        objc["declarations"].append({"header": "Headers/Exported.h", "category": "unknown" if change == "objc-unknown" else "public"})
                (framework.parent / HEADERS.ROLE_MANIFEST).write_text(json.dumps(manifest))
                with self.assertRaisesRegex(RuntimeError, "Framework input-role"):
                    HEADERS.write_public_umbrella(root, root / "input.h", [], [framework.parent])
                self.assertFalse((root / "input.h").exists())

    def test_failed_actual_role_parse_stays_a_public_root(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            framework = self.framework(root / "products", "BrokenCpp")
            (framework / "Headers/Exported.h").write_text("namespace api { class Broken : Missing {}; }\n")
            manifest = self.produce_roles(framework.parent, [], self.compiler_library())
            self.assertTrue(manifest["frameworks"][0]["proof"]["errors"])
            self.assertEqual(manifest["frameworks"][0]["role"], HEADERS.PUBLIC_ROLE)
            HEADERS.write_public_umbrella(root, root / "input.h", [], [framework.parent])
            self.assertIn(str(framework / "Headers/Entry.h"), (root / "input.h").read_text())

    def test_regenerated_role_preserves_future_c_api_in_unreferenced_hpp_header(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            framework = self.framework(root / "products", "CppThenMixed")
            (framework / "Headers/Exported.h").write_text("#pragma once\n#ifdef __cplusplus\nnamespace api { class Thing {}; }\n#endif\n")
            library = self.compiler_library()
            first = self.produce_roles(framework.parent, [], library)
            self.assertEqual(first["frameworks"][0]["role"], HEADERS.CPP_ROLE)
            (framework / "Headers/NewAPI.hpp").write_text('extern "C" int future_public_api();')
            updated = self.produce_roles(framework.parent, [], library)
            self.assertEqual(updated["frameworks"][0]["role"], HEADERS.PUBLIC_ROLE)
            self.assertTrue(any(d["name"] == "future_public_api" and d["category"] == "public"
                                for d in updated["frameworks"][0]["proof"]["declarations"]))

    def test_objc_branch_c_api_keeps_a_dual_language_framework_public(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            framework = self.framework(root / "products", "DualLanguage")
            (framework / "Headers/Exported.h").write_text(
                '#pragma once\n#ifdef __cplusplus\nnamespace api { class Thing {}; }\n'
                '#else\nint supported_c_api(void);\n#endif\n')
            manifest = self.produce_roles(framework.parent, [], self.compiler_library())
            proof = manifest["frameworks"][0]["proof"]
            self.assertEqual(manifest["frameworks"][0]["role"], HEADERS.PUBLIC_ROLE)
            self.assertEqual(proof["objcCompatibility"]["errors"], [])
            self.assertTrue(any(d["name"] == "supported_c_api" for d in proof["objcCompatibility"]["declarations"]))

    def test_objc_errors_cannot_hide_conditional_public_declarations(self):
        with tempfile.TemporaryDirectory() as name:
            framework = self.framework(Path(name) / "products", "IncompleteAudit")
            (framework / "Headers/Exported.h").write_text(
                '#pragma once\nnamespace api { class Thing {}; }\n'
                '#ifndef __cplusplus\nextern int actual_objc_branch_api(void);\n#endif\n')
            manifest = self.produce_roles(framework.parent, [], self.compiler_library())
            record = manifest["frameworks"][0]
            self.assertTrue(record["proof"]["objcCompatibility"]["errors"])
            self.assertFalse(record["proof"]["objcCompatibility"]["complete"])
            self.assertEqual(record["role"], HEADERS.PUBLIC_ROLE)
            # Even rewriting this newly issued public receipt into the old unsafe
            # CPP form must not revive the error-bearing compatibility audit.
            record["role"] = record["proof"]["role"] = HEADERS.CPP_ROLE
            (framework.parent / HEADERS.ROLE_MANIFEST).write_text(json.dumps(manifest))
            with self.assertRaisesRegex(RuntimeError, "complete ObjC"):
                HEADERS.verified_framework_roles(framework.parent)

    def test_target_only_mismatch_and_actual_deployment_branch_are_bound(self):
        with tempfile.TemporaryDirectory() as name:
            framework = self.framework(Path(name) / "products", "DeploymentBranch")
            (framework / "Headers/Exported.h").write_text(
                '#pragma once\n#ifdef __cplusplus\nnamespace api { class Thing {}; }\n'
                '#elif __ENVIRONMENT_IPHONE_OS_VERSION_MIN_REQUIRED__ >= 270100\n'
                'extern int newer_public_api(void);\n#endif\n')
            library = self.compiler_library()
            arguments = ["-target", "arm64-apple-ios27.0-simulator"]
            before = self.produce_roles(framework.parent, arguments, library)
            self.assertEqual(before["frameworks"][0]["role"], HEADERS.CPP_ROLE)
            with self.assertRaisesRegex(RuntimeError, "parser arguments changed"):
                HEADERS.verified_framework_roles(framework.parent, ["-target", "arm64-apple-ios27.2-simulator"])
            after = self.produce_roles(framework.parent, ["-target", "arm64-apple-ios27.2-simulator"], library)
            self.assertEqual(after["frameworks"][0]["role"], HEADERS.PUBLIC_ROLE)
            self.assertTrue(any(d["name"] == "newer_public_api" for d in after["frameworks"][0]["proof"]["objcCompatibility"]["declarations"]))
            sdk = str(Path(name) / "same-sdk")
            with patch.dict(os.environ, {"SDKROOT": sdk, "ARCHS": "arm64", "PLATFORM_NAME": "iphonesimulator", "IPHONEOS_DEPLOYMENT_TARGET": "27.0"}):
                with self.assertRaisesRegex(RuntimeError, "deployment/environment"):
                    HEADERS.verify_role_context(["-isysroot", sdk, "-target", "arm64-apple-ios27.2-simulator"])
                HEADERS.verify_role_context(["-isysroot", sdk, "-target", "arm64-apple-ios27.0.0-simulator"])

    def test_postreceipt_staging_requires_full_reclassification(self):
        with tempfile.TemporaryDirectory() as name, patch.dict(os.environ, {k: v for k, v in os.environ.items() if k not in {"SDKROOT", "ARCHS", "PLATFORM_NAME", "IPHONEOS_DEPLOYMENT_TARGET"}}, clear=True):
            framework = self.framework(Path(name) / "products", "StagedCpp")
            header = framework / "Headers/Exported.h"
            header.write_text('#pragma once\n#ifdef __cplusplus\nnamespace api { class Thing {}; }\n#endif\n')
            library = self.compiler_library()
            first = self.produce_roles(framework.parent, [], library)
            self.assertEqual(first["frameworks"][0]["role"], HEADERS.CPP_ROLE)
            header.write_text(header.read_text() + '// legitimate later staging comment\n')
            with self.assertRaisesRegex(RuntimeError, "identity/headers changed"):
                HEADERS.verified_framework_roles(framework.parent)
            self.produce_roles(framework.parent, [], library)
            self.assertEqual(HEADERS.verified_framework_roles(framework.parent)[framework.name]["role"], HEADERS.CPP_ROLE)
            header.write_text(header.read_text() + '#ifndef __cplusplus\nextern int staged_public_api(void);\n#endif\n')
            updated = self.produce_roles(framework.parent, [], library)
            self.assertEqual(updated["frameworks"][0]["role"], HEADERS.PUBLIC_ROLE)

    def test_changed_transitive_parser_dependency_rejects_receipt(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            framework = self.framework(root / "products", "DependencyAudit")
            dependency = root / "dependency.h"
            dependency.write_text('// genuine dependency\n')
            (framework / "Headers/Exported.h").write_text(
                '#pragma once\n#include "' + str(dependency).replace('\\', '/') + '"\n'
                '#ifdef __cplusplus\nnamespace api { class Thing {}; }\n#endif\n')
            self.produce_roles(framework.parent, [], self.compiler_library())
            dependency.write_text('// changed dependency\n')
            with self.assertRaisesRegex(RuntimeError, "parser dependency changed"):
                HEADERS.verified_framework_roles(framework.parent)

    def test_actual_adapter_capture_binds_deployment_and_order_without_running_generator(self):
        source = '''
import os, subprocess
class Child: pass
def fixture_popen(*args, **kwargs):
    with open("fixture-generator-reached.txt", "w") as output: output.write(os.getcwd())
    return Child()
subprocess.Popen = fixture_popen
sdk_root = "/actual SDK"
llvm_target_triple_vendor = "apple"
llvm_target_triple_os_version = "ios27.2"
llvm_target_triple_suffix = "-simulator"
deployment_target = "27.0"
def env(name): return os.environ[name]
def generate_metadata(arch):
    generator_call = ["./objc-metadata-generator", "-verbose",]
    # clang arguments
    generator_call.extend(["Xclang", "-isysroot", sdk_root, "-std=gnu17", "-target", "{}-{}-{}{}".format(arch, llvm_target_triple_vendor, llvm_target_triple_os_version, llvm_target_triple_suffix)])
    generator_call.extend(["-Irelative/include", "-Frelative/framework", "-ivfsoverlay", "relative/aliases.json", "-DCONDITIONAL_API=1"])
    child_process = subprocess.Popen(generator_call, stderr=subprocess.PIPE, universal_newlines=True)
generate_metadata("arm64")
'''
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            (root / "adapter-location").mkdir()
            (root / "generator-location").mkdir()
            adapter = root / "adapter-location/adapter.py"
            adapter.write_text(WRAPPER.explicit_input_adapter(source))
            plan = root / "arguments.json"
            actual = root / "actual.json"
            env = {**os.environ, "HANLIN_METADATA_GENERATOR": "must-not-run", "HANLIN_METADATA_INPUT_UMBRELLA": "actual-input.h",
                   "HANLIN_METADATA_EXPECTED_CONTEXT": str(plan), "HANLIN_METADATA_ACTUAL_CONTEXT": str(actual)}
            directory = root / "generator-location"
            arguments = WRAPPER.capture_compiler_arguments(adapter, env, "arm64", plan, directory)
            self.assertEqual(arguments, ["-isysroot", "/actual SDK", "-std=gnu17", "-target", "arm64-apple-ios27.0-simulator", "-Irelative/include", "-Frelative/framework", "-ivfsoverlay", "relative/aliases.json", "-DCONDITIONAL_API=1"])
            completed = WRAPPER.subprocess.run([sys.executable, str(adapter)], cwd=directory, env=env, capture_output=True, text=True)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(json.loads(plan.read_text()), json.loads(actual.read_text()))
            self.assertTrue((directory / "fixture-generator-reached.txt").is_file())
            drift = WRAPPER.subprocess.run([sys.executable, str(adapter)], cwd=adapter.parent, env=env, capture_output=True, text=True)
            self.assertNotEqual(drift.returncode, 0)
            self.assertIn("context drifted", drift.stderr)
            self.assertFalse((adapter.parent / "fixture-generator-reached.txt").exists())
            changed = WRAPPER.subprocess.run([sys.executable, str(adapter)], cwd=directory, env={**env, "CPATH": "changed-relative-path"}, capture_output=True, text=True)
            self.assertNotEqual(changed.returncode, 0)
            self.assertIn("context drifted", changed.stderr)

    def test_staging_without_actual_target_grants_no_cpp_role(self):
        with tempfile.TemporaryDirectory() as name:
            framework = self.framework(Path(name) / "products", "TargetPending")
            (framework / "Headers/Exported.h").write_text('namespace api { class Thing {}; }')
            inventory = self.produce_roles(framework.parent, [], self.compiler_library(), classify=False)
            self.assertEqual(inventory["frameworks"][0]["role"], HEADERS.PUBLIC_ROLE)
            self.assertNotIn("objcCompatibility", inventory["frameworks"][0]["proof"])

    def test_relative_parser_paths_and_environment_cannot_drift_after_audit(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            library = self.compiler_library()
            framework = self.framework(root / "products", "RelativeAudit")
            header = framework / "Headers/Exported.h"
            header.write_text('#pragma once\n#include <condition.h>\n#ifdef __cplusplus\nnamespace api { class Thing {}; }\n#elif EXPOSE_API\nextern int actual_c_api(void);\n#endif\n')
            first, second = root / "first", root / "second"
            for folder, expose in [(first, 0), (second, 1)]:
                (folder / "relative/include").mkdir(parents=True)
                (folder / "relative/framework").mkdir()
                (folder / "relative/include/condition.h").write_text('#define EXPOSE_API ' + str(expose) + '\n')
                (folder / "relative/aliases.json").write_text('{"version":0,"roots":[]}')
            arguments = ["-Irelative/include", "-Frelative/framework", "-ivfsoverlay", "relative/aliases.json"]
            with patch.dict(os.environ, {}, clear=True), HEADERS.compiler_working_directory(first):
                inventory = self.produce_roles(framework.parent, arguments, library)
                self.assertEqual(inventory["frameworks"][0]["role"], HEADERS.CPP_ROLE)
                HEADERS.verified_framework_roles(framework.parent, arguments)
                with patch.dict(os.environ, {"CPATH": "different"}):
                    with self.assertRaisesRegex(RuntimeError, "compiler environment changed"):
                        HEADERS.verified_framework_roles(framework.parent, arguments)
            with patch.dict(os.environ, {}, clear=True), HEADERS.compiler_working_directory(second):
                with self.assertRaisesRegex(RuntimeError, "working directory changed"):
                    HEADERS.verified_framework_roles(framework.parent, arguments)
                updated = self.produce_roles(framework.parent, arguments, library)
                self.assertEqual(updated["frameworks"][0]["role"], HEADERS.PUBLIC_ROLE)

    def test_complete_header_staging_preserves_default_and_skips_only_explicit_signing(self):
        spec = importlib.util.spec_from_file_location("actual_modular_stage", ROOT / "Scripts/CI/stage_modular_headers.py")
        staging = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(staging)
        results = []
        with tempfile.TemporaryDirectory() as name:
            for skip in [False, True]:
                root = Path(name) / str(skip)
                artifacts, packages, derived = root / "Artifacts", root / "SourcePackages", root / "DerivedData"
                react = artifacts / "React.xcframework/ios-arm64_x86_64-simulator/React.framework/Headers"
                react.mkdir(parents=True)
                source = artifacts / "ModularFrameworks/react.framework/Headers/Existing.h"
                source.parent.mkdir(parents=True)
                source.write_text('#include <jsi/JSIDynamic.h>\n')
                rn = artifacts / "ReactNativeHeaders.xcframework/ios-arm64_x86_64-simulator/Headers/ReactCommon/CallInvoker.h"
                rn.parent.mkdir(parents=True)
                rn.write_text('// actual copy input fixture\n')
                checkout = packages / "checkouts/consumer"
                checkout.mkdir(parents=True)
                (checkout / "Package.swift").write_text('// Hanlin consumer fixture')
                options = {"sign_xcframeworks": False} if skip else {}
                with patch.object(staging, "resign_xcframework", return_value=True) as sign, contextlib.redirect_stdout(io.StringIO()):
                    result = staging.stage_modular_headers(packages, artifacts, derived_data_dir=derived,
                        force=True, configurations=["Debug"], run_patch_hash_combine=False, **options)
                self.assertEqual(result["status"], "SUCCESS")
                self.assertEqual(sign.call_count == 0, skip)
                self.assertEqual((react / "ReactCommon/CallInvoker.h").read_bytes(), rn.read_bytes())
                self.assertIn('__has_include', (react / "Existing.h").read_text())
                self.assertTrue((checkout / "Artifacts/ModularFrameworks/react.framework/Headers/Existing.h").is_file())
                results.append({p.relative_to(root).as_posix(): p.read_bytes() for p in root.rglob("*")
                                if p.is_file() and (p.suffix in {".h", ".hpp"} or p.name == "module.modulemap")})
            self.assertEqual(results[0], results[1])

    def test_signing_mode_transitions_invalidate_same_path_stamps(self):
        spec = importlib.util.spec_from_file_location("actual_signing_stamp_stage", ROOT / "Scripts/CI/stage_modular_headers.py")
        staging = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(staging)
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            artifacts, packages, derived = root / "Artifacts", root / "SourcePackages", root / "DerivedData"
            headers = artifacts / "ReactNativeHeaders.xcframework/ios-arm64_x86_64-simulator/Headers"
            for relative in ["React/React-umbrella.h", "folly/dynamic.h", "folly/json/dynamic.h", "jsi/JSIDynamic.h"]:
                file = headers / relative
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text('// owned completeness input\n')
            packages.mkdir()
            snapshots = []
            # Covers unsigned→default and default→unsigned→default on identical paths.
            for index, enabled in enumerate([False, True, False, True, True]):
                options = {} if enabled else {"sign_xcframeworks": False}
                with patch.object(staging, "resign_xcframework", return_value=True) as sign, contextlib.redirect_stdout(io.StringIO()):
                    result = staging.stage_modular_headers(packages, artifacts, derived_data_dir=derived,
                        configurations=["Debug"], run_patch_hash_combine=False, **options)
                self.assertEqual(result["status"], "SKIPPED_STAMP_MATCH" if index == 4 else "SUCCESS")
                self.assertEqual(sign.call_count > 0, enabled and index != 4)
                snapshots.append({p.relative_to(root).as_posix(): p.read_bytes() for p in root.rglob("*.h")})
                for stamp in [packages / ".modular_headers_staged", derived / "CacheMetadata/.modular_headers_staged"]:
                    self.assertIs(json.loads(stamp.read_text())["sign_xcframeworks"], enabled)
            self.assertTrue(all(value == snapshots[0] for value in snapshots))
            # A legacy/unknown signing stamp is never accepted as a signed cache hit.
            for stamp in [packages / ".modular_headers_staged", derived / "CacheMetadata/.modular_headers_staged"]:
                document = json.loads(stamp.read_text())
                document.pop("sign_xcframeworks")
                stamp.write_text(json.dumps(document))
            with patch.object(staging, "resign_xcframework", return_value=True) as sign, contextlib.redirect_stdout(io.StringIO()):
                result = staging.stage_modular_headers(packages, artifacts, derived_data_dir=derived,
                    configurations=["Debug"], run_patch_hash_combine=False)
            self.assertEqual(result["status"], "SUCCESS")
            self.assertGreater(sign.call_count, 0)

    def test_generator_macro_and_frontend_identity_cannot_hide_public_api(self):
        with tempfile.TemporaryDirectory() as name:
            framework = self.framework(Path(name) / "products", "ActualGeneratorContext")
            (framework / "Headers/Exported.h").write_text(
                '#pragma once\n#ifdef __cplusplus\nnamespace api { class Thing {}; }\n'
                '#elif __NATIVESCRIPT_METADATA_GENERATOR\nextern int metadata_only_public_api(void);\n#endif\n')
            library = self.compiler_library()
            flags = ["-x", "objective-c", "-fno-objc-arc", "-D__NATIVESCRIPT_METADATA_GENERATOR=1"]
            manifest = self.produce_roles(framework.parent, flags, library)
            self.assertEqual(manifest["frameworks"][0]["role"], HEADERS.PUBLIC_ROLE)
            (framework / "Headers/Exported.h").write_text('#pragma once\n#ifdef __cplusplus\nnamespace api { class Thing {}; }\n#endif\n')
            changed = self.produce_roles(framework.parent, flags, library,
                metadata_compiler={"compiler": "A different real metadata frontend", "arguments": flags})
            self.assertEqual(changed["frameworks"][0]["role"], HEADERS.PUBLIC_ROLE)
            unknown = self.produce_roles(framework.parent, flags, library, metadata_compiler=None)
            self.assertEqual(unknown["frameworks"][0]["role"], HEADERS.PUBLIC_ROLE)

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

    def test_explicit_public_module_headers_precede_same_named_convenience_header(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            framework = self.framework(root / "products", "Public")
            (framework / "Headers/Public.h").write_text("// does not import Additional.h")
            (framework / "Headers/Additional.h").write_text("extern int actual_public_c_api(void);")
            (framework / "Modules/module.modulemap").write_text(
                'framework module Public {\n header "Public.h"\n header "Additional.h"\n export *\n}\n')
            umbrella = root / "input.h"
            records = HEADERS.write_public_umbrella(root, umbrella, [], [framework.parent])
            self.assertEqual([Path(h["path"]).name for h in records[0]["publicUmbrellaHeaders"]], ["Public.h", "Additional.h"])
            self.assertIn(str(framework / "Headers/Additional.h"), umbrella.read_text())

    def test_identical_header_alias_overlay_preserves_c_api_and_real_clang_identity(self):
        with tempfile.TemporaryDirectory(prefix="Hanlin aliases ") as name:
            root = Path(name)
            owner = self.framework(root / "products", "lower")
            header = owner / "Headers/Exported.h"
            header.write_text("#pragma once\nenum ActualEnum { ActualValue };\nint actual_public_c_api(void);\n")
            (owner / "Modules/module.modulemap").write_text(
                'framework module lower {\n header "Exported.h"\n export *\n}\n')
            alias = root / "products/Carrier.framework/Headers/lower/Exported.h"
            alias.parent.mkdir(parents=True)
            shutil.copytree(owner / "Headers", alias.parent, dirs_exist_ok=True)
            records = HEADERS.write_public_umbrella(root, root / "input.h", [], [owner.parent])
            library = self.compiler_library()
            before = HEADERS.inspect_header_declarations([header, alias], [], library, "objective-c")
            self.assertTrue(before["errors"], "Different physical pragma-once files must genuinely reproduce redefinition")
            overlay = root / "aliases.json"
            evidence = HEADERS.write_verified_header_alias_overlay(records, overlay)
            self.assertEqual(len(evidence), 1)
            self.assertEqual(evidence[0]["module"], "lower")
            after = HEADERS.inspect_header_declarations([header, alias], ["-ivfsoverlay", str(overlay)], library, "objective-c")
            self.assertEqual(after["errors"], [])
            self.assertEqual([d["name"] for d in after["declarations"]].count("actual_public_c_api"), 1)
            self.assertEqual(header.read_bytes(), alias.read_bytes())
            flags = shlex.split(WRAPPER.metadata_flags(root, root / "module.modulemap", root / "include", overlay))
            self.assertEqual(flags[flags.index("-ivfsoverlay") + 1], str(overlay))

    def test_differing_public_header_alias_cannot_be_overlaid(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            owner = self.framework(root / "products", "lower")
            (owner / "Modules/module.modulemap").write_text(
                'framework module lower {\n header "Exported.h"\n export *\n}\n')
            alias = root / "products/Carrier.framework/Headers/lower/Exported.h"
            alias.parent.mkdir(parents=True)
            alias.write_text("int independent_candidate_c_api(void);\n")
            records = HEADERS.write_public_umbrella(root, root / "input.h", [], [owner.parent])
            overlay = root / "aliases.json"
            before = (header := owner / "Headers/Exported.h").read_bytes(), alias.read_bytes()
            evidence = HEADERS.write_verified_header_alias_overlay(records, overlay)
            self.assertEqual(json.loads(overlay.read_text())["roots"], [])
            self.assertEqual(evidence[0]["disposition"], "NOT_ALIASED")
            self.assertEqual(evidence[0]["reason"], "different-header-bytes")
            self.assertEqual(evidence[0]["candidateSHA256"], hashlib.sha256(before[1]).hexdigest())
            self.assertEqual(evidence[0]["ownerSHA256"], hashlib.sha256(before[0]).hexdigest())
            self.assertEqual((header.read_bytes(), alias.read_bytes()), before)
            parsed = HEADERS.inspect_header_declarations([header, alias], ["-ivfsoverlay", str(overlay)], self.compiler_library(), "objective-c")
            self.assertEqual(parsed["errors"], [])
            self.assertIn("independent_candidate_c_api", [d["name"] for d in parsed["declarations"]])

    def test_identical_entry_with_changed_alias_dependency_is_rejected(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            owner = self.framework(root / "products", "lower")
            alias_root = root / "products/Carrier.framework/Headers/lower"
            shutil.copytree(owner / "Headers", alias_root)
            (alias_root / "Exported.h").write_text("// changed relative dependency of identical Entry.h")
            records = HEADERS.write_public_umbrella(root, root / "input.h", [], [owner.parent])
            evidence = HEADERS.write_verified_header_alias_overlay(records, root / "aliases.json")
            self.assertEqual(json.loads((root / "aliases.json").read_text())["roots"], [])
            self.assertEqual(evidence[0]["disposition"], "NOT_ALIASED")
            self.assertEqual(evidence[0]["reason"], "different-or-missing-dependency-tree")
            parsed = HEADERS.inspect_header_declarations([owner / "Headers/Entry.h", alias_root / "Entry.h"],
                ["-ivfsoverlay", str(root / "aliases.json")], self.compiler_library(), "objective-c")
            self.assertEqual(parsed["errors"], [])
            for actual in [owner / "Headers/Exported.h", alias_root / "Exported.h"]:
                self.assertEqual(parsed["dependencies"][str(actual.resolve())], hashlib.sha256(actual.read_bytes()).hexdigest())

    def test_unaliased_candidates_do_not_hide_actual_native_declaration_conflict(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            owner = self.framework(root / "products", "lower")
            header = owner / "Headers/Entry.h"
            header.write_text("enum Collision { FirstValue };\n")
            candidate = root / "products/Carrier.framework/Headers/lower/Entry.h"
            candidate.parent.mkdir(parents=True)
            candidate.write_text("enum Collision { SecondValue };\n")
            inventory = HEADERS.write_public_umbrella(root, root / "input.h", [], [owner.parent])
            overlay = root / "aliases.json"
            evidence = HEADERS.write_verified_header_alias_overlay(inventory, overlay)
            self.assertEqual(evidence[0]["disposition"], "NOT_ALIASED")
            self.assertEqual(json.loads(overlay.read_text())["roots"], [])
            parsed = HEADERS.inspect_header_declarations([header, candidate], ["-ivfsoverlay", str(overlay)], self.compiler_library(), "objective-c")
            self.assertTrue(parsed["errors"])
            self.assertIn("redefinition", "\n".join(parsed["errors"]))

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
                'def generate_metadata():\n    generator_call = ["./objc-metadata-generator", "-verbose",]\n    # clang arguments\n'
                '    # llvm_target_triple_os_version, llvm_target_triple_suffix)\n'
                '    child_process = subprocess.Popen(generator_call, stderr=subprocess.PIPE, universal_newlines=True)\n')
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
                   "PLATFORM_NAME": "iphonesimulator", "CONFIGURATION_BUILD_DIR": str(products), "SDKROOT": str(sdk),
                   "IPHONEOS_DEPLOYMENT_TARGET": "27.0", "ARCHS": "arm64"}
            with patch.dict(os.environ, env), patch.object(WRAPPER, "__file__", str(generator / "wrapper.py")), \
                 patch.object(WRAPPER.sys, "argv", ["wrapper", "arm64"]), \
                 patch.dict(sys.modules, {"metadata_public_headers": HEADERS}), \
                 patch.object(WRAPPER.subprocess, "run") as run, contextlib.redirect_stdout(io.StringIO()):
                def capture(arguments, **kwargs):
                    destination = kwargs.get("env", {}).get("HANLIN_METADATA_CAPTURE_ARGUMENTS")
                    if destination:
                        flags = ["-isysroot", str(sdk), "-target", "arm64-apple-ios27.0-simulator"]
                        Path(destination).write_text(json.dumps({"workingDirectory": str(Path(kwargs["cwd"]).resolve()), "arguments": flags,
                            "generatorCall": [str(tool / "bin/objc-metadata-generator"), "Xclang", *flags]}))
                    elif "-hanlin-dump-clang-context" in arguments:
                        destination = Path(arguments[arguments.index("-hanlin-dump-clang-context") + 1])
                        flags = arguments[arguments.index("Xclang") + 1:]
                        destination.write_bytes(b"Unit fixture compiler\0" + b"\0".join(value.encode() for value in flags) + b"\0")
                    return type("Completed", (), {"returncode": 0})()
                run.side_effect = capture
                self.assertEqual(WRAPPER.main(), 1)
            retained = root / "build/acceptance/nativescript-metadata/iphonesimulator-arm64"
            self.assertEqual((retained / diagnostic.name).read_bytes(), diagnostic.read_bytes())
            self.assertEqual((retained / "metadata-arm64.bin").read_bytes(), b"NSObject\0UIView\0")
            self.assertIn('"HanlinNativeServicesBridge": false', (retained / "visibility.json").read_text())
            # Capture-only discovery retains context before a genuine alias
            # owner conflict; it must never reach final emission on that error.
            carrier = self.framework(sdk / "System/Library/Frameworks", "Carrier")
            alias = carrier / "Headers/UIKit/UIKit.h"
            alias.parent.mkdir()
            alias.write_text("// differing alias, never safe to map by name")
            with patch.dict(os.environ, env), patch.object(WRAPPER, "__file__", str(generator / "wrapper.py")), \
                 patch.object(WRAPPER.sys, "argv", ["wrapper", "arm64"]), \
                 patch.dict(sys.modules, {"metadata_public_headers": HEADERS}), \
                 patch.object(HEADERS, "write_verified_header_alias_overlay", side_effect=RuntimeError("Conflicting public header alias owners")), \
                 patch.object(WRAPPER.subprocess, "run") as run:
                run.side_effect = capture
                with self.assertRaisesRegex(RuntimeError, "Conflicting public header alias owners"):
                    WRAPPER.main()
                self.assertEqual(run.call_count, 2)  # launcher capture, native read-only dump; no final invocation.
                self.assertIn("-hanlin-dump-clang-context", run.call_args_list[1].args[0])
            self.assertEqual(json.loads((retained / "effective-compiler-context.json").read_text())["compiler"], "Unit fixture compiler")
            self.assertEqual(json.loads((retained / "header-alias-validation.json").read_text())["status"], "FAILED")
            self.assertEqual(json.loads((retained / "HanlinHeaderAliases.json").read_text())["roots"], [])
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


class ModernMetadataProvenanceControls(unittest.TestCase):
    def test_candidate_rejects_source_binary_library_and_frontend_identity_drift(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            scripts = root / "Scripts/NativeScript"
            scripts.mkdir(parents=True)
            frontend = root / "frontend"
            support = scripts / "metadata-dual-grammar/Proof.h"
            support.parent.mkdir()
            support.write_bytes(b"candidate support source")
            (frontend / "lib").mkdir(parents=True)
            for name in ["libclang.dylib", "libclang-cpp.dylib", "libLLVM.dylib"]:
                (frontend / "lib" / name).write_bytes(name.encode())
            (frontend / "header.h").write_bytes(b"actual header")
            sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
            lock = {"installedPrefix": str(frontend.resolve()), "version": "20.1.8",
                    "files": {"header.h": sha(frontend / "header.h")}}
            (scripts / "metadata-frontend-lock.json").write_text(json.dumps(lock))
            for name in ["build-metadata-tool.py", "build-modern-metadata-tool.py"]:
                (scripts / name).write_bytes(name.encode())
            tool_root = root / "build/nativescript-modern-metadata-tool"
            (tool_root / "bin").mkdir(parents=True)
            binary = tool_root / "bin/objc-metadata-generator"
            binary.write_bytes(b"compiled binary")
            receipt = {"schemaVersion": 2, "status": "BUILT_NOT_ACCEPTED", "generatorSHA256": sha(binary),
                       "supportSources": {support.relative_to(root).as_posix(): sha(support)},
                       "frontendRoot": str(frontend.resolve()), "classifierLibrary": str(frontend.resolve() / "lib/libclang.dylib"),
                       "frontendVersion": "20.1.8", "frontendInputs": {"header.h": sha(frontend / "header.h")},
                       "libraries": {p.name: sha(p) for p in (frontend / "lib").iterdir()}}
            for key, name in [("basePatchSourceSHA256", "build-metadata-tool.py"),
                              ("modernPatchSourceSHA256", "build-modern-metadata-tool.py"),
                              ("frontendLockSHA256", "metadata-frontend-lock.json")]:
                receipt[key] = sha(scripts / name)
            path = tool_root / "provenance.json"
            path.write_text(json.dumps(receipt))
            self.assertEqual(WRAPPER.validate_modern_tool(root), (tool_root, frontend.resolve() / "lib/libclang.dylib"))
            for target in [binary, support, scripts / "build-metadata-tool.py", scripts / "build-modern-metadata-tool.py",
                           scripts / "metadata-frontend-lock.json", frontend / "header.h", frontend / "lib/libclang.dylib"]:
                original = target.read_bytes()
                target.write_bytes(original + b" drift")
                with self.subTest(target=target.name), self.assertRaises(RuntimeError):
                    WRAPPER.validate_modern_tool(root)
                target.write_bytes(original)
            for key in ["classifierLibrary", "frontendRoot", "frontendVersion", "status"]:
                changed = {**receipt, key: "unproven"}
                path.write_text(json.dumps(changed))
                with self.subTest(field=key), self.assertRaises(RuntimeError):
                    WRAPPER.validate_modern_tool(root)


class PreprocessingReceiptControls(unittest.TestCase):
    """Pure receipt rejection controls. Authored source; execution is separate."""

    def packet(self):
        root = {"ordinal": 0, "line": 1, "path": "/fixture/a.h", "owner": "fixture", "sha256": "a" * 64}
        request = {"bindings": {"contextSHA256": "b" * 64}, "roots": [root]}
        receipt = {"schemaVersion": 1, "mode": "preprocessing-provenance", "status": "COMPLETE",
            "bindings": copy.deepcopy(request["bindings"]), "sawEOF": True, "endOfMainFile": True,
            "actionEnded": True, "hadASTContext": False, "hadSema": False, "hadErrors": False,
            "serializedContext": False, "truncated": False, "diagnosticErrors": 0,
            "lookupMisses": 0, "unknownOwners": 0, "uncorrelated": 0, "unprovenPragmas": 0,
            "consumerEntries": 0, "writerEntries": 0, "expectedRootOccurrences": 1,
            "resolvedRootOccurrences": 1, "inactiveRootOccurrences": 0, "reasons": [],
            "observedInputs": [{"path": root["path"], "sha256": root["sha256"]}], "events": [],
            "roots": [{**root, "state": "resolved", "resolvedPath": root["path"], "observedOwner": root["owner"]}]}
        return request, receipt

    def test_partial_cancelled_truncated_or_parser_receipt_cannot_be_complete(self):
        request, receipt = self.packet()
        self.assertEqual(WRAPPER.validate_preprocessing_receipt(receipt, request), [])
        changes = {"sawEOF": False, "endOfMainFile": False, "actionEnded": False,
            "hadASTContext": True, "hadSema": True, "hadErrors": True, "serializedContext": True,
            "truncated": True, "diagnosticErrors": 1, "lookupMisses": 1, "unknownOwners": 1,
            "uncorrelated": 1, "unprovenPragmas": 1, "consumerEntries": 1, "writerEntries": 1,
            "expectedRootOccurrences": True, "resolvedRootOccurrences": True, "roots": [],
            "status": "CANCELLED", "bindings": {}, "reasons": ["partial"]}
        for key, value in changes.items():
            with self.subTest(key=key):
                self.assertTrue(WRAPPER.validate_preprocessing_receipt({**receipt, key: value}, request))
        for malformed in [None, [], "COMPLETE"]:
            self.assertTrue(WRAPPER.validate_preprocessing_receipt(malformed, request))

    def test_inactive_occurrence_has_no_observed_resolution_or_owner(self):
        request, receipt = self.packet()
        receipt.update(resolvedRootOccurrences=0, inactiveRootOccurrences=1)
        receipt["roots"] = [{**request["roots"][0], "state": "inactive"}]
        self.assertEqual(WRAPPER.validate_preprocessing_receipt(receipt, request), [])
        receipt["roots"][0]["observedOwner"] = "fixture"
        self.assertIn("inactive-is-not-resolved", WRAPPER.validate_preprocessing_receipt(receipt, request))


class DiagnosticMemoryPath(PurePosixPath):
    """RAM-only control filesystem; never touches a real path or executable."""
    files = {}
    operations = []
    failures = {}

    def read_bytes(self):
        self.operations.append(("read", str(self)))
        if str(self) in self.failures:
            raise self.failures[str(self)]
        return self.files[str(self)]

    def read_text(self, **kwargs):
        return self.read_bytes().decode("utf-8")

    def write_bytes(self, body):
        self.operations.append(("write", str(self)))
        if str(self) in self.failures:
            raise self.failures[str(self)]
        self.files[str(self)] = body
        return len(body)

    def write_text(self, text, **kwargs):
        return self.write_bytes(text.encode("utf-8"))

    def open(self, mode):
        assert mode == "rb"
        return io.BytesIO(self.read_bytes())

    def mkdir(self, **kwargs):
        self.operations.append(("mkdir", str(self)))

    def is_file(self):
        self.operations.append(("is_file", str(self)))
        return str(self) in self.files

    def glob(self, pattern):
        return []

    def resolve(self):
        return self


@contextlib.contextmanager
def diagnostic_memory_generation(mode, *, alias_error=None, source_error=None, evidence_failure=None,
                                 selected_source_error=None, helper_error=None, generator_exit=0):
    """Execute real wrapper control flow with RAM paths and mocked transports.

    This proves control flow only; no actual generation/native/real-filesystem
    success is established. The authored unittest methods remain separately run.
    """
    memory = DiagnosticMemoryPath
    memory.files, memory.operations, memory.failures = {}, [], {}
    root, module = memory("/repo"), memory("/module")
    evidence = root / "build/acceptance/nativescript-metadata/iphonesimulator-arm64"
    tool = root / "build/nativescript-metadata-tool"
    patch_source = root / "Scripts/NativeScript/build-metadata-tool.py"
    memory.files[str(tool / "bin/objc-metadata-generator")] = b"not-executable-memory-tool"
    memory.files[str(patch_source)] = b"memory-source"
    memory.files[str(tool / "provenance.json")] = json.dumps({
        "generatorSHA256": hashlib.sha256(b"not-executable-memory-tool").hexdigest(),
        "patchSourceSHA256": hashlib.sha256(b"memory-source").hexdigest()}).encode()
    upstream = memory("/generator/upstream.py")
    memory.files[str(upstream)] = b"memory-launcher"
    stale = memory("/products/metadata-arm64.bin")
    memory.files[str(stale)] = b"OLD-METADATA-MUST-NOT-BE-ACCEPTED"
    selected = memory("/selected/ExpoModulesCore_umbrella.h")
    memory.files[str(selected)] = b"// selected body\n"
    inventory = [{"framework": "ExpoModulesCore.framework", "status": "SELECTED",
        "publicUmbrellaHeaders": [{"path": str(selected), "sha256": hashlib.sha256(memory.files[str(selected)]).hexdigest()}]}]
    if selected_source_error:
        memory.failures[str(selected)] = selected_source_error
    if evidence_failure:
        memory.failures[str(evidence / evidence_failure)] = OSError("injected diagnostic evidence write failure")
    # A stale COMPLETE receipt must not overcome an evidence-failure exit.
    memory.files[str(evidence / "preprocessing-provenance.json")] = json.dumps({
        "status": "COMPLETE", "metadataExecution": "NOT_GENERATED"}).encode()
    headers = types.ModuleType("metadata_public_headers")
    headers.ROLE_MANIFEST = "roles.json"
    headers.produce_role_inventory = Mock()
    headers.verify_role_context = Mock()
    headers.write_public_umbrella = Mock(return_value=inventory, side_effect=source_error)
    headers.write_verified_header_alias_overlay = Mock(return_value=[], side_effect=alias_error)
    def capture(*args):
        (module / "actual-compiler-arguments.json").write_text("{}")
        return []
    with contextlib.ExitStack() as stack:
        stack.enter_context(patch.dict(os.environ, {"SDKROOT": "/sdk", "CONFIGURATION_BUILD_DIR": "/products",
            "HANLIN_METADATA_PREPROCESS_PROVENANCE": mode}, clear=True))
        stack.enter_context(patch.dict(sys.modules, {"metadata_public_headers": headers}))
        stack.enter_context(patch.object(WRAPPER, "Path", memory))
        for name, value in [("write_swift_module_map", []), ("explicit_input_adapter", "adapter"),
                            ("metadata_flags", "-fno-modules"), ("capture_native_compiler_context", {"arguments": []})]:
            stack.enter_context(patch.object(WRAPPER, name, return_value=value))
        stack.enter_context(patch.object(WRAPPER, "capture_compiler_arguments", side_effect=capture))
        trace = stack.enter_context(patch.object(WRAPPER, "capture_preprocessing_provenance", return_value={
            "schemaVersion": 1, "status": "COMPLETE", "metadataExecution": "NOT_RUN_DIAGNOSTIC_ONLY"}))
        copied = stack.enter_context(patch.object(WRAPPER.shutil, "copy2"))
        generated = stack.enter_context(patch.object(WRAPPER.subprocess, "run", return_value=types.SimpleNamespace(returncode=generator_exit)))
        checked = stack.enter_context(patch.object(WRAPPER, "retain_and_check_metadata", return_value=True))
        helper = stack.enter_context(patch.object(WRAPPER, "retain_diagnostic_evidence", wraps=WRAPPER.retain_diagnostic_evidence,
                                                  side_effect=helper_error))
        stderr = stack.enter_context(contextlib.redirect_stderr(io.StringIO()))
        invoke = lambda: WRAPPER.generate_final_metadata(root, "arm64", "iphonesimulator", module,
            module / "module.modulemap", memory("/runtime.h"), memory("/generator"), upstream)
        yield types.SimpleNamespace(invoke=invoke, memory=memory, evidence=evidence, stale=stale,
            trace=trace, helper=helper, generated=generated, checked=checked, copied=copied,
            headers=headers, stderr=stderr)


class DiagnosticProductionBoundaryControls(unittest.TestCase):
    """Authored RAM control-flow tests, NOT_RUN in the frozen source packet."""

    def test_complete_diagnostic_never_succeeds_production_or_consumes_stale_binary(self):
        with diagnostic_memory_generation("1") as control:
            self.assertEqual(control.invoke(), WRAPPER.DIAGNOSTIC_ONLY_EXIT)
            self.assertNotEqual(WRAPPER.DIAGNOSTIC_ONLY_EXIT, 0)
            control.generated.assert_not_called()
            control.checked.assert_not_called()
            self.assertNotIn(("read", str(control.stale)), control.memory.operations)
            self.assertEqual(control.memory.files[str(control.stale)], b"OLD-METADATA-MUST-NOT-BE-ACCEPTED")
            receipt = json.loads(control.memory.files[str(control.evidence / "preprocessing-provenance.json")])
            self.assertEqual(receipt["status"], "COMPLETE")
            self.assertEqual(receipt["metadataExecution"], "NOT_GENERATED")

    def test_disabled_mode_never_calls_diagnostic_helper_or_new_evidence_io(self):
        with diagnostic_memory_generation("0") as control:
            self.assertEqual(control.invoke(), 0)  # RAM transport success only.
            control.trace.assert_not_called()
            control.helper.assert_not_called()
            control.generated.assert_called_once()
            control.checked.assert_called_once_with("arm64", "iphonesimulator")
            self.assertEqual(control.headers.write_public_umbrella.call_count, 2)
            self.assertFalse(any("preprocessing-provenance" in path or "selected-public-header" in path
                or "ExpoModulesCore_umbrella.h" in path for _, path in control.memory.operations))

    def test_normal_generator_failure_keeps_original_exit_contract(self):
        with diagnostic_memory_generation("0", generator_exit=7) as control:
            self.assertEqual(control.invoke(), 7)
            control.checked.assert_called_once()
            control.helper.assert_not_called()

    def test_diagnostic_write_failure_has_distinct_non_success_even_with_stale_complete(self):
        for filename in ["selected-public-header.json", "preprocessing-provenance.json"]:
            with self.subTest(filename=filename), diagnostic_memory_generation("1", evidence_failure=filename) as control:
                self.assertEqual(control.invoke(), WRAPPER.DIAGNOSTIC_EVIDENCE_FAILURE_EXIT)
                control.generated.assert_not_called()
                control.checked.assert_not_called()
                self.assertIn("diagnostic evidence INCOMPLETE", control.stderr.getvalue())

    def test_selected_read_failure_never_masks_original_alias_exception(self):
        primary = RuntimeError("original unequal alias")
        with diagnostic_memory_generation("1", alias_error=primary, selected_source_error=OSError("source read failed")) as control:
            with self.assertRaises(RuntimeError) as caught:
                control.invoke()
            self.assertIs(caught.exception, primary)
            self.assertIn("source read failed", control.stderr.getvalue())
            control.generated.assert_not_called()

    def test_unexpected_helper_failure_never_masks_original_source_exception(self):
        primary = RuntimeError("original source inventory failure")
        with diagnostic_memory_generation("1", source_error=primary, helper_error=RuntimeError("diagnostic helper failed")) as control:
            with self.assertRaises(RuntimeError) as caught:
                control.invoke()
            self.assertIs(caught.exception, primary)
            self.assertIn("diagnostic helper failed", control.stderr.getvalue())
            control.headers.write_verified_header_alias_overlay.assert_not_called()

    def test_probe_accepts_sentinel_only_in_explicit_diagnostic_outcome(self):
        spec = importlib.util.spec_from_file_location("diagnostic_probe", ROOT / "Scripts/NativeScript/probe-sdk-metadata.py")
        probe = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(probe)
        receipt = {"status": "COMPLETE", "metadataExecution": "NOT_GENERATED"}
        aliases = {"status": "VERIFIED"}
        self.assertEqual(probe.diagnostic_probe_outcome(3, receipt, aliases), {
            "diagnosticStatus": "COMPLETE", "metadataExecution": "NOT_GENERATED"})
        for code in [0, 1, 2, 4, -9]:
            self.assertEqual(probe.diagnostic_probe_outcome(code, receipt, aliases)["diagnosticStatus"], "INCOMPLETE")
        self.assertEqual(probe.diagnostic_probe_outcome(3, receipt, {"status": "FAILED"})["diagnosticStatus"], "INCOMPLETE")
        self.assertEqual(probe.diagnostic_probe_outcome(3, {"status": "INCOMPLETE"}, aliases)["diagnosticStatus"], "INCOMPLETE")


class NativePreprocessingProvenanceControls(unittest.TestCase):
    """FUTURE BLACK-BOX CONTROLS: NOT_RUN in the source-only packet.

    Requires explicit HANLIN_RUN_PROVENANCE_NATIVE_CONTROLS=1 on macOS and an
    already built, source-hash-matched tool/provenance. This suite never builds
    or downloads a tool. Context capture is a separate normal discovery process
    which can build an AST; the subsequent diagnostic process must not do so.
    """

    def setUp(self):
        if os.environ.get("HANLIN_RUN_PROVENANCE_NATIVE_CONTROLS") != "1" or sys.platform != "darwin":
            self.skipTest("NOT_RUN: separately authorized native provenance controls required")
        evidence = os.environ.get("HANLIN_PROVENANCE_CONTROL_EVIDENCE_DIR")
        if not evidence:
            self.skipTest("NOT_RUN: explicit runner-owned evidence directory required")
        evidence_root = Path(evidence)
        self.assertTrue(evidence_root.is_absolute())
        self.assertFalse(evidence_root.is_symlink())
        self.assertEqual(evidence_root.resolve(strict=True), evidence_root)
        self.assertTrue(evidence_root.is_dir())
        self.assertEqual(evidence_root.stat().st_uid, os.getuid())
        self.variant = "default"
        if self._testMethodName == "test_serialized_context_rejected_without_cache_or_emitter_work":
            self.variant = os.environ.get("HANLIN_PROVENANCE_SERIALIZED_VARIANT", "modules")
            self.assertIn(self.variant, {"modules", "pch", "module-file", "preamble"})
        if self._testMethodName == "test_hash_drift_or_output_collision_cannot_write_a_complete_receipt":
            self.variant = os.environ.get("HANLIN_PROVENANCE_NEGATIVE_VARIANT", "overlay")
            self.assertIn(self.variant, {"overlay", "umbrella", "header", "context", "request", "collision"})
        self.selector_name = type(self).__name__ + "." + self._testMethodName
        self.evidence = evidence_root / (self.selector_name + "--" + self.variant)
        self.evidence.mkdir(mode=0o700)  # Exclusive: no stale case or owner output replacement.
        self.control_status, self.control_reason = "RUNNING", None
        self.commands = []
        self.cache_before = None
        # Explicit retention opt-in replaces this native suite's temporary
        # auto-cleanup. Keep the ORIGINAL fixture paths valid even if retention
        # fails or the runner hits its cap; never delete the last raw evidence.
        self.folder = self.evidence / "fixture"
        self.folder.mkdir(mode=0o700)
        self.addCleanup(self.retain_evidence)
        self.tool = Path(os.environ["HANLIN_PREPROCESS_PROVENANCE_NATIVE_TOOL"]).resolve(strict=True)
        self.provenance_path = Path(os.environ["HANLIN_PREPROCESS_PROVENANCE_TOOL_RECEIPT"]).resolve(strict=True)
        self.patch_source = ROOT / "Scripts/NativeScript/build-metadata-tool.py"
        provenance = json.loads(self.provenance_path.read_text(encoding="utf-8"))
        self.modern = os.environ.get("HANLIN_METADATA_PROOF_FRONTEND") == "modern"
        self.assertEqual(provenance["basePatchSourceSHA256" if self.modern else "patchSourceSHA256"], self.sha(self.patch_source))
        self.assertEqual(provenance["generatorSHA256"], self.sha(self.tool))
        frozen = {filename: self.sha(ROOT / "Scripts/NativeScript" / filename) for filename in [
            "build-metadata-tool.py", "build-step-metadata-generator-wrapper.py", "probe-sdk-metadata.py"]}
        if self.modern:
            self.assertEqual(provenance["schemaVersion"], 2)
            for key, filename in [("modernPatchSourceSHA256", "build-modern-metadata-tool.py"),
                                  ("frontendLockSHA256", "metadata-frontend-lock.json")]:
                self.assertEqual(provenance[key], self.sha(ROOT / "Scripts/NativeScript" / filename))
                frozen[filename] = provenance[key]
            frontend = Path(provenance["frontendRoot"])
            support_sources = {p.relative_to(ROOT).as_posix(): self.sha(p)
                               for p in sorted((ROOT / "Scripts/NativeScript/metadata-dual-grammar").glob("*")) if p.suffix in {".h", ".cpp", ".py"}}
            self.assertTrue(support_sources)
            self.assertEqual(provenance["supportSources"], support_sources)
            frozen.update(support_sources)
            for name, digest in provenance["libraries"].items():
                self.assertEqual(self.sha(frontend / "lib" / name), digest)
        self.flags = json.loads(os.environ["HANLIN_PREPROCESS_PROVENANCE_CLANG_ARGS_JSON"])
        self.assertIsInstance(self.flags, list)
        self.record("control-meta.json", {"schemaVersion": 1, "selector": self.selector_name, "variant": self.variant,
            "category": "NATIVE", "fixture": str(self.folder), "tool": str(self.tool),
            "toolSHA256": self.sha(self.tool), "testSourceSHA256": self.sha(Path(__file__)), "productionSources": frozen,
            "provenanceSHA256": self.sha(self.provenance_path), "flags": self.flags})
        (self.evidence / "tool-provenance.json").write_bytes(self.provenance_path.read_bytes())

    @staticmethod
    def sha(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def record(self, name, value):
        (self.evidence / name).write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")

    @staticmethod
    def tree_snapshot(root):
        """lstat-based tree identity, including absent roots/directories/symlinks."""
        entries = []
        def visit(path):
            relative = "." if path == root else path.relative_to(root).as_posix()
            if not path.exists() and not path.is_symlink():
                entries.append({"path": relative, "kind": "absent"})
                return
            info = path.lstat()
            row = {"path": relative, "mode": info.st_mode, "mtimeNS": info.st_mtime_ns}
            if path.is_symlink():
                row.update(kind="symlink", target=os.readlink(path))
            elif path.is_dir():
                row["kind"] = "directory"
            elif path.is_file():
                row.update(kind="file", bytes=info.st_size, sha256=NativePreprocessingProvenanceControls.sha(path))
            else:
                row["kind"] = "other"
            entries.append(row)
            if row["kind"] == "directory":
                for child in sorted(path.iterdir()):
                    visit(child)
        visit(root)
        return entries

    def retain_evidence(self):
        # Failure to retain is an actual harness error; it cannot publish PASS.
        self.record("fixture.final-tree.json", self.tree_snapshot(self.folder))
        if self.cache_before is not None:
            self.record("cache.after.json", self.tree_snapshot(self.folder / "module-cache"))
        outcome = self._outcome.result
        failed = any(test is self or getattr(test, "test_case", None) is self
                     for test, _ in [*outcome.failures, *outcome.errors])
        skipped = any(test is self for test, _ in outcome.skipped)
        status = self.control_status
        if status == "RUNNING":
            status = "FAIL" if failed else "NOT_RUN" if skipped else "PASS"
        manifest = []
        for path in sorted(self.evidence.rglob("*")):
            if path.is_file() and not path.is_symlink():
                manifest.append({"path": path.relative_to(self.evidence).as_posix(), "sha256": self.sha(path), "bytes": path.stat().st_size})
        self.record("evidence-manifest.json", manifest)
        self.record("control-result.json", {"schemaVersion": 1, "selector": self.selector_name, "variant": self.variant,
            "status": status, "readiness": "RECORDED" if status == "PASS" else "BLOCKED",
            "reason": self.control_reason, "metadataAcceptance": "NOT_ESTABLISHED", "commands": self.commands,
            "manifestSHA256": self.sha(self.evidence / "evidence-manifest.json")})

    def not_observed(self, reason):
        self.control_status, self.control_reason = "NOT_OBSERVED", reason
        self.skipTest("BLOCKED / NOT_OBSERVED: " + reason)

    def run_recorded(self, label, command, *, cwd=None, timeout=60):
        self.assertNotIn(label, self.commands)
        self.commands.append(label)
        directory = cwd or self.tool.parent
        call = {"argv": [str(value) for value in command], "cwd": str(directory), "timeoutSeconds": timeout,
            "environmentSHA256": hashlib.sha256(json.dumps(dict(os.environ), sort_keys=True).encode()).hexdigest()}
        self.record(label + ".command.json", call)
        try:
            result = subprocess.run(command, cwd=directory, capture_output=True, timeout=timeout)
        except (OSError, subprocess.SubprocessError) as error:
            for suffix, body in [("stdout", getattr(error, "stdout", b"")), ("stderr", getattr(error, "stderr", b""))]:
                (self.evidence / (label + "." + suffix)).write_bytes(body or b"")
            self.record(label + ".exit.json", {"returncode": None, "error": type(error).__name__, "detail": str(error)})
            raise
        (self.evidence / (label + ".stdout")).write_bytes(result.stdout)
        (self.evidence / (label + ".stderr")).write_bytes(result.stderr)
        self.record(label + ".exit.json", {"returncode": result.returncode})
        return result

    def prepare(self, text, occurrences, extra_flags=()):
        umbrella = self.folder / "input.h"
        umbrella.write_text(text)
        overlay = self.folder / "overlay.json"
        overlay.write_text(json.dumps({"version": 0, "use-external-names": True, "roots": []}))
        # Each normal output category has an existing byte canary. A missing
        # blacklist is another canary: diagnostic mode must never open it.
        normal = []
        self.canaries = {}
        self.normal_paths = []
        for option, name, directory in [("-output-bin", "metadata.bin", False),
                ("-output-umbrella", "normal-umbrella.h", False), ("-output-yaml", "yaml", True),
                ("-output-typescript", "types", True), ("-output-modulemaps", "maps", True)]:
            path = self.folder / name
            if directory:
                path.mkdir()
            canary = path / "canary" if directory else path
            canary.write_bytes(b"UNCHANGED-NORMAL-OUTPUT\0")
            self.canaries[canary] = canary.read_bytes()
            self.normal_paths.append(path)
            normal.extend([option, str(path)])
        self.canary_before = {path.name: self.tree_snapshot(path) for path in self.normal_paths}
        self.record("canaries.before.json", self.canary_before)
        self.call = [str(self.tool), "-input-umbrella", str(umbrella), *normal,
            "-blacklist-modules-file", str(self.folder / "must-never-open-blacklist"), "Xclang",
            *self.flags, "-I" + str(self.folder), "-ivfsoverlay", str(overlay), *extra_flags]
        self.context_path = self.folder / "context.bin"
        split = self.call.index("Xclang")
        captured = self.run_recorded("normal-context-capture", [*self.call[:split], "-hanlin-dump-clang-context", str(self.context_path),
            *self.call[split:]])
        self.assertEqual(captured.returncode, 0, captured.stderr.decode(errors="replace"))
        self.assertTrue(self.context_path.read_bytes().endswith(b"\0"))
        context_fields = self.context_path.read_bytes()[:-1].decode("utf-8").split("\0")
        self.record("actual-context.json", {"compiler": context_fields[0], "arguments": context_fields[1:],
            "contextSHA256": self.sha(self.context_path), "preparationMayUseAST": True})
        roots = [{"ordinal": index, "line": line, "path": str((self.folder / name).resolve()),
                  "owner": "fixture", "sha256": self.sha(self.folder / name)}
                 for index, (line, name) in enumerate(occurrences)]
        files = [umbrella, overlay, self.context_path, self.tool, self.patch_source, self.provenance_path,
                 *[self.folder / name for _, name in occurrences]]
        if self.modern:
            files.extend(ROOT / "Scripts/NativeScript" / name for name in ["build-modern-metadata-tool.py", "metadata-frontend-lock.json"])
            files.extend(p for p in sorted((ROOT / "Scripts/NativeScript/metadata-dual-grammar").glob("*")) if p.suffix in {".h", ".cpp", ".py"})
        self.request = {"schemaVersion": 1,
            "bindings": {"contextSHA256": self.sha(self.context_path), "umbrellaSHA256": self.sha(umbrella),
                "overlaySHA256": self.sha(overlay), "patchSourceSHA256": self.sha(self.patch_source),
                "instrumentedBinarySHA256": self.sha(self.tool), "compiler": context_fields[0], "cwd": str(self.tool.parent),
                "environmentSHA256": hashlib.sha256(json.dumps(dict(os.environ), sort_keys=True).encode()).hexdigest(),
                "toolProvenanceSHA256": self.sha(self.provenance_path)}, "roots": roots,
            "owners": [{"root": str(self.folder), "id": "fixture"}], "filteredPrefixes": [str(self.folder)],
            "verifiedFiles": [{"path": str(path), "sha256": self.sha(path)} for path in dict.fromkeys(files)]}
        self.request_path = self.folder / "request.json"
        self.request_path.write_text(json.dumps(self.request))
        self.receipt_path = self.folder / "trace.json"
        self.trace_call = [*self.call[:split], "-hanlin-expected-clang-context", str(self.context_path),
            "-hanlin-preprocess-provenance", str(self.receipt_path), "-hanlin-provenance-inputs", str(self.request_path),
            *self.call[split:]]
        self.assert_canaries()
        self.cache_before = self.tree_snapshot(self.folder / "module-cache")
        self.record("cache.before.json", self.cache_before)
        self.record("fixture.before-tree.json", self.tree_snapshot(self.folder))
        shutil.copytree(self.folder, self.evidence / "fixture-before", symlinks=True)

    def assert_canaries(self):
        for path, body in self.canaries.items():
            self.assertEqual(path.read_bytes(), body, str(path))
        for directory in ["yaml", "types", "maps"]:
            self.assertEqual([path.name for path in (self.folder / directory).iterdir()], ["canary"])
        after = {path.name: self.tree_snapshot(path) for path in self.normal_paths}
        self.record("canaries.after.json", after)
        self.assertEqual(after, self.canary_before)

    def trace(self):
        self.record("fixture.pre-trace-tree.json", self.tree_snapshot(self.folder))
        run = self.run_recorded("diagnostic-trace", self.trace_call)
        self.assert_canaries()
        receipt = json.loads(self.receipt_path.read_text()) if self.receipt_path.is_file() else {}
        return run, receipt

    def test_338_occurrences_quote_angle_macro_import_guard_pragma_and_inactive(self):
        for name in ["quote.h", "angle.h", "macro.h", "inactive.h"]:
            (self.folder / name).write_text("int fixture_declaration;\n")
        (self.folder / "once.h").write_text("#pragma once\nint once_declaration;\n")
        (self.folder / "guard.h").write_text("#ifndef FIXTURE_GUARD\n#define FIXTURE_GUARD\nint guard_declaration;\n#endif\n")
        lines = ['#include "quote.h"', '#include <angle.h>', '#define HEADER_MACRO "macro.h"',
            '#include HEADER_MACRO', '#import "once.h"', '#import "once.h"',
            '#include "guard.h"', '#include "guard.h"', '#if 0', '#include "inactive.h"', '#endif']
        occurrences = [(1, "quote.h"), (2, "angle.h"), (4, "macro.h"), (5, "once.h"),
                       (6, "once.h"), (7, "guard.h"), (8, "guard.h"), (10, "inactive.h")]
        while len(occurrences) < 338:
            lines.append('#import "once.h"')
            occurrences.append((len(lines), "once.h"))
        self.prepare("\n".join(lines) + "\n", occurrences)
        run, receipt = self.trace()
        self.assertEqual(run.returncode, 0, run.stderr.decode(errors="replace"))
        self.assertEqual(WRAPPER.validate_preprocessing_receipt(receipt, self.request), [])
        self.assertEqual(receipt["expectedRootOccurrences"], 338)
        self.assertEqual(receipt["resolvedRootOccurrences"], 337)
        self.assertEqual(receipt["inactiveRootOccurrences"], 1)
        includes = {event["line"]: event for event in receipt["events"] if event["kind"] == "include"}
        self.assertEqual([includes[line]["form"] for line in [1, 2, 4]], ["quote", "angle", "macro"])
        self.assertEqual(includes[5]["directive"], "import")
        self.assertIn("skip", receipt["roots"][4])
        self.assertIn("skip", receipt["roots"][6])
        self.assertEqual(receipt["roots"][7]["state"], "inactive")
        if self.modern:
            builtin_pragmas = [event for event in receipt["events"] if event["kind"] == "compiler-predefine-pragma"]
            self.assertEqual({event["source"] for event in builtin_pragmas}, {
                '#pragma push_macro("__GCC_DESTRUCTIVE_SIZE")', '#pragma push_macro("__GCC_CONSTRUCTIVE_SIZE")'})
            self.assertEqual(len(builtin_pragmas), 2)
            self.assertTrue(all(re.fullmatch(r"[0-9a-f]{64}", event["predefinesSHA256"]) for event in builtin_pragmas))

    def test_semantically_invalid_cpp_tokens_are_not_an_ast_or_metadata_pass(self):
        header = self.folder / "cpp.h"
        header.write_text("struct Broken { HanlinMissingPublicType field; };\n" if self.modern else
                          "namespace cpp_only { template<class T> struct Type {}; }\n")
        self.prepare('#include "cpp.h"\n', [(1, "cpp.h")])
        run, receipt = self.trace()
        self.assertEqual(run.returncode, 0, run.stderr.decode(errors="replace"))
        self.assertEqual(WRAPPER.validate_preprocessing_receipt(receipt, self.request), [])
        # The SAME executable/context now takes its real normal AST/parser
        # path. No output options, missing blacklist or invalid CLI stand-in.
        split = self.call.index("Xclang")
        semantic = self.run_recorded("same-generator-semantic-rejection", [str(self.tool),
            "-input-umbrella", str(self.folder / "input.h"), "-hanlin-expected-clang-context", str(self.context_path),
            "Xclang", *self.call[split + 1:]])
        self.assertEqual(semantic.returncode, 1)
        self.assertIn(b"unknown type name 'HanlinMissingPublicType'" if self.modern else b"unknown type name 'namespace'", semantic.stderr)
        self.assert_canaries()

    def test_suppressed_missing_header_still_makes_trace_incomplete(self):
        (self.folder / "root.h").write_text('#include "does-not-exist.h"\n')
        self.prepare('#include "root.h"\n', [(1, "root.h")])
        run, receipt = self.trace()  # default strict-includes=false, as production
        self.assertNotEqual(run.returncode, 0)
        self.assertEqual(receipt["status"], "INCOMPLETE")
        self.assertGreater(receipt["lookupMisses"], 0)
        self.assertTrue(WRAPPER.validate_preprocessing_receipt(receipt, self.request))

    def test_unknown_owner_and_semantic_pragma_cannot_be_complete(self):
        (self.folder / "root.h").write_text('#pragma clang diagnostic push\n' +
            ('#line 1 "<built-in>"\n#pragma push_macro("__GCC_DESTRUCTIVE_SIZE")\n' if self.modern else '') +
            'int declaration;\n')
        self.prepare('#include "root.h"\n', [(1, "root.h")])
        self.request["owners"] = []
        self.request_path.write_text(json.dumps(self.request))
        run, receipt = self.trace()
        self.assertNotEqual(run.returncode, 0)
        self.assertGreater(receipt["unknownOwners"], 0)
        self.assertGreater(receipt["unprovenPragmas"], 0)
        if self.modern:
            self.assertGreaterEqual(receipt["unprovenPragmas"], 2)  # User source cannot impersonate compiler predefines.

    def test_source_import_cannot_claim_serialization_absence_without_parser(self):
        (self.folder / "root.h").write_text("@import UnknownModule;\n")
        self.prepare('#include "root.h"\n', [(1, "root.h")])
        run, receipt = self.trace()
        self.assertNotEqual(run.returncode, 0)
        self.assertTrue(receipt["serializedContext"])
        self.assertTrue(WRAPPER.validate_preprocessing_receipt(receipt, self.request))

    def test_serialized_context_rejected_without_cache_or_emitter_work(self):
        # Separate test instances isolate all filesystem/cache state.
        variant = os.environ.get("HANLIN_PROVENANCE_SERIALIZED_VARIANT", "modules")
        cache = self.folder / "module-cache"
        choices = {"modules": ["-fmodules", "-fmodules-cache-path=" + str(cache)],
            "pch": ["-include-pch", str(self.folder / "absent.pch")],
            "module-file": ["-fmodule-file=" + str(self.folder / "absent.pcm")],
            "preamble": ["-Xclang", "-preamble-bytes=1,0"]}
        self.assertIn(variant, choices)
        (self.folder / "root.h").write_text("int declaration;\n")
        self.prepare('#include "root.h"\n', [(1, "root.h")], choices[variant])
        self.cache_before = self.tree_snapshot(cache)
        self.record("cache.before.json", self.cache_before)
        run, receipt = self.trace()
        self.assertNotEqual(run.returncode, 0)
        self.assertTrue(WRAPPER.validate_preprocessing_receipt(receipt, self.request))
        after = self.tree_snapshot(cache)
        self.record("cache.after.json", after)
        self.assertEqual(after, self.cache_before)
        if not receipt:
            self.not_observed("No genuine serialized-context receipt; driver-only rejection is insufficient")
        self.assertEqual(receipt["mode"], "preprocessing-provenance")
        self.assertEqual(receipt["status"], "INCOMPLETE")
        self.assertIn("unsupported-serialized-context", receipt["reasons"])
        self.assertTrue(receipt["serializedContext"])
        for field in ["sawEOF", "endOfMainFile", "hadASTContext", "hadSema"]:
            self.assertIs(receipt[field], False)
        self.assertEqual(receipt["consumerEntries"], 0)
        self.assertEqual(receipt["writerEntries"], 0)

    def test_hash_drift_or_output_collision_cannot_write_a_complete_receipt(self):
        variant = os.environ.get("HANLIN_PROVENANCE_NEGATIVE_VARIANT", "overlay")
        (self.folder / "root.h").write_text("int declaration;\n")
        self.prepare('#include "root.h"\n', [(1, "root.h")])
        if variant in {"overlay", "umbrella", "header", "context"}:
            names = {"overlay": "overlay.json", "umbrella": "input.h", "header": "root.h", "context": "context.bin"}
            path = self.folder / names[variant]
            path.write_bytes(path.read_bytes() + b"\n")
        elif variant == "request":
            self.request["bindings"]["contextSHA256"] = "0" * 64
            self.request_path.write_text(json.dumps(self.request))
        elif variant == "collision":
            index = self.trace_call.index("-hanlin-preprocess-provenance") + 1
            self.trace_call[index] = str(self.folder / "metadata.bin")
        else:
            self.fail("Unknown negative variant")
        run, receipt = self.trace()
        self.assertNotEqual(run.returncode, 0)
        self.assertTrue(WRAPPER.validate_preprocessing_receipt(receipt, self.request))

    def test_debugger_cancellation_during_observed_preprocessor_lex(self):
        (self.folder / "root.h").write_text("int declaration;\n")
        self.prepare('#include "root.h"\n', [(1, "root.h")])
        observer = self.evidence / "lldb_cancel.py"
        observer.write_bytes((ROOT / "Scripts/CI/MetadataProvenanceProof/lldb_cancel.py").read_bytes())
        config = self.evidence / "debugger-cancel-config.json"
        facts_path = self.evidence / "debugger-cancel-facts.json"
        self.record(config.name, {"executable": str(self.tool), "binarySHA256": self.sha(self.tool),
                                 "observerSHA256": self.sha(observer), "receipt": str(self.receipt_path), "output": str(facts_path)})
        call = ["xcrun", "lldb", "--batch", "-o", "command script import " + shlex.quote(str(observer)),
                "-o", "breakpoint set --name 'clang::Preprocessor::Lex(clang::Token&)'",
                "-o", "run", "-o", "thread backtrace all", "-o", "image list -o -f",
                "-o", "hanlin-cancel " + shlex.quote(str(config)), "-o", "quit", "--", *self.trace_call]
        run = self.run_recorded("observed-lldb-cancellation", call, timeout=45)
        if not facts_path.is_file():
            self.not_observed("Debugger did not retain an actual stopped PP Lex observation on this single attempt")
        facts = json.loads(facts_path.read_text())
        if facts.get("status") != "OBSERVED_CANCELLED":
            self.not_observed("Actual debugger ownership/same-thread PP Lex/unfinished/kill boundary was not established")
        self.assertEqual(run.returncode, 0)
        self.assertTrue(facts["unfinishedEstablished"])
        self.assertTrue(facts["ownedExecutable"])
        self.assertTrue(facts["killSucceeded"])
        self.assertTrue(facts["exited"])
        self.assertGreater(facts["pid"], 0)
        self.assertEqual(facts["executableSHA256"], self.sha(self.tool))
        self.assertFalse(facts["beforeKillReceipt"]["exists"])
        self.assertFalse(facts["afterKillReceipt"]["exists"])
        self.assertFalse(self.receipt_path.exists())
        self.assertTrue(WRAPPER.validate_preprocessing_receipt({}, self.request))
        self.assert_canaries()

    def test_cancelled_native_process_cannot_leave_a_complete_receipt(self):
        # One attempt; observing a stopped PID alone does NOT establish an
        # unfinished operation. A completed pre-cancel receipt is not a defect.
        import selectors
        import signal
        (self.folder / "root.h").write_text("int declaration;\n")
        self.prepare('#include "root.h"\n', [(1, "root.h")])
        label = "cancellation-native"
        self.commands.append(label)
        self.record(label + ".command.json", {"argv": self.trace_call, "cwd": str(self.tool.parent),
            "environmentSHA256": hashlib.sha256(json.dumps(dict(os.environ), sort_keys=True).encode()).hexdigest(),
            "timeoutSeconds": None, "phaseLimitsSeconds": {"startup": 10, "observer": 10, "reap": 10}})
        facts = {"schemaVersion": 1, "expectedExecutable": str(self.tool), "expectedBinarySHA256": self.sha(self.tool),
            "startupObserved": False, "wifStopped": False, "unfinishedEstablished": False, "killSent": False}
        startup, remaining = b"", b""
        with (self.evidence / (label + ".stderr")).open("wb") as stderr:
            child = subprocess.Popen(self.trace_call, cwd=self.tool.parent, stdout=subprocess.PIPE, stderr=stderr)
            facts["pid"] = child.pid
            selector = selectors.DefaultSelector()
            selector.register(child.stdout, selectors.EVENT_READ)
            try:
                if not selector.select(timeout=10):
                    self.not_observed("Native startup was not observed on this single attempt")
                startup = os.read(child.stdout.fileno(), 4096)
                (self.evidence / "cancellation.startup.stdout").write_bytes(startup)
                facts["startupObserved"] = bool(startup)
                if not startup or child.poll() is not None:
                    facts["beforeCancelReceipt"] = self.receipt_snapshot("cancellation.before-cancel")
                    self.not_observed("Native process exited before a stopped unfinished boundary could be established")
                try:
                    os.kill(child.pid, signal.SIGSTOP)
                except ProcessLookupError:
                    facts["beforeCancelReceipt"] = self.receipt_snapshot("cancellation.before-cancel")
                    self.not_observed("Native process exited before SIGSTOP")
                waited_pid, status = os.waitpid(child.pid, os.WUNTRACED)
                facts.update(waitedPID=waited_pid, waitStatus=status, wifStopped=os.WIFSTOPPED(status))
                if not facts["wifStopped"]:
                    child.returncode = os.waitstatus_to_exitcode(status)
                    facts["beforeCancelReceipt"] = self.receipt_snapshot("cancellation.before-cancel")
                    self.not_observed("No WIFSTOPPED boundary; child exited before cancellation")
                before = self.receipt_snapshot("cancellation.before-cancel")
                facts["beforeCancelReceipt"] = before
                if before["completedReceipt"]:
                    self.not_observed("Receipt already completed BEFORE cancellation; this is not a cancellation defect")
                if before["exists"]:
                    self.not_observed("Receipt publication already began BEFORE cancellation; unfinished operation unproven")
                try:
                    ps_command = ["/bin/ps", "-ww", "-p", str(child.pid), "-o", "pid=", "-o", "stat=", "-o", "comm="]
                    ps_before = self.run_recorded("cancellation.ps-before", ps_command, timeout=10)
                    sample = self.run_recorded("cancellation.sample", ["/usr/bin/sample", str(child.pid), "1", "1"], timeout=10)
                    ps_after = self.run_recorded("cancellation.ps-after", ps_command, timeout=10)
                except (OSError, subprocess.SubprocessError) as error:
                    self.not_observed("Stopped-process observer unavailable: " + type(error).__name__)
                facts["afterObserverReceipt"] = self.receipt_snapshot("cancellation.after-observer")
                if facts["afterObserverReceipt"]["completedReceipt"]:
                    self.not_observed("Completed receipt observed BEFORE kill; cancellation operation was not proven unfinished")
                if facts["afterObserverReceipt"]["exists"]:
                    self.not_observed("Receipt publication observed BEFORE kill; unfinished operation unproven")
                if any(result.returncode != 0 for result in [ps_before, sample, ps_after]):
                    self.not_observed("Observer failed; executable/unfinished stopped boundary unproven")
                proof = self.unfinished_lex_boundary(sample.stdout, ps_before.stdout, ps_after.stdout, child.pid, str(self.tool))
                facts["boundaryProof"] = proof
                if not proof["established"]:
                    self.not_observed(proof["reason"])
                facts["unfinishedEstablished"] = True
            finally:
                # Snapshot while still stopped, BEFORE any intentional kill.
                try:
                    facts["immediatelyBeforeKillReceipt"] = self.receipt_snapshot("cancellation.immediately-before-kill")
                except Exception as error:
                    facts["beforeKillSnapshotError"] = type(error).__name__ + ": " + str(error)
                facts["eligibleForCancellationAssertion"] = facts["unfinishedEstablished"] \
                    and "immediatelyBeforeKillReceipt" in facts and not facts["immediatelyBeforeKillReceipt"]["exists"]
                selector.close()
                if child.poll() is None:
                    child.kill()
                    facts["killSent"] = True
                try:
                    remaining, _ = child.communicate(timeout=10)
                except subprocess.TimeoutExpired as error:
                    remaining = error.stdout or b""
                    raise
                finally:
                    (self.evidence / (label + ".stdout")).write_bytes(startup + (remaining or b""))
                    facts.update(returncode=child.returncode, reaped=child.returncode is not None)
                    try:
                        facts["afterReapReceipt"] = self.receipt_snapshot("cancellation.after-reap")
                    except Exception as error:
                        facts["afterReapSnapshotError"] = type(error).__name__ + ": " + str(error)
                    self.record("cancellation.boundary.json", facts)
                    self.record(label + ".exit.json", {"returncode": child.returncode})
        if "immediatelyBeforeKillReceipt" not in facts:
            self.not_observed("Immediately-before-kill completion snapshot unavailable")
        if facts["immediatelyBeforeKillReceipt"]["completedReceipt"]:
            self.not_observed("Completion occurred BEFORE cancellation; not a cancellation defect")
        if facts["immediatelyBeforeKillReceipt"]["exists"]:
            self.not_observed("Receipt publication began BEFORE cancellation; unfinished boundary unproven")
        if "afterReapReceipt" not in facts:
            self.not_observed("Post-reap receipt snapshot unavailable; cancellation outcome unproven")
        self.assertTrue(facts["eligibleForCancellationAssertion"])
        self.assertTrue(facts["unfinishedEstablished"])
        self.assertTrue(facts["killSent"])
        self.assertTrue(facts["reaped"])
        self.assertEqual(child.returncode, -signal.SIGKILL)
        # Only the proven unfinished stopped executable is eligible for this
        # post-kill assertion. Missing symbols/permission/races never PASS.
        receipt = facts["afterReapReceipt"].get("receipt", {})
        self.assertTrue(WRAPPER.validate_preprocessing_receipt(receipt, self.request))
        self.assert_canaries()

    def receipt_snapshot(self, label):
        exists = self.receipt_path.exists()
        body = self.receipt_path.read_bytes() if exists else b""
        (self.evidence / (label + ".receipt.raw")).write_bytes(body)
        result = self.receipt_state_from_bytes(body, exists)
        self.record(label + ".receipt-state.json", result)
        return result

    @staticmethod
    def receipt_state_from_bytes(body, exists):
        result = {"exists": exists, "bytes": len(body), "sha256": hashlib.sha256(body).hexdigest(), "completedReceipt": False,
            "completionState": "PRESENT_UNPARSEABLE" if exists else "ABSENT"}
        try:
            receipt = json.loads(body)
            result["receipt"] = receipt
            result["completedReceipt"] = isinstance(receipt, dict) and receipt.get("mode") == "preprocessing-provenance" \
                and isinstance(receipt.get("status"), str) and receipt["status"] in {"COMPLETE", "INCOMPLETE"}
            result["completionState"] = "FINAL_RECEIPT" if result["completedReceipt"] else "UNRECOGNIZED_JSON"
        except (ValueError, UnicodeError) as error:
            result["parseError"] = type(error).__name__
        return result

    @staticmethod
    def unfinished_lex_boundary(sample_bytes, ps_before, ps_after, pid, executable):
        """Conservative classification of REAL observer output, not attestation.

        Unsupported output/symbols produce NOT_OBSERVED. Both active provenance
        action and PP lex frames must be in the SAME sampled thread block.
        """
        failure = lambda reason: {"established": False, "reason": reason}
        for snapshot in [ps_before, ps_after]:
            fields = snapshot.decode("utf-8", errors="replace").strip().split(None, 2)
            if len(fields) != 3 or fields[0] != str(pid) or "T" not in fields[1]:
                return failure("PID/stopped state not established before and after sampling")
            if fields[2] not in {executable, Path(executable).name}:
                return failure("Observed command does not identify the expected native executable")
        text = sample_bytes.decode("utf-8", errors="replace")
        path = re.search(r"(?m)^Path:\s*(.+?)\s*$", text)
        process = re.search(r"(?m)^Process:.*\[(\d+)\]\s*$", text)
        if not path or path[1] != executable or not process or process[1] != str(pid):
            return failure("Sample does not establish exact executable path and PID")
        # Do not mix unrelated threads or Binary Images text into proof.
        stack = text.split("Binary Images:", 1)[0]
        blocks = re.split(r"(?m)^.*\bThread_[^\n]*\n", stack)[1:]
        for block in blocks:
            if "HanlinProvenanceAction::ExecuteAction" in block and "clang::Preprocessor::Lex" in block:
                return {"established": True, "reason": "Observed same-thread active provenance PP lex stack while stopped",
                    "sampleSHA256": hashlib.sha256(sample_bytes).hexdigest(), "pid": pid, "executable": executable}
        return failure("Active same-thread provenance/PP lex frames unproven; no unfinished-operation claim")

    def test_normal_sdk31_binary_invalidtype_context_and_combined_public_api_controls(self):
        if os.environ.get("HANLIN_RUN_PROVENANCE_FULL_NATIVE_CONTROLS") != "1":
            self.skipTest("NOT_RUN: SDK/provider compilation requires its separate native authorization")
        environment = {**os.environ, "HANLIN_METADATA_PREPROCESS_PROVENANCE": "0"}
        with patch.dict(os.environ, environment, clear=True):
            run = self.run_recorded("normal-sdk-combined-probe", [sys.executable, str(ROOT / "Scripts/NativeScript/probe-sdk-metadata.py"),
                "--generator", str(self.tool), "--runtime-wrapper"], cwd=ROOT, timeout=1200)
        result = json.loads((ROOT / "build/acceptance/nativescript-sdk-probe/result.json").read_text())
        self.record("normal-sdk-combined-probe.result.json", result)
        self.assertEqual(run.returncode, 0, "Combined metadata must genuinely generate after alias-contract v2")
        self.assertEqual(result["modes"]["textual-public"]["status"], "EXECUTED_PASS")
        self.assertGreater(result["modes"]["textual-public"]["metadataBytes"], 0)
        parity = result["unchangedUIKitAndHostDeclarationParity"]
        self.assertEqual(parity["status"], "EXECUTED_PASS")
        self.assertEqual(len(parity["yamlSHA256"]["candidate"]), 31)
        self.assertEqual(result["invalidDeclarationRejected"]["status"], "EXECUTED_PASS")
        self.assertEqual(result["nativeCompilerContext"]["status"], "EXECUTED_PASS")
        combined = result["runtimeWrapper"]
        self.assertEqual(combined["headerAliasValidation"]["status"], "VERIFIED")
        self.assertEqual(combined["headerAliasValidation"]["contractVersion"], 2)
        self.assertGreater(combined["headerAliasValidation"]["notAliased"], 0)
        self.assertEqual(combined["symbolChecksStatus"], "EXECUTED")
        self.assertTrue(all(combined["publicObjCAndCMetadataNames"].values()))
        self.assertEqual(combined["visibility"]["clangErrorCount"], 0)


if __name__ == "__main__":
    unittest.main()
