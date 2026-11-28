from pathlib import Path
import copy,json,sys,tempfile,unittest,unittest.mock,importlib.util
source = Path(sys.argv[1])
name = "Scripts.CI.Tests.test_installed_expo_observer_storage"
spec = importlib.util.spec_from_file_location(name, source)
module = importlib.util.module_from_spec(spec)
before_path = list(sys.path)
before_modules = dict(sys.modules)
spec.loader.exec_module(module)
assert sys.path == before_path, "The new test module leaked sys.path"
assert sys.modules == before_modules, "The new test module leaked sys.modules"
suite = unittest.defaultTestLoader.loadTestsFromModule(module)
assert suite.countTestCases() == 8
result = unittest.TextTestRunner(verbosity=2).run(suite)
print(json.dumps({"importPathRestored": True, "importModulesRestored": True,
                  "actualTests": result.testsRun, "failures": len(result.failures), "errors": len(result.errors)}))
raise SystemExit(0 if result.wasSuccessful() and result.testsRun == 8 else 1)
