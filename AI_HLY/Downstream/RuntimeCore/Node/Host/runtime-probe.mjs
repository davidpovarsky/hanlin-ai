import { promises as fs } from 'node:fs';
import path from 'node:path';
import { Worker } from 'node:worker_threads';
import {StringDecoder} from 'node:string_decoder';
import {MCPLineFrames} from './mcp-framing.mjs';

const workerURL = new URL('./server-worker.mjs', import.meta.url);
const protocolVersion = '2025-06-18';

export async function runMCPRuntimeProbe(options) {
  let totalDurationMilliseconds = 0;
  let result;
  for (let attempt = 1; attempt <= 5; attempt += 1) {
    options.signal?.throwIfAborted();
    result = await runMCPRuntimeProbeAttempt(options);
    options.signal?.throwIfAborted();
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
  const timeoutMilliseconds = options.timeoutMilliseconds;
  const maximumOutputBytes = options.maximumOutputBytes;
  if(timeoutMilliseconds!=null&&(!Number.isSafeInteger(timeoutMilliseconds)||timeoutMilliseconds<=0
      ||!Number.isSafeInteger(Date.now()+timeoutMilliseconds)))throw new TypeError('Invalid explicit probe timeout.');
  if(maximumOutputBytes!=null&&(!Number.isSafeInteger(maximumOutputBytes)||maximumOutputBytes<0))
    throw new TypeError('Invalid explicit probe output budget.');
  options.signal?.throwIfAborted();
  const ownsWorkspace = options.workspace == null;
  const workspace = ownsWorkspace ? await fs.mkdtemp(path.join(path.dirname(packageRoot), 'probe-workspace-')) : path.resolve(options.workspace);
  await fs.mkdir(workspace, { recursive: true });

  const moduleEdges = [];
  const blockedAccesses = [];
  const dynamicModules = new Set();
  let outputBytes = 0;
  let stderr = '';
  const frames=new MCPLineFrames(),stderrDecoder=new StringDecoder('utf8');
  let stdoutTail=Promise.resolve(),stderrTail=Promise.resolve(),removeAbort=()=>{};
  let worker;
  let cleanStop = false;
  let stopAttempted = false;

  try {
    worker = new Worker(workerURL, {
      workerData: {
        packageRoot,
        entryPoint,
        moduleKind: options.moduleKind,
        runtimeProbe: true,
        environment: suppliedEnvironment(options.environment),
      },
      argv: validatedArguments(options.arguments),
      env: sanitizedEnvironment(workspace),
      // Retain Node's default FD ownership tracking in the actual probe too.
      stdin: true,
      stdout: true,
      stderr: true,
    });

    const events = createWorkerEvents(worker, { moduleEdges, blockedAccesses, dynamicModules });
    const responses = createResponseQueue();
    const fail=error=>{events.fail(error);responses.fail(error);};
    const processChunk=async(channel,chunk)=>{
      outputBytes+=chunk.length;
      await options.onOutput?.(channel,chunk);
      if(maximumOutputBytes!=null&&outputBytes>maximumOutputBytes)throw new Error('Runtime probe output exceeded its explicit budget.');
      if(channel==='stderr')stderr+=stderrDecoder.write(chunk);
      else for(const bytes of frames.push(chunk)) {
        const line=bytes.toString('utf8').trim();
        if(!line)continue;
        try{responses.push(JSON.parse(line));}catch{/* diagnostic stdout is not MCP traffic */}
      }
    };
    worker.stdout.on('data',chunk=>{
      worker.stdout.pause();
      stdoutTail=stdoutTail.then(()=>processChunk('stdout',chunk)).catch(fail).finally(()=>worker.stdout.resume());
    });
    worker.stderr.on('data',chunk=>{
      worker.stderr.pause();
      stderrTail=stderrTail.then(()=>processChunk('stderr',chunk)).catch(fail).finally(()=>worker.stderr.resume());
    });
    worker.once('error',fail);
    worker.once('exit',code=>{
      void Promise.all([stdoutTail,stderrTail]).then(()=>{
        if(stopAttempted)return;
        const diagnostic=redact(stderr).trim().slice(-2048);
        fail(Object.assign(new Error(`Server Worker exited during the runtime probe with code ${code}.`
          +(diagnostic?` Worker stderr: ${diagnostic}`:'')),{exitCode:code}));
      }).catch(fail);
    });
    const onAbort=()=>fail(options.signal.reason??new Error('Runtime probe cancelled.'));
    if(options.signal){
      options.signal.addEventListener('abort',onAbort,{once:true});
      removeAbort=()=>options.signal.removeEventListener('abort',onAbort);
      if(options.signal.aborted)onAbort();
    }

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

    stopAttempted = true;
    const stopResult = await stopWorker(worker);
    cleanStop = stopResult.graceful;
    if (!stopResult.stopped) {
      throw new Error('Server Worker did not stop within the bounded shutdown deadline.');
    }
    await Promise.all([stdoutTail,stderrTail]);
    stderr+=stderrDecoder.end();
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
      stderr: redact(stderr),
    };
  } catch (error) {
    if (worker && worker.threadId !== -1 && !stopAttempted) {
      stopAttempted = true;
      cleanStop = (await stopWorker(worker)).graceful;
    }
    await Promise.all([stdoutTail,stderrTail]);
    stderr+=stderrDecoder.end();
    const graph = finalizeGraph(moduleEdges, blockedAccesses, relativePath(packageRoot, entryPoint));
    options.signal?.throwIfAborted();
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
      stderr: redact(stderr),
    };
  } finally {
    removeAbort();
    if (ownsWorkspace) await fs.rm(workspace, { recursive: true, force: true }).catch(() => {});
  }
}

