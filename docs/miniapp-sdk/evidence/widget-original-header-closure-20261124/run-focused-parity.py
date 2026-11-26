import hashlib, importlib.util, json, pathlib, sys, unittest
from unittest.mock import patch
EVIDENCE = pathlib.Path(__file__).resolve().parent
ROOT = EVIDENCE.parents[3]
metadata = json.loads((EVIDENCE / "manifest-evaluation.json").read_text())
for relative, expected in metadata["sourceSHA256"].items():
    assert hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() == expected, relative
remote = metadata["remoteRoot"]
def relocate(value):
    if isinstance(value, str):
        return value.replace(remote, str(ROOT))
    if isinstance(value, list):
        return [relocate(item) for item in value]
    if isinstance(value, dict):
        return {key: relocate(item) for key, item in value.items()}
    return value
manifests = {label: relocate(json.loads((EVIDENCE / (label + "-manifest.json")).read_text()))
             for label in ("unified", "expo", "widgets")}
paths = {ROOT: "unified", ROOT / "Packages/HanlinExpoRuntime": "expo",
         ROOT / "Packages/HanlinWidgetSDK": "widgets"}
spec = importlib.util.spec_from_file_location("test_widget_cxx_imports", ROOT / "Scripts/SDK/tests/test_widget_cxx_imports.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
if sys.argv[1:] == ["--generate"]:
    output = module.update_project.update(package=manifests["unified"])
    module.update_project.FILE.write_text(output)
    print("PASS: regenerated native project with actual Mac-evaluated unified manifest")
else:
    assert not sys.argv[1:]
    suite = unittest.TestSuite([module.WidgetCxxImportTests(
        "test_real_widget_consumers_preserve_original_expo_cpp_import_contract")])
    # Only canonical workspace path relocation is applied to genuine dump-package
    # output. No manifest fields, settings, targets or test assertions are changed.
    with patch.object(module, "dump", side_effect=lambda path: manifests[paths[path]]):
        result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
