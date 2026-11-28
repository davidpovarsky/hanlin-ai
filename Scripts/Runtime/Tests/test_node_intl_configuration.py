from pathlib import Path
import ast
import gzip
import hashlib
import importlib.util
import json
import re
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).parents[1] / "configure-node-wasm.py"
FIXTURES = Path(__file__).with_name("NodeIntl")
SPEC = importlib.util.spec_from_file_location("node_intl_configuration", SCRIPT)
adapter = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(adapter)


class NodeIntlConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "node"
        self.root.mkdir()
        self.original = {}
        manifest = json.loads((FIXTURES / "SOURCE.json").read_text())
        self.assertEqual(manifest["commit"], "4768489cd0cfa3bb0c27786e958c6446c004f1bd")
        for item in manifest["files"]:
            packed = (FIXTURES / item["file"]).read_bytes()
            self.assertEqual(hashlib.sha256(packed).hexdigest(), item["compressedSHA256"])
            raw = gzip.decompress(packed)
            self.assertEqual(len(raw), item["bytes"])
            self.assertEqual(hashlib.sha256(raw).hexdigest(), item["sha256"])
            self.assertEqual(hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest(), item["gitBlob"])
            self.original[item["sourcePath"]] = raw
            target = self.root / item["sourcePath"]
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(raw)

    def invoke(self, *arguments):
        return subprocess.run([sys.executable, str(SCRIPT), str(self.root), *arguments],
                              capture_output=True, text=True, timeout=10)

    def snapshot(self):
        return {name: (self.root / name).read_bytes() for name in adapter.PREIMAGES}

    def test_pinned_icu_target_archives_are_enabled_copied_and_linked_for_original_slices(self):
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        receipt = json.loads(result.stdout)
        self.assertEqual(receipt["internationalization"], "full-icu")
        self.assertEqual(receipt["icuLibraries"], ["libicudata.a", "libicui18n.a", "libicuucx.a"])
        shell = (self.root / "tools/ios_framework_prepare.sh").read_text()
        self.assertEqual(shell.count("--with-intl=full-icu"), 3)
        self.assertNotIn("--with-intl=none", shell)
        common = shell.split("declare -a outputs_common=(", 1)[1].split("\n)", 1)[0]
        project = (self.root / "tools/ios-framework/NodeMobile.xcodeproj/project.pbxproj").read_text()
        framework_phase = project.split("/* Begin PBXFrameworksBuildPhase section */", 1)[1].split("/* End PBXFrameworksBuildPhase section */", 1)[0]
        groups = project.split("/* Begin PBXGroup section */", 1)[1].split("/* End PBXGroup section */", 1)[0]
        targets = {}
        def collect(value):
            if isinstance(value, dict):
                if "target_name" in value:
                    targets[value["target_name"]] = value
                for child in value.values():
                    collect(child)
            elif isinstance(value, list):
                for child in value:
                    collect(child)
        collect(ast.literal_eval(self.original["tools/icu/icu-generic.gyp"].decode()))
        self.assertEqual(targets["icuuc"]["type"], "none")
        self.assertEqual(targets["icutools"]["toolsets"], ["host"])
        for target in ("icudata", "icui18n", "icuucx"):
            self.assertIn("target", targets[target]["toolsets"])
            library = "lib" + target + ".a"
            self.assertEqual(common.count('"' + library + '"'), 1)
            file_rows = re.findall(r"([A-F0-9]{24}) /\* " + re.escape(library) + r" \*/ = \{isa = PBXFileReference; [^\n]+", project)
            build_rows = re.findall(r"([A-F0-9]{24}) /\* " + re.escape(library) + r" in Frameworks \*/ = \{isa = PBXBuildFile; fileRef = ([A-F0-9]{24})", project)
            self.assertEqual(len(file_rows), 1)
            self.assertEqual(len(build_rows), 1)
            self.assertEqual(build_rows[0][1], file_rows[0])
            self.assertEqual(framework_phase.count(build_rows[0][0] + " /* " + library + " in Frameworks */"), 1)
            self.assertEqual(groups.count(file_rows[0] + " /* " + library + " */"), 1)
            self.assertIn("path = bin/" + library + ";", project)
        self.assertNotIn('"libicuuc.a"', common)
        self.assertNotIn('"libicutools.a"', common)

    def test_existing_wasm_outputs_and_all_other_framework_settings_remain_exact(self):
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(hashlib.sha256((self.root / "tools/v8_gypfiles/features.gypi").read_bytes()).hexdigest(),
                         "90da41738ea9ec84ed3c633b6c3e92281116f5c83e9b79a4fba5771d0af94396")
        self.assertEqual(hashlib.sha256((self.root / "tools/v8_gypfiles/v8.gyp").read_bytes()).hexdigest(),
                         "d55186e1cf0e015994c34f46d3df40b3ce18e642b17e229440ba4cce97a1532a")
        libraries = ("libicudata.a", "libicui18n.a", "libicuucx.a")
        shell = (self.root / "tools/ios_framework_prepare.sh").read_text()
        shell = shell.replace("--with-intl=full-icu", "--with-intl=none")
        for library in libraries:
            shell = shell.replace('  "' + library + '"\n', "")
        self.assertEqual(hashlib.sha256(shell.encode()).hexdigest(),
                         "1d08245dd2b0382b5097533b9628eb40e5a36a2dc39adb2753b2539c4953d052")
        project = (self.root / "tools/ios-framework/NodeMobile.xcodeproj/project.pbxproj").read_text()
        restored = "".join(line for line in project.splitlines(keepends=True) if not any(library in line for library in libraries))
        self.assertEqual(restored.encode(), self.original["tools/ios-framework/NodeMobile.xcodeproj/project.pbxproj"])

    def test_describe_does_not_write_and_partly_prepared_input_is_idempotent(self):
        before = self.snapshot()
        result = self.invoke("--describe")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.snapshot(), before)
        changes = adapter.proposed_changes(self.root)
        changes[0][0].write_bytes(changes[0][1])
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        once = self.snapshot()
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.snapshot(), once)

    def test_tampered_originals_are_rejected_before_any_source_write(self):
        for name in adapter.PREIMAGES:
            with self.subTest(path=name):
                for path in adapter.PREIMAGES:
                    (self.root / path).write_bytes(self.original[path])
                target = self.root / name
                target.write_bytes(target.read_bytes() + b"\nchanged upstream input\n")
                before = self.snapshot()
                result = self.invoke()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Unexpected pinned Node build preimage", result.stderr)
                self.assertEqual(self.snapshot(), before)

    def test_symlink_escape_is_rejected_before_any_source_write(self):
        name = "tools/ios-framework/NodeMobile.xcodeproj/project.pbxproj"
        outside = Path(self.temporary.name) / "outside.pbxproj"
        outside.write_bytes(self.original[name])
        target = self.root / name
        target.unlink()
        target.symlink_to(outside)
        before = self.snapshot()
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Native build adapter path escapes source root", result.stderr)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(outside.read_bytes(), self.original[name])


if __name__ == "__main__":
    unittest.main()
