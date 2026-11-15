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
            alias.write_text("// different bytes must stay visible")
            records = HEADERS.write_public_umbrella(root, root / "input.h", [], [owner.parent])
            overlay = root / "aliases.json"
            with self.assertRaisesRegex(RuntimeError, "Conflicting public header alias bytes"):
                HEADERS.write_verified_header_alias_overlay(records, overlay)
            self.assertFalse(overlay.exists())

    def test_identical_entry_with_changed_alias_dependency_is_rejected(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            owner = self.framework(root / "products", "lower")
            alias_root = root / "products/Carrier.framework/Headers/lower"
            shutil.copytree(owner / "Headers", alias_root)
            (alias_root / "Exported.h").write_text("// changed relative dependency of identical Entry.h")
            records = HEADERS.write_public_umbrella(root, root / "input.h", [], [owner.parent])
            with self.assertRaisesRegex(RuntimeError, "Conflicting public header alias dependency tree"):
                HEADERS.write_verified_header_alias_overlay(records, root / "aliases.json")

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
