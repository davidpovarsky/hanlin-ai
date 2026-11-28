import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { execFileSync } from 'node:child_process';

const repoRoot = resolve(import.meta.dirname, '..', '..', '..');

test('Packaged probes contain valid Metro bundles, manifests, and capability declarations', async () => {
  const probesDir = resolve(repoRoot, 'Fixtures', 'ExpoNativeAPIProbe');
  const requiredZips = [
    'ExpoNativeAPIProbeA.hanlinExpo',
    'ExpoNativeAPIProbeB.hanlinExpo',
    'ExpoNativeAPIProbeMissingGrant.hanlinExpo',
    'ExpoNativeAPIProbeIncompatible.hanlinExpo',
    'ExpoNativeAPIMalformed.hanlinExpo',
  ];

  for (const zip of requiredZips) {
    const fullPath = resolve(probesDir, zip);
    assert.ok(existsSync(fullPath), `Probe package ${zip} must exist`);
  }

  // Inspect contents directly from ExpoNativeAPIProbeA.hanlinExpo using Python zipfile
  const pythonBin = process.platform === 'win32' ? 'python' : 'python3';
  const zipAPath = resolve(probesDir, 'ExpoNativeAPIProbeA.hanlinExpo');
  const inspectCode = `
import zipfile, sys, json
with zipfile.ZipFile(sys.argv[1], 'r') as zf:
    names = zf.namelist()
    assert 'bundle.js' in names, 'bundle.js missing in zip'
    assert 'package.json' in names, 'package.json missing in zip'
    assert 'script.json' in names, 'script.json missing in zip'
    script_data = json.loads(zf.read('script.json'))
    assert 'ios-native-api' in script_data.get('capabilities', []), 'ios-native-api missing in Probe A capabilities'
    bundle_text = zf.read('bundle.js').decode('utf-8')
    assert 'NativeScript' in bundle_text, 'Bundle must reference NativeScript'
    assert '_worklet' in bundle_text, 'Bundle must contain transpiled worklets'
print('PROBE_A_VALIDATED')
`;
  const result = execFileSync(pythonBin, ['-c', inspectCode, zipAPath], { encoding: 'utf8' });
  assert.ok(result.includes('PROBE_A_VALIDATED'), 'Probe A bundle and manifest content must be valid');

  // Inspect MissingGrant probe
  const zipMissingPath = resolve(probesDir, 'ExpoNativeAPIProbeMissingGrant.hanlinExpo');
  const inspectMissingCode = `
import zipfile, sys, json
with zipfile.ZipFile(sys.argv[1], 'r') as zf:
    script_data = json.loads(zf.read('script.json'))
    caps = script_data.get('capabilities', [])
    assert 'ios-native-api' not in caps, 'MissingGrant probe must NOT declare ios-native-api'
print('PROBE_MISSING_GRANT_VALIDATED')
`;
  const resultMissing = execFileSync(pythonBin, ['-c', inspectMissingCode, zipMissingPath], { encoding: 'utf8' });
  assert.ok(resultMissing.includes('PROBE_MISSING_GRANT_VALIDATED'), 'Missing grant probe must omit ios-native-api');
});
