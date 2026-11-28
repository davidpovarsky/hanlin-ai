"""Execute the production capsule owner against real portable CPython C APIs."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]

@unittest.skipIf(sys.version_info < (3, 12), "Production exception preservation requires CPython 3.12+ C APIs")
class PythonCancellationContextTests(unittest.TestCase):
    def test_retained_callback_owns_flag_and_releases_it_without_erasing_exception(self):
        with tempfile.TemporaryDirectory(prefix="hanlin-cancellation-capi-") as directory:
            root = Path(directory)
            fixture = REPOSITORY / "Scripts/Runtime/Tests/python_cancellation_probe.cpp"
            (root / "probe.cpp").write_bytes(fixture.read_bytes())
            include = str(REPOSITORY / "AI_HLY/Downstream/RuntimeCore/Python/Native")
            flags = ["/std:c++17"] if os.name == "nt" else ["-std=c++17"]
            (root / "setup.py").write_text(
                "from setuptools import setup, Extension\n" +
                f"setup(name='cancellation-probe', ext_modules=[Extension('_cancellation_probe', ['probe.cpp'], include_dirs=[{include!r}], extra_compile_args={flags!r}, language='c++')])\n",
                encoding="utf-8")
            built = subprocess.run([sys.executable, "setup.py", "build_ext", "--inplace"], cwd=root,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
            self.assertEqual(built.returncode, 0, built.stdout.decode("utf-8", errors="replace"))
            proof = """
import gc
import _cancellation_probe as probe
for index in range(10000):
    callback = probe.make()
    assert probe.alive(), 'The retained callback lost its native owner'
    assert callback() is False
    probe.cancel()
    assert callback() is True
    del callback
    assert not probe.alive(), 'The capsule leaked the flag'
try:
    probe.preserve_error()
except RuntimeError as error:
    assert str(error) == 'original exception preserved'
else:
    raise AssertionError('Destruction erased the active exception')
gc.collect()
print('CANCELLATION_CAPSULE_10000_CYCLES_PASSED')
"""
            result = subprocess.run([sys.executable, "-c", proof], cwd=root,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout.decode("utf-8", errors="replace"))
            self.assertIn(b"CANCELLATION_CAPSULE_10000_CYCLES_PASSED", result.stdout)

if __name__ == "__main__": unittest.main()
