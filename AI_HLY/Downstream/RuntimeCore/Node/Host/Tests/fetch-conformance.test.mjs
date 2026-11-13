import test from 'node:test';
import assert from 'node:assert/strict';
import {promisify} from 'node:util';
import {execFile} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

test('native Fetch reference proves TLS, SRI and actual controlled Proxy routing', {timeout:30000}, async () => {
  const fixtureRoot = process.env.HANLIN_RUNTIME_TEST_FIXTURES
    ?? fileURLToPath(new URL('../../../../../../AI_HLYTests/Fixtures/RuntimeNetworkFixtures.bundle',import.meta.url));
  const hostPackage = fileURLToPath(new URL('../package.json',import.meta.url));
  const code = `import {createRequire} from 'node:module';import {pathToFileURL} from 'node:url';import {readFileSync} from 'node:fs';
    const {runFetchConformance}=await import(pathToFileURL(${JSON.stringify(path.join(fixtureRoot,'probe.mjs'))}).href);
    const {Agent,ProxyAgent}=createRequire(${JSON.stringify(hostPackage)})('undici');
    const report=await runFetchConformance({Agent,ProxyAgent,tlsFixture:JSON.parse(readFileSync(${JSON.stringify(path.join(fixtureRoot,'tls-fixture.json'))},'utf8'))});
    console.log(JSON.stringify(report));`;
  // Stock desktop WASM reference only. JITless iOS requires its separate SDK test.
  const {stdout} = await promisify(execFile)(process.execPath,['--input-type=module','-e',code],{timeout:25000});
  const report = JSON.parse(stdout);
  assert.equal(report.passed,true);
  assert.equal(report.wasm,true);
  assert.equal(report.contracts.length,12);
  assert.equal(report.tunnels.length,2);
});
