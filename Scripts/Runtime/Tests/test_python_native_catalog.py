"""Execute the actual linked provider table before and after real CPython init.

Host-only header-layout/TargetConditionals shims are explicit; this portable
execution is not an iOS SDK, signing, Python3.14.6 or physical-device proof.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]

class PythonNativeCatalogTests(unittest.TestCase):
    def test_actual_catalog_does_not_initialize_or_wait_for_python_and_matches_its_registry(self):
        with tempfile.TemporaryDirectory(prefix="hanlin-native-catalog-") as directory:
            root = Path(directory)
            (root / "probe.cpp").write_bytes((ROOT / "Scripts/Runtime/Tests/python_native_catalog_probe.cpp").read_bytes())
            (root / "Python").mkdir()
            (root / "Python/Python.h").write_text("#include <Python.h>\n", encoding="utf-8")
            (root / "TargetConditionals.h").write_text("#pragma once\n#define TARGET_OS_SIMULATOR 0\n", encoding="utf-8")
            native = str(ROOT / "AI_HLY/Downstream/RuntimeCore/Python/Native")
            build = r'''from pathlib import Path
import os,shlex,sys,sysconfig
from setuptools import setup,Extension
from setuptools.command.build_ext import build_ext
class BuildProbe(build_ext):
    def build_extensions(self):
        flags = ["/std:c++17"] if os.name == "nt" else ["-std=c++17"]
        objects = self.compiler.compile(["probe.cpp"], include_dirs=[".", NATIVE, sysconfig.get_paths()["include"]], extra_postargs=flags)
        if os.name == "nt":
            self.compiler.link_executable(objects,"probe", libraries=["python"+str(sys.version_info.major)+str(sys.version_info.minor)], library_dirs=[str(Path(sys.base_prefix)/"libs")])
        else:
            libname=sysconfig.get_config_var("LDLIBRARY") or sysconfig.get_config_var("LIBRARY")
            candidates=[Path(sysconfig.get_config_var("LIBDIR") or sys.base_prefix)/libname,Path(sys.base_prefix)/"Python",Path(sysconfig.get_config_var("LIBPL") or sys.base_prefix)/libname]
            library=next((p for p in candidates if p.is_file()),None)
            if library is None:raise RuntimeError("Actual embeddable Python library unavailable")
            dependencies=shlex.split((sysconfig.get_config_var("LIBS") or "")+" "+(sysconfig.get_config_var("SYSLIBS") or ""))
            self.compiler.link_executable(objects,"probe", extra_postargs=[str(library),*dependencies])
setup(name="actual-native-catalog-probe",ext_modules=[Extension("unused",[])],cmdclass={"build_ext":BuildProbe})
'''
            (root / "setup.py").write_text("NATIVE = " + repr(native) + "\n" + build, encoding="utf-8")
            result = subprocess.run([sys.executable, "setup.py", "build_ext"], cwd=root,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout.decode("utf-8", errors="replace"))
            executable = root / ("probe.exe" if os.name == "nt" else "probe")
            environment = dict(os.environ)
            environment["PATH"] = sys.base_prefix + os.pathsep + environment.get("PATH", "")
            result = subprocess.run([str(executable), sys.base_prefix], cwd=root, env=environment,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
            output = result.stdout.decode("utf-8", errors="replace")
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("ACTUAL_NATIVE_CATALOG_NONCE_GIL_AND_LIFECYCLE_PASSED", output)
            stages = dict(line.split("\t", 1) for line in output.splitlines() if "\t" in line)
            before, registered, imported, finalized = [json.loads(stages[name])[0] for name in ("BEFORE", "REGISTERED", "IMPORTED", "FINALIZED")]
            self.assertFalse(before["registeredInittab"])
            self.assertFalse(before["initializationObserved"])
            self.assertTrue(registered["registeredInittab"])
            self.assertFalse(registered["initializationObserved"])
            self.assertTrue(imported["registeredInittab"] and imported["initializationObserved"])
            self.assertEqual(imported, finalized)  # historical facts, never a Ready claim
            self.assertEqual(imported["pythonMajor"], sys.version_info.major)
            self.assertEqual(imported["pythonMinor"], sys.version_info.minor)
            self.assertEqual(imported["module"], "_hanlin_native")
            print(json.dumps({"scope":"actual portable CPython provider table; host-only platform/header-layout shims", "before":before, "registered":registered, "initialized":imported, "finalized":finalized, "nonceAndGILFreeRead":"executed"},sort_keys=True))

if __name__ == "__main__": unittest.main()
