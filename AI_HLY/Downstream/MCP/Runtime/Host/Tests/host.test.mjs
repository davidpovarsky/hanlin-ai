import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Worker } from 'node:worker_threads';
import Arborist from '@npmcli/arborist';
import pacote from 'pacote';
import { inspectManifest, listEntryPoints, resolveEntryPoint } from '../package-compatibility.mjs';
import { checkCancelled, commitInstall, rollbackInstall, verifyIntegrity } from '../package-installer.mjs';

const workerURL = new URL('../server-worker.mjs', import.meta.url);

test('worker stdin and stdout remain isolated for multiple servers', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-mcp-test-'));
  await fs.writeFile(path.join(root, 'package.json'), JSON.stringify({ name: 'fixture', version: '1.0.0', type: 'module' }));
  await fs.writeFile(path.join(root, 'server.mjs'), `
    import { createInterface } from 'node:readline';
    createInterface({ input: process.stdin }).on('line', line => process.stdout.write(line + '\\n'));
  `);
  const create = () => new Worker(workerURL, {
    workerData: { packageRoot: root, entryPoint: path.join(root, 'server.mjs') },
    stdin: true, stdout: true, stderr: true,
  });
  const first = create();
  const second = create();
  const read = worker => new Promise(resolve => worker.stdout.once('data', data => resolve(data.toString('utf8').trim())));
  const firstRead = read(first); const secondRead = read(second);
  first.stdin.write('{"id":1}\n'); second.stdin.write('{"id":2}\n');
  assert.equal(await firstRead, '{"id":1}');
  assert.equal(await secondRead, '{"id":2}');
  await Promise.all([first.terminate(), second.terminate()]);
  await fs.rm(root, { recursive: true, force: true });
});

test('lifecycle scripts and incompatible engines are rejected by preflight', () => {
  const findings = inspectManifest({ engines: { node: '>=20' }, scripts: { postinstall: 'node setup.js' } });
  assert.equal(findings.filter(item => item.severity === 'unsupported').length, 2);
});

test('integrity mismatch fails closed', () => {
  assert.throws(() => verifyIntegrity(Buffer.from('wrong'), 'sha512-deadbeef'));
});

test('install cancellation aborts work', () => {
  const controller = new AbortController();
  controller.abort(new Error('cancelled'));
  assert.throws(() => checkCancelled(controller.signal), /cancelled/);
});

test('multiple package bins are listed and an explicit path preserves its bin name', () => {
  const manifest = { bin: { alpha: './alpha.mjs', beta: './beta.mjs' }, main: './fallback.mjs' };
  assert.deepEqual(listEntryPoints(manifest), ['./alpha.mjs', './beta.mjs', './fallback.mjs']);
  assert.deepEqual(resolveEntryPoint(manifest, './beta.mjs'), { entryPoint: './beta.mjs', binName: 'beta' });
  assert.deepEqual(resolveEntryPoint(manifest, 'alpha'), { entryPoint: './alpha.mjs', binName: 'alpha' });
});

test('replacement rollback restores the prior server and commit removes its backup', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-mcp-transaction-'));
  const operationID = '11111111-1111-4111-8111-111111111111';
  const serverID = '22222222-2222-4222-8222-222222222222';
  const servers = path.join(root, 'servers');
  const staging = path.join(root, 'staging');
  const finalRoot = path.join(servers, serverID);
  const backupRoot = path.join(staging, `backup-${operationID}`);
  await fs.mkdir(finalRoot, { recursive: true });
  await fs.mkdir(backupRoot, { recursive: true });
  await fs.writeFile(path.join(finalRoot, 'version'), 'new');
  await fs.writeFile(path.join(backupRoot, 'version'), 'old');

  await rollbackInstall({ root, operationID, serverID });
  assert.equal(await fs.readFile(path.join(finalRoot, 'version'), 'utf8'), 'old');

  await fs.mkdir(backupRoot, { recursive: true });
  await commitInstall({ root, operationID, serverID });
  await assert.rejects(fs.access(backupRoot), error => error.code === 'ENOENT');
  await fs.rm(root, { recursive: true, force: true });
});

