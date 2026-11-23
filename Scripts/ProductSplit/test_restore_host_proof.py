"""Negative controls for authenticated proof reuse; no native tests are rerun here."""
from pathlib import Path
import copy
import hashlib
import importlib.util
import io
import json
import os
import tempfile
import unittest
import warnings
import zipfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
with patch.dict(os.environ, {'SPLIT_EVIDENCE': str(ROOT/'build/foreground-reuse-tests')}):
    spec = importlib.util.spec_from_file_location('restore_host_proof', Path(__file__).with_name('restore_host_proof.py'))
    guard = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(guard)


class ForegroundProofTests(unittest.TestCase):
    prefix = 'app-split-evidence/foreground/'
    platform = 'ProductName: macOS\nProductVersion: 27.0.1\nBuildVersion: 26A434\narm64\nXcode 27.2\nBuild version 27B52\n'

    def setUp(self):
        origin = ROOT/'docs/agent-sdk/evidence/miniapps-native-45133337462'
        self.files = {self.prefix+'foreground-results.json': (origin/'foreground-results.json').read_bytes()}
        for source in (origin/'foreground-origin').iterdir():
            if source.is_file():
                self.files[self.prefix+'raw-origin/'+source.name] = source.read_bytes()
        for source in (ROOT/'docs/agent-sdk/evidence/foreground-reuse-20261123/original-raw').iterdir():
            if source.is_file():
                self.files[self.prefix+'raw-origin/'+source.name] = source.read_bytes()
        self.files['app-split-evidence/preflight.log'] = (self.platform+'original SDK list follows\n').encode()
        self.report = json.loads(self.files[self.prefix+'foreground-results.json'])
        self.origin_sha = self.report['commit_base_at_execution']
        self.toolchain = self.report['toolchain']
        self.compiler_tools = copy.deepcopy(self.report['compiler_tools'])

    def report_change(self, update):
        report = json.loads(self.files[self.prefix+'foreground-results.json'])
        update(report)
        self.files[self.prefix+'foreground-results.json'] = (json.dumps(report,indent=2)+'\n').encode()

    def raw_change(self, name, contents):
        key = self.prefix+'raw-origin/'+name
        self.files[key] = contents
        manifest_key = self.prefix+'raw-origin/manifest.json'
        manifest = json.loads(self.files[manifest_key])
        changed = None
        for record in manifest['files']:
            if Path(record['path']).name == name:
                record.update(bytes=len(contents),sha256=hashlib.sha256(contents).hexdigest())
                changed = record
        self.assertIsNotNone(changed)
        data = (json.dumps(manifest,indent=2)+'\n').encode()
        self.files[manifest_key] = data
        self.report_change(lambda r:r['raw_evidence_manifest'].update(bytes=len(data),sha256=hashlib.sha256(data).hexdigest()))
        return changed

    def validate(self, *, duplicate=None):
        stream = io.BytesIO()
        with zipfile.ZipFile(stream,'w') as packed:
            for name,data in self.files.items():
                packed.writestr(name,data)
            if duplicate:
                with warnings.catch_warnings():
                    warnings.simplefilter('ignore',UserWarning)
                    packed.writestr(duplicate,self.files[duplicate])
        stream.seek(0)
        with zipfile.ZipFile(stream) as packed:
            return guard.validate_foreground(packed,self.origin_sha,self.platform,self.toolchain,self.compiler_tools)

    def test_original_raw_foreground53_is_admitted(self):
        report,payload,_ = self.validate()
        self.assertEqual(report['count'],53)
        self.assertEqual(len(payload),20)

    def test_changed_source_digest_invalidates(self):
        self.report_change(lambda r:r['source_sha256'].__setitem__(next(iter(r['source_sha256'])),'0'*64))
        with self.assertRaisesRegex(ValueError,'source/test closure'):
            self.validate()

    def test_missing_source_invalidates_even_with_53_pass_claim(self):
        self.report_change(lambda r:r['source_sha256'].pop(next(iter(r['source_sha256']))))
        with self.assertRaisesRegex(ValueError,'source/test closure'):
            self.validate()

    def test_changed_runner_invalidates(self):
        self.report_change(lambda r:r['runner_sources'][0].update(sha256='0'*64))
        with self.assertRaisesRegex(ValueError,'runner/provenance content'):
            self.validate()

    def test_missing_provenance_runner_invalidates(self):
        self.report_change(lambda r:r['runner_sources'].pop())
        with self.assertRaisesRegex(ValueError,'runner/provenance source closure'):
            self.validate()

    def test_changed_platform_invalidates(self):
        self.platform += 'changed Xcode build'
        with self.assertRaisesRegex(ValueError,'fingerprint changed'):
            self.validate()

    def test_changed_swift_toolchain_invalidates(self):
        self.toolchain += ' different'
        with self.assertRaisesRegex(ValueError,'Swift version'):
            self.validate()

    def test_changed_actual_compiler_bytes_invalidates(self):
        self.compiler_tools[0]['sha256'] = '0'*64
        with self.assertRaisesRegex(ValueError,'compiler fingerprint'):
            self.validate()

    def test_wrong_origin_source_invalidates(self):
        self.origin_sha = '0'*40
        with self.assertRaisesRegex(ValueError,'wrong source'):
            self.validate()

    def test_raw_result_corruption_invalidates(self):
        self.files[self.prefix+'raw-origin/raw-005-tests-foreground.stdout.log'] = b'{}'
        with self.assertRaisesRegex(ValueError,'checksum mismatch'):
            self.validate()

    def test_rehashed_incomplete_raw_result_still_invalidates(self):
        key = self.prefix+'raw-origin/raw-005-tests-foreground.stdout.log'
        result = json.loads(self.files[key])
        result['tests'].pop()
        record = self.raw_change('raw-005-tests-foreground.stdout.log',json.dumps(result).encode())
        key = self.prefix+'raw-origin/commands.jsonl'
        trace = [json.loads(line) for line in self.files[key].decode().splitlines()]
        next(e for e in trace if e['kind']=='completed' and 'tests-foreground' in e['stdout']['path'])['stdout'] = record
        self.raw_change('commands.jsonl',('\n'.join(json.dumps(e) for e in trace)+'\n').encode())
        with self.assertRaisesRegex(ValueError,'53 unique passes'):
            self.validate()

    def test_rehashed_failed_native_command_still_invalidates(self):
        key = self.prefix+'raw-origin/commands.jsonl'
        trace = [json.loads(line) for line in self.files[key].decode().splitlines()]
        next(e for e in trace if e['kind']=='completed' and 'tests-foreground' in e['stdout']['path'])['exit_code'] = 1
        self.raw_change('commands.jsonl',('\n'.join(json.dumps(e) for e in trace)+'\n').encode())
        with self.assertRaisesRegex(ValueError,'command failed'):
            self.validate()

    def test_rehashed_different_executed_binary_still_invalidates(self):
        key = self.prefix+'raw-origin/commands.jsonl'
        trace = [json.loads(line) for line in self.files[key].decode().splitlines()]
        for event in trace:
            if ((event['kind']=='start' and event['label']=='tests-foreground')
                    or (event['kind']=='completed' and 'tests-foreground' in event['stdout']['path'])):
                event['argv'][0] += '-different'
        self.raw_change('commands.jsonl',('\n'.join(json.dumps(e) for e in trace)+'\n').encode())
        with self.assertRaisesRegex(ValueError,'executed test'):
            self.validate()

    def test_rehashed_canonical_dependency_mismatch_still_invalidates(self):
        name = 'contracts-provenance.json'
        proof = json.loads(self.files[self.prefix+'raw-origin/'+name])
        proof['inputs']['dependency_outputs'][0]['sha256'] = '0'*64
        record = self.raw_change(name,(json.dumps(proof,indent=2)+'\n').encode())
        self.report_change(lambda r:r['canonical_provenance']['contracts'].__setitem__('provenance',record))
        with self.assertRaisesRegex(ValueError,'canonical compiler/output lineage'):
            self.validate()

    def test_duplicate_archive_member_invalidates(self):
        with self.assertRaisesRegex(ValueError,'duplicate'):
            self.validate(duplicate=self.prefix+'foreground-results.json')

    def test_missing_raw_trace_invalidates(self):
        del self.files[self.prefix+'raw-origin/commands.jsonl']
        with self.assertRaisesRegex(ValueError,'Missing'):
            self.validate()


    def test_failed_admission_emits_false_and_keeps_actual_execution_required(self):
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary)
            outputs = evidence/'outputs'
            with patch.object(guard,'EVIDENCE',evidence), patch.dict(os.environ,{
                    'HOST_PROOF_RUN_ID':'','FOREGROUND_PROOF_RUN_ID':'45133337462','GITHUB_OUTPUT':str(outputs)}), patch.object(
                    guard,'restore_foreground',side_effect=ValueError('source changed')):
                guard.main()
            self.assertIn('foreground_reused=false',outputs.read_text().splitlines())
            self.assertEqual(json.loads((evidence/'foreground-reuse.json').read_text())['status'],'INVALIDATED')

    def test_default_does_not_request_or_skip_native_foreground(self):
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary)
            outputs = evidence/'outputs'
            with patch.object(guard,'EVIDENCE',evidence), patch.dict(os.environ,{
                    'HOST_PROOF_RUN_ID':'','FOREGROUND_PROOF_RUN_ID':'','GITHUB_OUTPUT':str(outputs)}), patch.object(
                    guard,'restore_foreground',side_effect=AssertionError('Unexpected reuse')) as restore:
                guard.main()
            restore.assert_not_called()
            self.assertIn('foreground_reused=false',outputs.read_text().splitlines())
            self.assertEqual(json.loads((evidence/'foreground-reuse.json').read_text())['status'],'NOT_REQUESTED')


if __name__ == '__main__':
    unittest.main()
