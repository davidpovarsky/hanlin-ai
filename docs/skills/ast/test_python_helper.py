"""Portable helper checks; actual engine/version is recorded, never an embedded3.14 pass."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
RESOURCE = ROOT/'AI_HLY/Downstream/AgentSkills/Analysis/Resources/hanlin_python_ast.py'
spec = importlib.util.spec_from_file_location('owned_passive_ast', RESOURCE)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class PythonHelperTests(unittest.TestCase):
    def test_mixed_python_fixtures(self):
        fixtures = json.loads((Path(__file__).parent/'Tests/Fixtures/mixed.json').read_text(encoding='utf-8'))
        selected = [f for f in fixtures if f['language'] == 'python']
        self.assertEqual(len(selected), 13)
        for fixture in selected:
            with self.subTest(file=fixture['file']):
                if fixture.get('requiresPython314') and sys.version_info < (3, 14):
                    continue  # Explicitly recorded below as NOT_RUN; no grammar emulation.
                raw = fixture['source'].encode('utf-8')
                report = helper.analyze_python_source(fixture['file'], raw)
                modules = {f['value'] for f in report['findings'] if f['kind'] == 'moduleReference'}
                self.assertTrue(set(fixture['modules']) <= modules, report)
                self.assertEqual(any(f['kind'] == 'unknown' for f in report['findings']), fixture['unknown'], report)
                self.assertNotIn(fixture.get('absent'), modules)
                self.assertEqual(report['sourceSHA256'], hashlib.sha256(raw).hexdigest())
                self.assertEqual(report['provenance']['engineVersion'], sys.version.split()[0])
                if 'conditional' in fixture:
                    self.assertTrue(any(f['value'] == fixture['conditional'] and f['confidence'] == 'conditionalSyntax'
                                        for f in report['findings']))

    def test_utf8_crlf_positions_and_unavailable_inputs(self):
        raw = "label='שלום🙂'; import PIL\r\nimport os\r\n".encode()
        report = helper.analyze_python_source('עברית.py', raw)
        for name in ('PIL', 'os'):
            fact = next(f for f in report['findings'] if f['value'] == name)
            start = raw.index(name.encode())
            self.assertEqual(fact['source']['byteOffset'], start)
            self.assertEqual(fact['source']['byteLength'], len(name))
        self.assertEqual(helper.analyze_python_source('x.py', b'\xff')['completion'], 'unknown')
        self.assertEqual(helper.analyze_python_source('x.py', b'import os', maximum_bytes=1)['findings'][0]['reason'], 'sourceBudget')
        self.assertEqual(helper.analyze_python_source('x.py', b'import os', cancelled=lambda: True)['findings'][0]['reason'], 'cancelled')

    def test_no_import_execution_or_filesystem_discovery(self):
        with tempfile.TemporaryDirectory() as folder:
            marker = Path(folder)/'must-not-exist'
            source = f"from pathlib import Path\nPath({str(marker)!r}).write_text('executed')\nimport missing_actual_package_921\n"
            report = helper.analyze_python_source('canary.py', source.encode())
            self.assertFalse(marker.exists())
            self.assertTrue(any(f['value'] == 'missing_actual_package_921' for f in report['findings']))
            self.assertEqual(report['completion'], 'complete')  # Syntax only; not installed/ready.

    def test_hostile_finding_node_depth_and_literal_limits(self):
        source = b'import a\n' * 100
        for budget in ({'maximum_nodes': 3}, {'maximum_findings': 3}, {'maximum_depth': 1}):
            report = helper.analyze_python_source('large.py', source, **budget)
            self.assertEqual(report['completion'], 'partial')
            self.assertTrue(any(f['kind'] == 'unknown' for f in report['findings']))
        huge = helper.analyze_python_source('long.py', ('import ' + 'a' * 300).encode())
        self.assertEqual(huge['findings'][0]['reason'], 'moduleNameBudget')
        surrogate = helper.analyze_python_source('escape.py', b"__import__('\\ud800')")
        self.assertEqual(surrogate['completion'], 'partial')


if __name__ == '__main__':
    print(json.dumps({'actual_python': sys.version.split()[0],
                      'embedded_python314': 'NOT_RUN', 'template314': 'EXECUTED' if sys.version_info >= (3, 14) else 'NOT_RUN'}))
    unittest.main()
