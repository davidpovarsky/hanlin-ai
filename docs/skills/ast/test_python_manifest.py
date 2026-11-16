import importlib.util
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
WHEEL = ROOT/'AI_HLY/Downstream/RuntimeCore/Python/Resources/Vendor/packaging-26.3-py3-none-any.whl'
sys.path.insert(0, str(WHEEL))
import packaging
from packaging.requirements import Requirement
assert packaging.__version__ == '26.3' and str(WHEEL) in packaging.__file__
RESOURCE = ROOT/'AI_HLY/Downstream/AgentSkills/Analysis/Resources/hanlin_python_manifest.py'
spec = importlib.util.spec_from_file_location('owned_passive_manifest', RESOURCE)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


def scan(file, source, **budgets):
    return helper.analyze_python_manifest(file, source.encode(), requirement_parser=Requirement,
                                         packaging_version=packaging.__version__, **budgets)


class PythonManifestTests(unittest.TestCase):
    def test_original_requirements_parser_preserves_constraints_lines_and_no_import_mapping(self):
        source = '# source\r\nPillow>=10; python_version >= "3.14"\r\nrequests[socks]==2.32.5\r\n'
        report = scan('requirements.txt', source)
        values = [f['value'] for f in report['findings'] if f['kind'] == 'dependencyDeclaration']
        self.assertEqual(values, ['Pillow>=10; python_version >= "3.14"', 'requests[socks]==2.32.5'])
        self.assertEqual(report['findings'][0]['source']['line'], 2)
        self.assertEqual(report['findings'][0]['source']['byteOffset'], len('# source\r\n'.encode()))
        self.assertEqual(report['completion'], 'complete')
        self.assertFalse(any(f['kind'] == 'moduleReference' for f in report['findings']))

    def test_pip_includes_dynamic_continuations_and_invalid_lines_are_unknown_not_followed(self):
        report = scan('requirements.txt', '-r do-not-read.txt\nfoo \\\nnot a requirement ???\n')
        self.assertEqual(report['completion'], 'partial')
        self.assertEqual(len(report['findings']), 3)
        self.assertTrue(all(f['kind'] == 'unknown' for f in report['findings']))

    def test_stdlib_toml_dependencies_keep_honest_whole_document_spans(self):
        source = '''[project]
dependencies = ["requests>=2.31"]
requires-python = ">=3.14"
[project.optional-dependencies]
images = ["Pillow>=10"]
[build-system]
requires = ["setuptools>=70"]
build-backend = "DO_NOT_IMPORT"
'''
        report = scan('pyproject.toml', source)
        values = {f['value'] for f in report['findings'] if f['kind'] == 'dependencyDeclaration'}
        self.assertEqual(values, {'requests>=2.31', 'Pillow>=10', 'setuptools>=70'})
        self.assertEqual(report['completion'], 'partial')
        self.assertTrue(all(f['source']['byteLength'] == len(source.encode()) for f in report['findings']))
        self.assertTrue(all(f['confidence'] == 'unknown' for f in report['findings']))

    def test_unsupported_shapes_dynamic_metadata_duplicates_and_missing_original_parser_fail_explicitly(self):
        for source in ['[project]\ndependencies = "bad"\n', '[project]\ndynamic=["dependencies"]\n',
                       '[project]\nname="x"\nname="y"\n', '[tool.poetry.dependencies]\nrequests="*"\n']:
            report = scan('pyproject.toml', source)
            self.assertNotEqual(report['completion'], 'complete')
            self.assertTrue(any(f['kind'] == 'unknown' for f in report['findings']))
        missing = helper.analyze_python_manifest('requirements.txt', b'requests>=2')
        self.assertEqual(missing['findings'][0]['reason'], 'trustedOriginalPackagingParserUnavailable')

    def test_bounds_cancel_and_unknown_interpretation_remain_distinct_from_no_requirements(self):
        report = scan('requirements.txt', 'a\n' * 30, maximum_findings=3)
        self.assertLessEqual(len(report['findings']), 3)
        self.assertEqual(report['completion'], 'partial')
        self.assertEqual(scan('pyproject.toml', '[project]\nname="x"', maximum_nodes=1)['completion'], 'unknown')
        self.assertEqual(scan('requirements.txt', 'requests', maximum_bytes=1)['completion'], 'unknown')
        self.assertEqual(scan('requirements.txt', 'requests', cancelled=lambda: True)['completion'], 'unknown')
        def resource_failure(_):
            raise RecursionError('injected trusted parser resource failure')
        failed = helper.analyze_python_manifest('requirements.txt', b'requests',
            requirement_parser=resource_failure, packaging_version='26.3')
        self.assertEqual(failed['findings'][0]['reason'], 'PEP508ParserResourceError')


if __name__ == '__main__':
    print(json.dumps({'actual_python': sys.version.split()[0], 'packaging': packaging.__version__,
                      'source': 'existing original Runtime Vendor wheel', 'embedded_python314': 'NOT_RUN'}))
    unittest.main()
