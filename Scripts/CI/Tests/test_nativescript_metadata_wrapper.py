import contextlib
import importlib.util
import io
import os
from pathlib import Path
import shlex
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("hanlin_metadata_wrapper", ROOT / "Scripts/NativeScript/build-step-metadata-generator-wrapper.py")
WRAPPER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(WRAPPER)


class NativeScriptMetadataWrapperTests(unittest.TestCase):
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
            self.assertEqual(flags[-2:], ["-include", str(root / "HanlinMetadataImports.h")])
            self.assertIn(f"-fmodule-map-file={module}", flags)
            self.assertIn("@import HanlinNativeServicesBridge;", (root / "HanlinMetadataImports.h").read_text())

    def test_upstream_success_without_bridge_metadata_fails_and_keeps_diagnostics(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            generator = root / "generator"
            generator.mkdir()
            (generator / "build-step-metadata-generator-upstream.py").write_text("# test harness only")
            objroot = root / "intermediates"
            header = objroot / "GeneratedModuleMaps-iphonesimulator/HanlinNativeScriptRuntime-Swift.h"
            header.parent.mkdir(parents=True)
            header.write_text("// generated header")
            products = root / "products"
            products.mkdir()
            diagnostic = products / "metadata-generation-stderr-arm64.txt"
            diagnostic.write_text("error: missing native module\n")
            (products / "metadata-arm64.bin").write_bytes(b"NSObject\0UIView\0")
            env = {"OBJROOT": str(objroot), "SRCROOT": str(root), "TARGET_TEMP_DIR": str(root / "target"),
                   "PLATFORM_NAME": "iphonesimulator", "CONFIGURATION_BUILD_DIR": str(products)}
            with patch.dict(os.environ, env), patch.object(WRAPPER, "__file__", str(generator / "wrapper.py")), \
                 patch.object(WRAPPER.sys, "argv", ["wrapper", "arm64"]), \
                 patch.object(WRAPPER.subprocess, "run") as run, contextlib.redirect_stdout(io.StringIO()):
                run.return_value.returncode = 0
                self.assertEqual(WRAPPER.main(), 1)
            retained = root / "build/acceptance/nativescript-metadata/iphonesimulator-arm64"
            self.assertEqual((retained / diagnostic.name).read_bytes(), diagnostic.read_bytes())
            self.assertEqual((retained / "metadata-arm64.bin").read_bytes(), b"NSObject\0UIView\0")
            self.assertIn('"HanlinNativeServicesBridge": false', (retained / "visibility.json").read_text())


if __name__ == "__main__":
    unittest.main()
