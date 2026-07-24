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
    trackUnmanagedFds: false,
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

test('lifecycle scripts require approval while incompatible engines remain rejected', () => {
  const findings = inspectManifest({ engines: { node: '>=20' }, scripts: { postinstall: 'node setup.js' } });
  assert.equal(findings.filter(item => item.severity === 'unsupported').length, 0);
  assert.equal(findings.filter(item => item.severity === 'warning').length, 1);
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
  const servers = path.join(root, 'packages', 'mcp');
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

test('host redirects npm state before preview and install modules initialize', async t => {
  const sandbox = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-mcp-home-'));
  const containerRoot = path.join(sandbox, 'container-root');
  const root = path.join(containerRoot, 'Library', 'Application Support', 'HanlinRuntime', 'v1');
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
  await fs.writeFile(path.join(packageDirectory, 'server.mjs'), `
    import { createInterface } from 'node:readline';
    createInterface({ input: process.stdin }).on('line', line => {
      const request = JSON.parse(line);
      if (request.method === 'initialize') respond(request.id, {
        protocolVersion: request.params.protocolVersion,
        capabilities: { tools: {} },
        serverInfo: { name: 'host-test', version: '1.0.0' },
      });
      if (request.method === 'tools/list') respond(request.id, { tools: [] });
    });
    function respond(id, result) { process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id, result }) + '\\n'); }
  `);
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
    assert.equal(ready.nodeVersion, process.versions.node);
    assert.equal(ready.modulePolicyHooksAvailable, true);
    const health = await fetch(`http://127.0.0.1:${ready.port}/health`, {
      headers: { Authorization: `Bearer ${launchToken}` },
    }).then(response => response.json());
    assert.equal(health.modulePolicyHooksAvailable, true);
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

    const workspace = path.join(root, 'clients', 'tools', 'host-test');
    await fs.mkdir(workspace, { recursive: true });
    const execution = await hostRequest(ready.port, launchToken, '/v1/executions', {
      executionID: '33333333-3333-4333-8333-333333333333',
      source: 'console.log("שלום"); export default { answer: 42 };',
      workspace,
      moduleKind: 'esm',
      timeoutMilliseconds: 5000,
      maximumOutputBytes: 4096,
    });
    assert.equal(execution.stdout, 'שלום\n');
    assert.deepEqual(execution.value, { answer: 42 });

    const compiled = await hostRequest(ready.port, launchToken, '/v1/typescript/compile', {
      source: 'const answer: number = 42; console.log(answer);',
      fileName: 'main.ts',
    });
    assert.equal(compiled.succeeded, true);
    assert.match(compiled.javaScript, /const answer = 42/);

    await fs.writeFile(path.join(workspace, 'tsconfig.json'), JSON.stringify({
      compilerOptions: { target: 'ES2022', module: 'ESNext', rootDir: 'src', outDir: 'dist', strict: true },
      include: ['src/**/*.ts'],
    }));
    await fs.mkdir(path.join(workspace, 'src'), { recursive: true });
    await fs.writeFile(path.join(workspace, 'src', 'setup.ts'), 'export const answer: number = 42;\n');
    const project = await hostRequest(ready.port, launchToken, '/v1/typescript/project', {
      workspace,
      arguments: ['--project', 'tsconfig.json'],
    });
    assert.equal(project.succeeded, true, JSON.stringify(project.diagnostics));
    assert.ok(project.emittedFiles.includes(path.join('dist', 'setup.js')));

    const timedOut = await hostRequest(ready.port, launchToken, '/v1/executions', {
      executionID: '44444444-4444-4444-8444-444444444444',
      source: 'setInterval(() => {}, 1000); await new Promise(() => {});',
      workspace,
      moduleKind: 'esm',
      timeoutMilliseconds: 1000,
      maximumOutputBytes: 4096,
    });
    assert.equal(timedOut.didTimeOut, true);

    const traversal = await hostRequestStatus(ready.port, launchToken, '/v1/executions', {
      executionID: '55555555-5555-4555-8555-555555555555', source: 'export default 1;',
      workspace: path.join(root, '..'), moduleKind: 'esm', timeoutMilliseconds: 1000, maximumOutputBytes: 4096,
    });
    assert.equal(traversal.status, 400);

    const linkedWorkspace = path.join(root, 'clients', 'tools', 'linked-workspace');
    try {
      await fs.symlink(workspace, linkedWorkspace, 'dir');
      const symlinkResult = await hostRequestStatus(ready.port, launchToken, '/v1/executions', {
        executionID: '66666666-6666-4666-8666-666666666666', source: 'export default 1;',
        workspace: linkedWorkspace, moduleKind: 'esm', timeoutMilliseconds: 1000, maximumOutputBytes: 4096,
      });
      assert.equal(symlinkResult.status, 400);
    } catch (error) {
      if (process.platform !== 'win32' || error.code !== 'EPERM') throw error;
      t.diagnostic('Windows Developer Mode is unavailable; symlink rejection remains enabled on the macOS CI run.');
    }

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
  const response = await hostRequestStatus(port, token, route, body);
  assert.equal(response.status, 200, response.text);
  return JSON.parse(response.text);
}

async function hostRequestStatus(port, token, route, body) {
  const response = await fetch(`http://127.0.0.1:${port}${route}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  const text = await response.text();
  return { status: response.status, text };
}
