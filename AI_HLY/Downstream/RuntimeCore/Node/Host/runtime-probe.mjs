import { promises as fs } from 'node:fs';
import path from 'node:path';
import { Worker } from 'node:worker_threads';

const workerURL = new URL('./server-worker.mjs', import.meta.url);
const protocolVersion = '2025-06-18';

export async function runMCPRuntimeProbe(options) {
  let totalDurationMilliseconds = 0;
  let result;
  for (let attempt = 1; attempt <= 5; attempt += 1) {
    result = await runMCPRuntimeProbeAttempt(options);
    totalDurationMilliseconds += result.durationMilliseconds;
    if (!shouldRetryInternalLoaderFailure(result) || attempt === 5) {
      return {
        ...result,
        durationMilliseconds: totalDurationMilliseconds,
        internalLoaderRetryCount: attempt - 1,
      };
    }
  }
  return result;
}

async function runMCPRuntimeProbeAttempt(options) {
  const started = Date.now();
  const packageRoot = path.resolve(options.packageRoot);
  const entryPoint = path.resolve(options.entryPoint);
  const timeoutMilliseconds = Math.min(Math.max(Number(options.timeoutMilliseconds) || 20_000, 1_000), 120_000);
  const maximumOutputBytes = Math.min(Math.max(Number(options.maximumOutputBytes) || 1_048_576, 4_096), 8 * 1024 * 1024);
  const workspace = path.resolve(options.workspace ?? path.join(path.dirname(packageRoot), 'probe-workspace'));
  await fs.mkdir(workspace, { recursive: true });

  const moduleEdges = [];
  const blockedAccesses = [];
  const dynamicModules = new Set();
  let outputBytes = 0;
  let stderr = '';
  let stdoutBuffer = Buffer.alloc(0);
  let worker;
  let cleanStop = false;

  try {
    worker = new Worker(workerURL, {
      workerData: {
        packageRoot,
        entryPoint,
        moduleKind: options.moduleKind,
        runtimeProbe: true,
      },
      argv: validatedArguments(options.arguments),
      env: sanitizedEnvironment(workspace, options.environment),
      stdin: true,
      stdout: true,
      stderr: true,
    });

    const events = createWorkerEvents(worker, { moduleEdges, blockedAccesses, dynamicModules });
    const responses = createResponseQueue();
    worker.stdout.on('data', chunk => {
      outputBytes += chunk.length;
      if (outputBytes > maximumOutputBytes) {
        responses.fail(new Error('Runtime probe output exceeded its limit.'));
        return;
      }
      stdoutBuffer = Buffer.concat([stdoutBuffer, chunk]);
      let newline;
      while ((newline = stdoutBuffer.indexOf(0x0a)) >= 0) {
        const line = stdoutBuffer.subarray(0, newline).toString('utf8').trim();
        stdoutBuffer = stdoutBuffer.subarray(newline + 1);
        if (!line) continue;
        try { responses.push(JSON.parse(line)); } catch { /* diagnostic stdout is not MCP traffic */ }
      }
    });
    worker.stderr.on('data', chunk => {
      outputBytes += chunk.length;
      if (Buffer.byteLength(stderr) < maximumOutputBytes) stderr += chunk.toString('utf8');
      if (outputBytes > maximumOutputBytes) responses.fail(new Error('Runtime probe output exceeded its limit.'));
    });
    worker.once('error', error => { events.fail(error); responses.fail(error); });
    worker.once('exit', code => {
      if (code !== 0) {
        const error = new Error(`Server Worker exited during the runtime probe with code ${code}.`);
        events.fail(error); responses.fail(error);
      }
    });

    await withTimeout(events.loaded, timeoutMilliseconds, 'Server Worker startup timed out.');
    writeMessage(worker, {
      jsonrpc: '2.0', id: 1, method: 'initialize',
      params: {
        protocolVersion,
        capabilities: {},
        clientInfo: { name: 'Hanlin Runtime Probe', version: '1' },
      },
    });
    const initialized = await withTimeout(responses.waitFor(1), timeoutMilliseconds, 'MCP initialize timed out.');
    if (initialized.error) throw new Error(`MCP initialize failed: ${initialized.error.message ?? JSON.stringify(initialized.error)}`);
    writeMessage(worker, { jsonrpc: '2.0', method: 'notifications/initialized', params: {} });
    writeMessage(worker, { jsonrpc: '2.0', id: 2, method: 'tools/list', params: {} });
    const tools = await withTimeout(responses.waitFor(2), timeoutMilliseconds, 'MCP tools/list timed out.');
    if (tools.error) throw new Error(`MCP tools/list failed: ${tools.error.message ?? JSON.stringify(tools.error)}`);
    if (!Array.isArray(tools.result?.tools)) throw new Error('MCP tools/list returned an invalid result.');

    cleanStop = await stopWorker(worker);
    if (!cleanStop) throw new Error('Server Worker did not stop cleanly after stdin closed.');
    const graph = finalizeGraph(moduleEdges, blockedAccesses, relativePath(packageRoot, entryPoint));
    return {
      passed: true,
      message: 'MCP initialize and tools/list succeeded.',
      durationMilliseconds: Date.now() - started,
      toolCount: tools.result.tools.length,
      cleanStop,
      blockedAccesses: graph.blockedAccesses,
      moduleEdges: graph.moduleEdges,
      reachableModuleCount: graph.reachableModuleCount,
      resolvedModuleCount: graph.moduleEdges.length,
      dynamicUnresolvedCount: dynamicModules.size,
      stderr: redact(stderr).slice(0, 16_384),
    };
  } catch (error) {
    if (worker && worker.threadId !== -1) cleanStop = await stopWorker(worker);
    const graph = finalizeGraph(moduleEdges, blockedAccesses, relativePath(packageRoot, entryPoint));
    const message = redact(error?.message ?? String(error));
    return {
      passed: false,
      failureCode: error?.code ?? null,
      requiresConfiguration: graph.blockedAccesses.length === 0 && looksLikeConfigurationFailure(`${message}\n${stderr}`),
      message,
      durationMilliseconds: Date.now() - started,
      toolCount: null,
      cleanStop,
      blockedAccesses: graph.blockedAccesses,
      moduleEdges: graph.moduleEdges,
      reachableModuleCount: graph.reachableModuleCount,
      resolvedModuleCount: graph.moduleEdges.length,
      dynamicUnresolvedCount: dynamicModules.size,
      stderr: redact(stderr).slice(0, 16_384),
    };
  } finally {
    await fs.rm(workspace, { recursive: true, force: true }).catch(() => {});
  }
}

