import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const serverID = '22222222-2222-4222-8222-222222222222';
const hostEntryPoint = fileURLToPath(
  new URL(
    '../../../../AI_HLY/Downstream/RuntimeCore/Node/Host/host.mjs',
    import.meta.url,
  ),
);

test('HTTP host serializes MCP lifecycle and survives stress', { timeout: 240_000 }, async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-host-lifecycle-'));
  const packageRoot = path.join(root, 'packages', 'mcp', serverID, 'package');
  const entryPoint = path.join(packageRoot, 'server.mjs');
  const readyPath = path.join(root, 'ready.json');
  const logPath = path.join(root, 'host.log');
  const token = 'lifecycle-test-token';
  let child;
  try {
    await fs.mkdir(packageRoot, { recursive: true });
    await fs.writeFile(path.join(packageRoot, 'package.json'), JSON.stringify({
      name: 'lifecycle-fixture',
      version: '1.0.0',
      type: 'module',
      main: 'server.mjs',
    }));
    await fs.writeFile(entryPoint, `
      import { createInterface } from 'node:readline';
      createInterface({ input: process.stdin }).on('line', line => {
        const request = JSON.parse(line);
        if (request.method === 'initialize') respond(request.id, {
          protocolVersion: request.params.protocolVersion,
          capabilities: { tools: {} },
          serverInfo: { name: 'lifecycle-fixture', version: '1.0.0' },
        });
        if (request.method === 'tools/list') respond(request.id, { tools: [] });
      });
      function respond(id, result) {
        process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id, result }) + '\\n');
      }
    `);
    child = spawn(process.execPath, [
      hostEntryPoint,
      root,
      readyPath,
      token,
      logPath,
      '0',
    ], { stdio: ['ignore', 'pipe', 'pipe'] });
    let stderr = '';
    child.stderr.on('data', chunk => { stderr += chunk.toString('utf8'); });
    const ready = await waitForJSON(readyPath, child, () => stderr);
    const configuration = {
      serverID,
      packageRoot,
      entryPoint,
      arguments: [],
      environment: {},
    };

    const duplicateStarts = await Promise.all(Array.from(
      { length: 8 },
      () => post(ready.port, token, `/v1/servers/${serverID}/start`, configuration),
    ));
    assert.equal(new Set(duplicateStarts.map(value => value.generation)).size, 1);
    assert.ok(duplicateStarts.every(value => value.state === 'running'));

    const eventResponse = await fetch(
      `http://127.0.0.1:${ready.port}/v1/servers/${serverID}/events`,
      { headers: { Authorization: `Bearer ${token}` } },
    );
    assert.equal(eventResponse.status, 200);
    const eventReader = eventResponse.body.getReader();
    await eventReader.read();

    const duplicateStops = await Promise.all(Array.from(
      { length: 8 },
      () => post(ready.port, token, `/v1/servers/${serverID}/stop`, {}),
    ));
    assert.ok(duplicateStops.every(value => value.state === 'stopped'));
    const closedEvent = await eventReader.read();
    if (!closedEvent.done) {
      let eventEnd = closedEvent;
      while (!eventEnd.done) eventEnd = await eventReader.read();
    }

    const firstRestartBase = await post(
      ready.port,
      token,
      `/v1/servers/${serverID}/start`,
      configuration,
    );
    const duplicateRestarts = await Promise.all(Array.from(
      { length: 8 },
      () => post(ready.port, token, `/v1/servers/${serverID}/restart`, configuration),
    ));
    assert.equal(new Set(duplicateRestarts.map(value => value.generation)).size, 1);
    assert.ok(duplicateRestarts[0].generation > firstRestartBase.generation);
    await post(ready.port, token, `/v1/servers/${serverID}/stop`, {});

    for (let iteration = 0; iteration < 20; iteration += 1) {
      await post(ready.port, token, `/v1/servers/${serverID}/start`, configuration);
      await post(ready.port, token, `/v1/servers/${serverID}/stop`, {});
    }
    for (let iteration = 0; iteration < 20; iteration += 1) {
      await post(ready.port, token, `/v1/servers/${serverID}/start`, configuration);
      const restarted = await post(
        ready.port,
        token,
        `/v1/servers/${serverID}/restart`,
        configuration,
      );
      await new Promise(resolve => setTimeout(resolve, 10));
      const afterOldExit = await get(ready.port, token, '/v1/runtime');
      assert.equal(
        afterOldExit.workers.find(worker => worker.id === serverID)?.generation,
        restarted.generation,
      );
      await post(ready.port, token, `/v1/servers/${serverID}/stop`, {});
    }

    const startingID = '44444444-4444-4444-8444-444444444444';
    const startingRoot = path.join(root, 'packages', 'mcp', startingID, 'package');
    const startingEntry = path.join(startingRoot, 'server.mjs');
    await fs.mkdir(startingRoot, { recursive: true });
    await fs.writeFile(path.join(startingRoot, 'package.json'), JSON.stringify({
      name: 'starting-fixture',
      version: '1.0.0',
      type: 'module',
      main: 'server.mjs',
    }));
    await fs.writeFile(startingEntry, `
      await new Promise(resolve => setTimeout(resolve, 750));
      process.stdin.resume();
    `);
    const cancelledStart = postRaw(
      ready.port,
      token,
      `/v1/servers/${startingID}/start`,
      {
        serverID: startingID,
        packageRoot: startingRoot,
        entryPoint: startingEntry,
        arguments: [],
        environment: {},
      },
    );
    await new Promise(resolve => setTimeout(resolve, 50));
    const backgroundLikeStop = await post(
      ready.port,
      token,
      `/v1/servers/${startingID}/stop`,
      {},
    );
    assert.equal(backgroundLikeStop.state, 'stopped');
    assert.equal((await cancelledStart).status, 400);

    const slowStopID = '55555555-5555-4555-8555-555555555555';
    const slowStopRoot = path.join(root, 'packages', 'mcp', slowStopID, 'package');
    const slowStopEntry = path.join(slowStopRoot, 'server.mjs');
    await fs.mkdir(slowStopRoot, { recursive: true });
    await fs.writeFile(path.join(slowStopRoot, 'package.json'), JSON.stringify({
      name: 'slow-stop-fixture',
      version: '1.0.0',
      type: 'module',
      main: 'server.mjs',
    }));
    await fs.writeFile(slowStopEntry, `
      process.stdin.resume();
      process.stdin.once('end', () => setTimeout(() => {}, 500));
    `);
    const slowConfiguration = {
      serverID: slowStopID,
      packageRoot: slowStopRoot,
      entryPoint: slowStopEntry,
      arguments: [],
      environment: {},
    };
    const slowFirst = await post(
      ready.port,
      token,
      `/v1/servers/${slowStopID}/start`,
      slowConfiguration,
    );
    const slowStop = post(
      ready.port,
      token,
      `/v1/servers/${slowStopID}/stop`,
      {},
    );
    await new Promise(resolve => setTimeout(resolve, 25));
    const blockedStartBegan = Date.now();
    const slowSecond = await post(
      ready.port,
      token,
      `/v1/servers/${slowStopID}/start`,
      slowConfiguration,
    );
    assert.ok(Date.now() - blockedStartBegan >= 400);
    assert.equal(slowSecond.generation, slowFirst.generation + 1);
    await slowStop;
    await post(ready.port, token, `/v1/servers/${slowStopID}/stop`, {});

    const timeoutID = '66666666-6666-4666-8666-666666666666';
    const timeoutRoot = path.join(root, 'packages', 'mcp', timeoutID, 'package');
    const timeoutEntry = path.join(timeoutRoot, 'server.mjs');
    await fs.mkdir(timeoutRoot, { recursive: true });
    await fs.writeFile(path.join(timeoutRoot, 'package.json'), JSON.stringify({
      name: 'startup-timeout-fixture',
      version: '1.0.0',
      type: 'module',
      main: 'server.mjs',
    }));
    await fs.writeFile(
      timeoutEntry,
      'await new Promise(() => setInterval(() => {}, 1000));\n',
    );
    const timeoutStarted = Date.now();
    const timedOutStart = await postRaw(
      ready.port,
      token,
      `/v1/servers/${timeoutID}/start`,
      {
        serverID: timeoutID,
        packageRoot: timeoutRoot,
        entryPoint: timeoutEntry,
        arguments: [],
        environment: {},
      },
    );
    assert.equal(timedOutStart.status, 400);
    assert.match(timedOutStart.text, /startup timed out/i);
    assert.ok(Date.now() - timeoutStarted >= 17_900);

    const stubbornID = '33333333-3333-4333-8333-333333333333';
    const stubbornRoot = path.join(root, 'packages', 'mcp', stubbornID, 'package');
    const stubbornEntry = path.join(stubbornRoot, 'server.mjs');
    await fs.mkdir(stubbornRoot, { recursive: true });
    await fs.writeFile(path.join(stubbornRoot, 'package.json'), JSON.stringify({
      name: 'stubborn-fixture',
      version: '1.0.0',
      type: 'module',
      main: 'server.mjs',
    }));
    await fs.writeFile(stubbornEntry, 'setInterval(() => {}, 1000);\n');
    await post(ready.port, token, `/v1/servers/${stubbornID}/start`, {
      serverID: stubbornID,
      packageRoot: stubbornRoot,
      entryPoint: stubbornEntry,
      arguments: [],
      environment: {},
    });
    const forcedStarted = Date.now();
    await post(ready.port, token, `/v1/servers/${stubbornID}/stop`, {});
    assert.ok(Date.now() - forcedStarted >= 2_900);

    const runtime = await get(ready.port, token, '/v1/runtime');
    assert.equal(runtime.workers.length, 0);
    assert.equal(runtime.lifecycle.activeWorkerCount, 0);
    assert.equal(runtime.lifecycle.maximumSimultaneousWorkers, 1);
    assert.equal(
      runtime.lifecycle.byServer[serverID].maximumSimultaneousWorkers,
      1,
    );
    assert.equal(runtime.lifecycle.forcedTerminationCount, 2);
    assert.equal(
      runtime.lifecycle.finalizeCount,
      runtime.lifecycle.workerCreationCount,
      JSON.stringify(runtime.lifecycle),
    );
    assert.equal(child.exitCode, null);
    const diagnostics = await fs.readFile(logPath, 'utf8');
    assert.doesNotMatch(diagnostics, /unhandled_rejection|double.final/i);
  } finally {
    if (child && child.exitCode === null) {
      child.kill();
      await once(child, 'exit');
    }
    await fs.rm(root, { recursive: true, force: true });
  }
});

async function post(port, token, route, body) {
  const result = await postRaw(port, token, route, body);
  assert.equal(result.status, 200, result.text);
  return JSON.parse(result.text);
}

async function postRaw(port, token, route, body) {
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

async function get(port, token, route) {
  const response = await fetch(`http://127.0.0.1:${port}${route}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  const text = await response.text();
  assert.equal(response.status, 200, text);
  return JSON.parse(text);
}

async function waitForJSON(file, child, stderr) {
  for (let attempt = 0; attempt < 200; attempt += 1) {
    try {
      return JSON.parse(await fs.readFile(file, 'utf8'));
    } catch (error) {
      if (child.exitCode !== null) {
        throw new Error(`Host exited before becoming ready: ${stderr()}`);
      }
      if (error.code !== 'ENOENT' && !(error instanceof SyntaxError)) throw error;
      await new Promise(resolve => setTimeout(resolve, 50));
    }
  }
  throw new Error(`Host did not become ready: ${stderr()}`);
}
