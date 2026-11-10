import test from 'node:test';
import { randomUUID } from 'node:crypto';
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
    if(process.env.NODE_OPTIONS!=='--not-a-bootstrap-flag' || process.env.HOME!=='/user-home') throw new Error('MCP user environment not applied after bootstrap');
    createInterface({ input: process.stdin }).on('line', line => process.stdout.write(line + '\\n'));
  `);
  const create = () => new Worker(workerURL, {
    workerData: { packageRoot: root, entryPoint: path.join(root, 'server.mjs'), environment:{NODE_OPTIONS:'--not-a-bootstrap-flag',HOME:'/user-home'} },
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

test('lifecycle scripts retain native execution metadata while incompatible engines remain rejected', () => {
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

test('unknown legacy transactions preserve both the installed package and its backup', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-mcp-transaction-'));
  t.after(() => fs.rm(root, {recursive:true,force:true}));
  const operationID = '11111111-1111-4111-8111-111111111111';
  const serverID = '22222222-2222-4222-8222-222222222222';
  const finalRoot = path.join(root, 'packages', 'mcp', serverID);
  const backupRoot = path.join(root, 'staging', `backup-${operationID}`);
  await fs.mkdir(finalRoot, {recursive:true});
  await fs.mkdir(backupRoot, {recursive:true});
  await fs.writeFile(path.join(finalRoot, 'version'), 'new');
  await fs.writeFile(path.join(backupRoot, 'version'), 'old');
  await assert.rejects(rollbackInstall({root,operationID,serverID}), {code:'ENOENT'});
  await assert.rejects(commitInstall({root,operationID,serverID}), {code:'ENOENT'});
  assert.equal(await fs.readFile(path.join(finalRoot,'version'),'utf8'),'new');
  assert.equal(await fs.readFile(path.join(backupRoot,'version'),'utf8'),'old');
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
    const startedServer = await hostRequest(ready.port, launchToken, `/v1/servers/${installed.id}/start`, {
      serverID: installed.id, packageRoot: installed.packageRoot, entryPoint: installed.entryPoint,
      arguments: [], environment: {},
    });
    assert.equal(startedServer.state, 'running');
    await hostRequest(ready.port, launchToken, `/v1/servers/${installed.id}/stop`, {});

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

    // Real authenticated HTTP interruption, not only an ExecutionJobs unit call.
    const interruptedID = randomUUID();
    await hostRequest(ready.port, launchToken, '/v1/executions', {
      executionID: interruptedID, source: "console.log('retained HTTP partial'); await new Promise(() => setInterval(() => {}, 1000));",
      workspace, moduleKind: 'esm', detached: true, maximumOutputBytes: 4096,
    });
    const readJob = async () => {
      const response = await fetch(`http://127.0.0.1:${ready.port}/v1/executions/${interruptedID}`, {headers:{Authorization:`Bearer ${launchToken}`}});
      assert.equal(response.status,200); return response.json();
    };
    const interruptionDeadline = performance.now()+15000;
    let interrupted;
    do {
      interrupted = await readJob();
      assert.ok(performance.now()<interruptionDeadline,'Actual HTTP job never wrote partial output');
      if (!interrupted.stdoutBytes) await new Promise(resolve=>setTimeout(resolve,10));
    } while (!interrupted.stdoutBytes);
    const deniedInterrupt = await fetch(`http://127.0.0.1:${ready.port}/v1/executions/${interruptedID}/interrupt`, {
      method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({reason:'unauthenticated'}),
    });
    assert.equal(deniedInterrupt.status,401);
    const interruptionReason = 'Background continuation ended by the system or its Cancel control.';
    await hostRequest(ready.port, launchToken, `/v1/executions/${interruptedID}/interrupt`, {reason:interruptionReason});
    do {
      interrupted = await readJob();
      assert.ok(performance.now()<interruptionDeadline,'Actual HTTP interruption did not settle');
      if (!interrupted.completedAt) await new Promise(resolve=>setTimeout(resolve,10));
    } while (!interrupted.completedAt);
    assert.equal(interrupted.state,'interrupted');
    assert.equal(interrupted.interruptionReason,interruptionReason);
    assert.match(await fs.readFile(interrupted.result.outputFiles.stdout.path,'utf8'),/retained HTTP partial/);

    const cliEntry = path.join(workspace, 'actual cli.cjs');
    const cliInput = path.join(workspace, 'cli stdin.txt');
    await fs.writeFile(cliInput, 'CLI_INPUT_שלום');
    await fs.writeFile(cliEntry, `
      if(require.main!==module) throw new Error('Not actual main');
      if(process.argv[2]!=='arg with spaces') throw new Error('Wrong argv');
      process.stdin.pipe(process.stdout);
      process.stdin.on('end',()=>setTimeout(()=>console.error(process.env.CLI_VALUE),20));
    `);
    const cli = await hostRequest(ready.port, launchToken, '/v1/executions', {
      executionID: randomUUID(), executionMode:'cli', entryPoint: cliEntry, standardInputPath: cliInput,
      workspace, moduleKind: 'commonjs', arguments: ['arg with spaces'], environment: {CLI_VALUE:'CLI_ENV'},
    });
    assert.equal(cli.exitCode, 0, JSON.stringify(cli));
    assert.equal(cli.stdout, 'CLI_INPUT_שלום');
    assert.match(cli.stderr, /CLI_ENV/);
    const parentSource = `import {executePortableShell} from ${JSON.stringify(new URL('../portable-shell.mjs',import.meta.url).href)};
      const status=await executePortableShell("echo CLI_PARENT_INPUT | node 'actual cli.cjs' 'arg with spaces'",[],{cwd:process.cwd(),environment:process.env});
      process.exitCode=status; export default status;`;
    const parent = await hostRequest(ready.port,launchToken,'/v1/executions',{
      executionID:randomUUID(),source:parentSource,moduleKind:'esm',workspace,detached:true,environment:{CLI_VALUE:'CLI_ENV'},
    });
    const read = async route => {
      const response=await fetch(`http://127.0.0.1:${ready.port}${route}`,{headers:{Authorization:`Bearer ${launchToken}`}});
      assert.equal(response.status,200);return response.json();
    };
    const deadline=performance.now()+15000;
    let pending=[];
    while(!(pending=await read('/v1/commands')).length){assert.ok(performance.now()<deadline);await new Promise(resolve=>setTimeout(resolve,10));}
    assert.equal(pending.length,1);assert.equal(pending[0].parentExecutionID,parent.executionID);
    const command=pending[0];
    const actualChild=await hostRequest(ready.port,launchToken,'/v1/executions',{
      executionID:randomUUID(),executionMode:'cli',entryPoint:path.resolve(command.cwd,command.arguments[0]),
      arguments:command.arguments.slice(1),workspace:command.cwd,moduleKind:'commonjs',environment:command.environment,standardInputPath:command.standardInputPath,
    });
    await fs.writeFile(path.join(path.dirname(command.standardInputPath),'response.json'),JSON.stringify({
      exitCode:actualChild.exitCode,stdoutPath:actualChild.outputFiles.stdout.path,stderrPath:actualChild.outputFiles.stderr.path,
    }));
    let completed;
    while((completed=await read('/v1/executions/'+parent.executionID)).state==='running'){
      assert.ok(performance.now()<deadline);await new Promise(resolve=>setTimeout(resolve,10));
    }
    assert.equal(completed.state,'completed',JSON.stringify(completed));
    assert.equal(completed.result.stdout,'CLI_PARENT_INPUT\n');assert.match(completed.result.stderr,/CLI_ENV/);
    assert.deepEqual(await read('/v1/commands'),[]);
    const invalidCLI = await hostRequestStatus(ready.port, launchToken, '/v1/executions', {
      executionID: randomUUID(), executionMode:'cli', entryPoint: workspace, workspace, moduleKind:'esm',
    });
    assert.equal(invalidCLI.status, 400);


    for (const tracing of [true, false]) {
      const marker = `warning-scope-${tracing}-${randomUUID()}`;
      const warningResult = await hostRequest(ready.port, launchToken, '/v1/executions', {
        executionID: randomUUID(),
        source: `process.emitWarning(${JSON.stringify(marker)}); await new Promise(resolve => setImmediate(resolve)); export default 42;`,
        workspace, moduleKind: 'esm', maximumOutputBytes: 4096,
        environment: tracing ? { HANLIN_NODE_TRACE_WARNINGS: '1' } : {},
      });
      assert.equal(warningResult.value, 42);
      for (let attempt = 0; tracing && attempt < 20 && !stderr.includes(marker); attempt += 1) {
        await new Promise(resolve => setTimeout(resolve, 50));
      }
      assert.ok((stderr + warningResult.stderr).includes(marker), JSON.stringify(warningResult) + stderr);
      const traced = (stderr + warningResult.stderr).split('\n').some(line => line.includes('[HANLIN_NODE_WARNING thread=') && line.includes(marker));
      assert.equal(traced, tracing, stderr);
    }

    const compiled = await hostRequest(ready.port, launchToken, '/v1/typescript/compile', {
      source: 'const answer: number = 42; console.log(answer);',
      fileName: 'main.ts',
    });
    assert.equal(compiled.succeeded, true, JSON.stringify(compiled.diagnostics));
    assert.match(compiled.javaScript, /const answer = 42/);

    const nodeTypes = await hostRequest(ready.port, launchToken, '/v1/typescript/compile', {
      source: "import fs from 'node:fs'; import path from 'node:path'; const argv: string[] = process.argv; export default fs.existsSync(path.resolve(argv[0]));",
      fileName: 'node-types.ts',
    });
    assert.equal(nodeTypes.succeeded, true, JSON.stringify(nodeTypes.diagnostics));
    assert.match(nodeTypes.javaScript, /node:fs/);
    const invalidNodeType = await hostRequest(ready.port, launchToken, '/v1/typescript/compile', {
      source: 'const wrong: number = process.cwd();', fileName: 'invalid-node-type.ts',
    });
    assert.equal(invalidNodeType.succeeded, false);
    assert.ok(invalidNodeType.diagnostics.some(item => item.code === 2322));

    const semanticFailure = await hostRequest(ready.port, launchToken, '/v1/typescript/compile', {
      source: "const answer: number = 'wrong';",
      fileName: 'semantic-error.ts',
    });
    assert.equal(semanticFailure.succeeded, false);
    assert.ok(semanticFailure.diagnostics.some(item => item.code === 2322));

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
    assert.equal(project.compilerVersion, '6.0.3');
    assert.equal(project.compilerIntegrity, 'sha512-y2TvuxSZPDyQakkFRPZHKFm+KKVqIisdg9/CZwm9ftvKXLP8NRWj38/ODjNbr43SsoXqNuAisEf1GdCxqWcdBw==');
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

    const externalWorkspace = path.join(sandbox, 'external-workspace');
    await fs.mkdir(externalWorkspace, { recursive: true });
    const externalResult = await hostRequestStatus(ready.port, launchToken, '/v1/executions', {
      executionID: '55555555-5555-4555-8555-555555555555', source: 'export default 1;',
      workspace: externalWorkspace, moduleKind: 'esm', timeoutMilliseconds: 1000, maximumOutputBytes: 4096,
    });
    assert.equal(externalResult.status, 200);

    const nonexistentResult = await hostRequestStatus(ready.port, launchToken, '/v1/executions', {
      executionID: '77777777-7777-4777-8777-777777777777', source: 'export default 1;',
      workspace: path.join(sandbox, 'does-not-exist'), moduleKind: 'esm', timeoutMilliseconds: 1000, maximumOutputBytes: 4096,
    });
    assert.equal(nonexistentResult.status, 400);

    const filePath = path.join(sandbox, 'some-file.txt');
    await fs.writeFile(filePath, 'not a dir');
    const fileResult = await hostRequestStatus(ready.port, launchToken, '/v1/executions', {
      executionID: '88888888-8888-4888-8888-888888888888', source: 'export default 1;',
      workspace: filePath, moduleKind: 'esm', timeoutMilliseconds: 1000, maximumOutputBytes: 4096,
    });
    assert.equal(fileResult.status, 400);

    const linkedWorkspace = path.join(root, 'clients', 'tools', 'linked-workspace');
    try {
      await fs.symlink(workspace, linkedWorkspace, 'dir');
      const symlinkResult = await hostRequestStatus(ready.port, launchToken, '/v1/executions', {
        executionID: '66666666-6666-4666-8666-666666666666', source: 'export default 1;',
        workspace: linkedWorkspace, moduleKind: 'esm', timeoutMilliseconds: 1000, maximumOutputBytes: 4096,
      });
      assert.equal(symlinkResult.status, 200);
    } catch (error) {
      if (process.platform !== 'win32' || error.code !== 'EPERM') throw error;
      t.diagnostic('Windows Developer Mode is unavailable; symlink test skipped on unprivileged Windows.');
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