function shouldRetryInternalLoaderFailure(result) {
  return !result.passed
    && !result.requiresConfiguration
    && (result.blockedAccesses?.length ?? 0) === 0
    && (
      result.failureCode === 'ERR_INTERNAL_ASSERTION'
      || /Unexpected module status \d+/.test(result.message)
    );
}

function createWorkerEvents(worker, state) {
  const loaded = deferred();
  worker.on('message', message => {
    if (message?.type === 'loaded') loaded.resolve(message);
    if (message?.type === 'module-edge') state.moduleEdges.push({
      parentPath: message.parentPath ?? null,
      specifier: String(message.specifier),
      resolvedPath: message.resolvedPath ?? null,
      moduleType: message.moduleType ?? 'unknown',
    });
    if (message?.type === 'policy-blocked') state.blockedAccesses.push({
      code: message.code,
      specifier: String(message.specifier),
      operation: message.operation ?? null,
      parentPath: message.parentPath ?? null,
      resolvedPath: message.resolvedPath ?? null,
    });
    if (message?.type === 'dynamic-unresolved' && message.path) state.dynamicModules.add(message.path);
  });
  return { loaded: loaded.promise, fail: loaded.reject };
}

function createResponseQueue() {
  const pending = new Map();
  let failure = null;
  return {
    push(message) {
      const waiter = pending.get(message?.id);
      if (waiter) { pending.delete(message.id); waiter.resolve(message); }
    },
    waitFor(id) {
      if (failure) return Promise.reject(failure);
      const value = deferred();
      pending.set(id, value);
      return value.promise;
    },
    fail(error) {
      if (failure) return;
      failure = error;
      for (const waiter of pending.values()) waiter.reject(error);
      pending.clear();
    },
  };
}

