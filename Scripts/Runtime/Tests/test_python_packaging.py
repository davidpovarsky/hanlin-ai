import base64
import csv
import hashlib
import importlib
import io
import json
import os
from pathlib import Path
import runpy
import sys
import tarfile
import tempfile
import unittest
import zipfile

RESOURCE = Path(__file__).resolve().parents[3] / "AI_HLY/Downstream/RuntimeCore/Python/Resources"


def wheel_bytes(name, version="1.0", requires=(), code="VALUE = 42\n", tag="py3-none-any", files=None):
    name = name.replace("-", "_")
    info = f"{name}-{version}.dist-info"
    entries = {
        name + "/__init__.py": code.encode(),
        info + "/METADATA": (f"Metadata-Version: 2.3\nName: {name}\nVersion: {version}\nRequires-Python: >=3.9\n" + "".join("Requires-Dist: " + r + "\n" for r in requires) + "\n").encode(),
        info + "/WHEEL": ("Wheel-Version: 1.0\nGenerator: Hanlin acceptance fixture\nRoot-Is-Purelib: true\nTag: " + tag + "\n").encode(),
        **(files or {}),
    }
    record = io.StringIO(newline="")
    writer = csv.writer(record, lineterminator="\n")
    for path, content in entries.items():
        digest = base64.urlsafe_b64encode(hashlib.sha256(content).digest()).rstrip(b"=").decode()
        writer.writerow((path, "sha256=" + digest, str(len(content))))
    writer.writerow((info + "/RECORD", "", ""))
    entries[info + "/RECORD"] = record.getvalue().encode()
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w") as archive:
        for path, content in entries.items():
            archive.writestr(path, content)
    return f"{name}-{version}-{tag}.whl", output.getvalue()


class PythonPackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="hanlin-packaging-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.index = self.root / "index"
        self.index.mkdir()
        lock = json.loads((RESOURCE / "HanlinPythonPackaging.lock.json").read_text())
        self.resources = [{"path": str(RESOURCE / "Vendor" / p["file"]), "sha256": p["sha256"]} for p in lock["packages"]]
        self.module = runpy.run_path(str(RESOURCE / "HanlinPythonPackaging.py"))
        self.packages = {}

    def project(self, name, version="1.0", requires=(), code="VALUE = 42\n", tag="py3-none-any", requires_python=None, files=None):
        filename, content = wheel_bytes(name, version, requires, code, tag, files)
        archive = self.index / filename
        archive.write_bytes(content)
        releases = self.packages.setdefault(name, {})
        releases.setdefault(version, []).append({"filename": filename, "url": archive.as_uri(), "packagetype": "bdist_wheel",
            "requires_python": requires_python, "digests": {"sha256": hashlib.sha256(content).hexdigest()}})
        path = self.index / "pypi" / name / "json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"releases": releases}))
        return archive

    def execute(self, requirement, destination=True):
        request = {"requirement": str(requirement), "indexURL": self.index.as_uri(), "workspace": str(self.root / "workspace"), "resources": self.resources}
        if destination:
            request["destination"] = str(self.root / "installed")
        return self.module["run"](request)

    def imported_value(self, name):
        previous = sys.path[:]
        try:
            sys.path.insert(0, str(self.root / "installed"))
            importlib.invalidate_caches()
            return importlib.import_module(name).VALUE
        finally:
            sys.path[:] = previous
            for key in list(sys.modules):
                if key == name or key.startswith(name + "."):
                    sys.modules.pop(key)

    def test_pep440_extras_markers_backtracking_requires_python_and_real_import(self):
        self.project("rootpkg", requires=["adep>=1", "bdep>=1", "extra_pkg; extra == 'test' and python_version >= '3.9'", "absent; python_version < '2'"])
        self.project("adep", "1.0", code="VALUE = 101\n")
        self.project("adep", "2.0", code="VALUE = 202\n")
        self.project("adep", "99.0", requires_python=">=99")
        self.project("bdep", requires=["adep<2"])
        self.project("extra-pkg")
        result = self.execute("rootpkg[test]>=1")
        versions = {p["name"]: p["version"] for p in result["dependencies"]}
        self.assertEqual(versions["adep"], "1.0")
        self.assertIn("extra-pkg", versions)
        self.assertNotIn("absent", versions)
        self.assertEqual(self.imported_value("adep"), 101)

    def test_local_wheel_installs_and_inactive_binary_data_does_not_block_it(self):
        wheel = self.project("localpkg", code="VALUE = 'local-wheel'\n", files={
            "localpkg/examples/unused.so": b"\x7fELFnot-loaded",
            "localpkg/examples/fixture-1.0.dist-info/METADATA": b"Inactive example metadata\n",
        })
        result = self.execute(wheel)
        self.assertEqual(result["root"]["name"], "localpkg")
        self.assertEqual(self.imported_value("localpkg"), "local-wheel")
        self.assertTrue((self.root / "installed/localpkg/examples/unused.so").exists())

    def test_wrong_interpreter_wheel_tags_are_rejected(self):
        wheel = self.project("wrongtag", tag="cp999-cp999-ios_99_0_arm64_iphoneos")
        with self.assertRaisesRegex(ValueError, "tags do not match"):
            self.execute(wheel)

    def test_checksum_failure_never_installs(self):
        wheel = self.project("tampered")
        wheel.write_bytes(b"tampered")
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            self.execute("tampered")
        self.assertFalse((self.root / "installed").exists())

    def test_local_source_and_sdist_use_real_pep517_hooks_without_subprocess(self):
        source = self.root / "source"
        source.mkdir()
        (source / "pyproject.toml").write_text('[build-system]\nrequires=[]\nbuild-backend="fixture_backend"\nbackend-path=["."]\n')
        filename, content = wheel_bytes("sourcepkg", code="VALUE = 'built-from-source'\n")
        (source / "fixture_backend.py").write_text(
            "from pathlib import Path\nimport base64\n"
            "def get_requires_for_build_wheel(config_settings=None): return []\n"
            "def build_wheel(wheel_directory, config_settings=None, metadata_directory=None):\n"
            f"    Path(wheel_directory, {filename!r}).write_bytes(base64.b64decode({base64.b64encode(content).decode()!r}))\n"
            f"    return {filename!r}\n")
        result = self.execute(source)
        self.assertEqual(result["root"]["name"], "sourcepkg")
        self.assertEqual(self.imported_value("sourcepkg"), "built-from-source")
        shutil = __import__("shutil")
        shutil.rmtree(self.root / "installed")
        archive = self.root / "sourcepkg-1.0.tar.gz"
        with tarfile.open(archive, "w:gz") as output:
            output.add(source, arcname="sourcepkg-1.0")
        self.execute(archive)
        self.assertEqual(self.imported_value("sourcepkg"), "built-from-source")

    def test_actual_graph_larger_than_old_512_limit(self):
        count = 530
        for index in range(count):
            self.project(f"chain{index}", requires=[f"chain{index+1}>=1"] if index + 1 < count else [])
        result = self.execute("chain0", destination=False)
        self.assertEqual(len(result["dependencies"]), count - 1)

    @unittest.skipUnless(os.environ.get("HANLIN_RUN_PACKAGING_NETWORK") == "1", "explicit real PyPI/backend integration")
    def test_real_flit_backend_download_build_install_and_import(self):
        source = self.root / "real-flit-source"
        source.mkdir()
        (source / "pyproject.toml").write_text('''[build-system]
requires = ["flit_core>=3.12,<4"]
build-backend = "flit_core.buildapi"
[project]
name = "hanlin-real-backend-proof"
version = "1.0.0"
description = "Native packaging acceptance"
[tool.flit.module]
name = "hanlin_real_backend_proof"
''')
        (source / "hanlin_real_backend_proof.py").write_text("VALUE = 'real-flit-built-and-imported'\n")
        request = {"requirement": str(source), "indexURL": "https://pypi.org", "workspace": str(self.root / "workspace"),
                   "destination": str(self.root / "installed"), "resources": self.resources}
        result = self.module["run"](request)
        self.assertEqual(result["root"]["name"], "hanlin-real-backend-proof")
        self.assertEqual(self.imported_value("hanlin_real_backend_proof"), "real-flit-built-and-imported")
        print(json.dumps({"proof": "real-flit-pep517-build-install-import", "artifact": result["root"]}))


if __name__ == "__main__":
    unittest.main()