export function shouldRetryInternalLoaderFailure(result) {
  const diagnostics = `${result.message ?? ''}\n${result.stderr ?? ''}`;
  return !result.passed
    && !result.requiresConfiguration
    && (result.blockedAccesses?.length ?? 0) === 0
    && (
      result.failureCode === 'ERR_INTERNAL_ASSERTION'
      || /Unexpected module status \d+/.test(diagnostics)
      || /Server Worker exited during the runtime probe with code 1\./.test(result.message)
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
  if (worker.threadId === -1) return { stopped: true, graceful: true };
  const exited = new Promise(resolve => worker.once('exit', code => resolve({ code })));
  try { worker.stdin?.end(); } catch { /* forced termination remains available */ }
  const gracefulExit = await settleWithin(exited, 1_000);
  if (gracefulExit || worker.threadId === -1) {
    return { stopped: true, graceful: true };
  }

  let termination;
  try {
    termination = worker.terminate();
  } catch {
    worker.unref();
    return { stopped: false, graceful: false };
  }
  const forcedExit = await settleWithin(
    Promise.race([
      exited,
      termination.then(code => ({ code })),
    ]),
    3_000,
  ).catch(() => null);
  if (!forcedExit) worker.unref();
  return { stopped: Boolean(forcedExit), graceful: false };
}

function sanitizedEnvironment(workspace) {
  const environment = {
    HOME: workspace,
    USERPROFILE: workspace,
    TMPDIR: workspace,
    TMP: workspace,
    TEMP: workspace,
    NODE_ENV: 'production',
    HANLIN_MCP_RUNTIME_PROBE: '1',
  };
  return environment;
}

function suppliedEnvironment(supplied) {
  if (supplied == null) return {};
  if (typeof supplied !== 'object' || Array.isArray(supplied)) throw new Error('Probe environment must be a dictionary.');
  const result = Object.create(null);
  for (const [name, value] of Object.entries(supplied)) {
    if ((!name || name.includes('=') || name.includes('\0'))) throw new Error('Invalid probe environment name.');
    const text = String(value);
    if (text.includes('\0')) throw new Error('Environment values cannot contain a NUL byte.');
    result[name] = text;
  }
  return result;
}

function validatedArguments(value) {
  if (!Array.isArray(value)) return [];
  return value.map(item => {
    const argument = String(item);
    if (argument.includes('\0')) throw new Error('Invalid server argument for the runtime probe.');
    return argument;
  });
}

function looksLikeConfigurationFailure(value) {
  return /\b(?:missing|required|configure|configuration|environment variable|api key|credential)\b/i.test(value)
    && !/\b(?:syntax|module not found|cannot find module|unsupported|policy|child_process|cluster|native addon)\b/i.test(value);
}

function withTimeout(promise, milliseconds, message) {
  if(milliseconds==null)return promise;
  const deadline=performance.now()+milliseconds;
  let timer;
  const expired=new Promise((_,reject)=>{
    const tick=()=>{
      const remaining=deadline-performance.now();
      if(remaining<=0)reject(new Error(message));
      else timer=setTimeout(tick,Math.min(remaining,2_147_483_647));
    };
    tick();
  });
  return Promise.race([promise,expired]).finally(()=>clearTimeout(timer));
}

function settleWithin(promise, milliseconds) {
  let timer;
  return Promise.race([
    promise,
    new Promise(resolve => {
      timer = setTimeout(() => resolve(null), milliseconds);
    }),
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
