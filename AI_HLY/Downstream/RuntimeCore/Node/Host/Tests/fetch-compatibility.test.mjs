import test from 'node:test';
import assert from 'node:assert/strict';
import { promisify } from 'node:util';
import { execFile } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { fetchImplementation, webAssemblyAvailable } from '../fetch-compatibility.mjs';

test('Fetch transport follows actual WebAssembly availability', () => {
  assert.equal(webAssemblyAvailable, typeof WebAssembly !== 'undefined');
  assert.equal(fetchImplementation, webAssemblyAvailable ? 'node-undici' : 'node-fetch@3.3.2+native-web-api');
});

test('real JITless Node supports Fetch request, streaming, clone, redirects, gzip, multipart and abort', { timeout: 20000 }, async () => {
  const {stdout} = await promisify(execFile)(process.execPath, ['--jitless', fileURLToPath(new URL('./Fixtures/fetch-compatibility-probe.mjs', import.meta.url))], { timeout: 15000 });
  const result = JSON.parse(stdout);
  assert.equal(result.passed, true);
  assert.equal(result.webAssemblyAvailable, false);
  assert.equal(result.contracts.length, 11);
});
