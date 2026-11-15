"""Compatibility entry point: execute production packaging acceptance, not a mirrored resolver."""
import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[2] / "Runtime/Tests/test_python_packaging.py"
spec = importlib.util.spec_from_file_location("hanlin_python_packaging_acceptance", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
PythonPackageManagerRulesTests = module.PythonPackagingTests

if __name__ == "__main__":
    unittest.main()