test('host redirects npm state before preview and install modules initialize', async () => {
  const sandbox = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-mcp-home-'));
  const containerRoot = path.join(sandbox, 'container-root');
  const root = path.join(containerRoot, 'Library', 'Application Support', 'HanlinMCP');
  const packageDirectory = path.join(sandbox, 'package-source');
  const fixtureCache = path.join(sandbox, 'fixture-cache');
  const archive = path.join(sandbox, 'fixture.tgz');
  const readyPath = path.join(root, 'ready.json');
  const logPath = path.join(root, 'runtime.log');
  const launchToken = 'test-launch-token';
  let child;

  await fs.mkdir(root, { recursive: true });
  await fs.mkdir(packageDirectory, { recursive: true });
  await fs.writeFile(path.join(packageDirectory, 'package.json'), JSON.stringify({
    name: 'hanlin-mcp-cache-fixture',
    version: '1.0.0',
    type: 'module',
    main: 'server.mjs',
  }));
  await fs.writeFile(path.join(packageDirectory, 'server.mjs'), 'process.stdin.resume();\n');
  await fs.writeFile(archive, await pacote.tarball(`file:${packageDirectory}`, {
    Arborist,
    cache: fixtureCache,
    ignoreScripts: true,
  }));

  try {
    await fs.chmod(containerRoot, 0o500);
    const environment = {
      ...process.env,
      HOME: containerRoot,
      USERPROFILE: containerRoot,
    };
    for (const key of Object.keys(environment)) {
      if (key.toLowerCase().startsWith('npm_config_') || key === 'XDG_CACHE_HOME') delete environment[key];
    }
    child = spawn(process.execPath, [
      fileURLToPath(new URL('../host.mjs', import.meta.url)),
      root,
      readyPath,
      launchToken,
      logPath,
      '0',
    ], { env: environment, stdio: ['ignore', 'pipe', 'pipe'] });

    let stderr = '';
    child.stderr.on('data', chunk => { stderr += chunk.toString('utf8'); });
    const ready = await waitForJSON(readyPath, child, () => stderr);
    const preview = await hostRequest(ready.port, launchToken, '/v1/install/preview', {
      source: { kind: 'file', path: archive },
    });
    assert.equal(preview.packageName, 'hanlin-mcp-cache-fixture');

    const installed = await hostRequest(ready.port, launchToken, '/v1/install', {
      operationID: '11111111-1111-4111-8111-111111111111',
      serverID: '22222222-2222-4222-8222-222222222222',
      source: { kind: 'file', path: archive },
    });
    assert.equal(installed.packageName, 'hanlin-mcp-cache-fixture');

    const expectedCache = path.join(root, 'cache', 'npm');
    await fs.access(expectedCache);
    await assert.rejects(fs.access(path.join(containerRoot, '.npm')), error => error.code === 'ENOENT');
    const diagnostics = await fs.readFile(logPath, 'utf8');
    const configured = diagnostics.split('\n')
      .filter(Boolean)
      .map(line => JSON.parse(line))
      .find(line => line.event === 'runtime_paths_configured');
    assert.equal(configured?.fields?.home, path.join(root, 'runtime', 'home'));
    assert.equal(configured?.fields?.npmCache, expectedCache);
    assert.equal(configured?.fields?.npmPrefix, path.join(root, 'runtime', 'npm-prefix'));
    assert.equal(configured?.fields?.npmTemp, path.join(root, 'staging', 'tmp'));
  } finally {
    if (child && child.exitCode === null) {
      child.kill();
      await once(child, 'exit');
    }
    await fs.chmod(containerRoot, 0o700).catch(() => {});
    await fs.rm(sandbox, { recursive: true, force: true });
  }
});

async function waitForJSON(file, child, stderr) {
  for (let attempt = 0; attempt < 200; attempt += 1) {
    try {
      return JSON.parse(await fs.readFile(file, 'utf8'));
    } catch (error) {
      if (child.exitCode !== null) throw new Error(`Host exited before becoming ready: ${stderr()}`);
      if (error.code !== 'ENOENT' && !(error instanceof SyntaxError)) throw error;
      await new Promise(resolve => setTimeout(resolve, 50));
    }
  }
  throw new Error(`Host did not become ready: ${stderr()}`);
}

async function hostRequest(port, token, route, body) {
  const response = await fetch(`http://127.0.0.1:${port}${route}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  const text = await response.text();
  assert.equal(response.status, 200, text);
  return JSON.parse(text);
}