function finalizeGraph(edges, accesses, entryPoint) {
  const moduleEdges = [...new Map(edges.map(edge => [
    `${edge.parentPath ?? ''}\0${edge.specifier}\0${edge.resolvedPath ?? ''}`,
    edge,
  ])).values()];
  const reachable = new Set(moduleEdges.flatMap(edge => edge.resolvedPath && !edge.resolvedPath.startsWith('node:') ? [edge.resolvedPath] : []));
  const blockedAccesses = accesses.map(access => ({
    ...access,
    importChain: importChain(moduleEdges, entryPoint, access.parentPath, access.specifier),
  }));
  return { moduleEdges, blockedAccesses, reachableModuleCount: reachable.size };
}

function importChain(edges, entryPoint, parentPath, specifier) {
  if (!parentPath) return [entryPoint, specifier];
  const parents = new Map();
  for (const edge of edges) {
    if (edge.resolvedPath && edge.parentPath && !parents.has(edge.resolvedPath)) parents.set(edge.resolvedPath, edge.parentPath);
  }
  const reversed = [parentPath];
  const visited = new Set(reversed);
  while (reversed.at(-1) !== entryPoint) {
    const parent = parents.get(reversed.at(-1));
    if (!parent || visited.has(parent)) break;
    reversed.push(parent);
    visited.add(parent);
  }
  return [...reversed.reverse(), specifier];
}

function writeMessage(worker, message) {
  worker.stdin.write(`${JSON.stringify(message)}\n`);
}

async function stopWorker(worker) {
  if (worker.threadId === -1) return true;
  worker.stdin?.end();
  const exited = new Promise(resolve => worker.once('exit', () => resolve(true)));
  const graceful = await Promise.race([exited, new Promise(resolve => setTimeout(() => resolve(false), 1_000))]);
  if (!graceful && worker.threadId !== -1) await worker.terminate();
  return graceful;
}

function sanitizedEnvironment(workspace, supplied) {
  const environment = {
    HOME: workspace,
    USERPROFILE: workspace,
    TMPDIR: workspace,
    TMP: workspace,
    TEMP: workspace,
    NODE_ENV: 'production',
    HANLIN_MCP_RUNTIME_PROBE: '1',
  };
  if (supplied && typeof supplied === 'object' && !Array.isArray(supplied)) {
    for (const [name, value] of Object.entries(supplied)) {
      if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) continue;
      if (/^(?:HOME|USERPROFILE|PATH|TMPDIR|TMP|TEMP|NODE_OPTIONS|NODE_PATH|NPM_CONFIG_.+|.*(?:TOKEN|SECRET|PASSWORD|API_KEY).*)$/i.test(name)) continue;
      environment[name] = String(value);
    }
  }
  return environment;
}

function validatedArguments(value) {
  if (!Array.isArray(value)) return [];
  if (value.length > 128) throw new Error('Too many server arguments for the runtime probe.');
  return value.map(item => {
    const argument = String(item);
    if (/\0|\r|\n/.test(argument)) throw new Error('Invalid server argument for the runtime probe.');
    return argument;
  });
}

function looksLikeConfigurationFailure(value) {
  return /\b(?:missing|required|configure|configuration|environment variable|api key|credential)\b/i.test(value)
    && !/\b(?:syntax|module not found|cannot find module|unsupported|policy|child_process|cluster|native addon)\b/i.test(value);
}

function withTimeout(promise, milliseconds, message) {
  let timer;
  return Promise.race([
    promise,
    new Promise((_, reject) => { timer = setTimeout(() => reject(new Error(message)), milliseconds); }),
  ]).finally(() => clearTimeout(timer));
}

function deferred() {
  let resolve;
  let reject;
  let settled = false;
  const promise = new Promise((accept, decline) => {
    resolve = value => { if (!settled) { settled = true; accept(value); } };
    reject = error => { if (!settled) { settled = true; decline(error); } };
  });
  return { promise, resolve, reject };
}

function relativePath(root, candidate) {
  return (path.relative(path.resolve(root), path.resolve(candidate)) || '.').replaceAll(path.sep, '/');
}

function redact(value = '') {
  return String(value).replace(/(authorization|bearer|token|api[_-]?key|secret|password|cookie)\s*[:=]?\s*[^\s,;]+/gi, '$1=<redacted>');
}
