import {compileTypeScript, compileTypeScriptProject} from './typescript-compiler.mjs';
import {resolveMCPPackageRoot} from './mcp-package-generations.mjs';
import {runtimeCapabilities} from './runtime-capabilities.mjs';
import { verifyLifecyclePlan } from './lifecycle-planner.mjs';
import { globalNodeModules } from './global-package-state.mjs';
import {executeLifecycleInJobs} from './lifecycle-executor.mjs';
import { ExecutionJobs } from './execution-jobs.mjs';
import './fetch-compatibility.mjs';
import { traceRuntimeWarnings } from './warning-diagnostics.mjs';
import http from 'node:http';
import dns from 'node:dns';
if (typeof dns.setDefaultResultOrder === 'function') {
  dns.setDefaultResultOrder('ipv4first');
}
import {
  promises as fs,
  createWriteStream,
  realpathSync,
  statSync,
} from 'node:fs';
import path from 'node:path';
import { Worker } from 'node:worker_threads';
import { timingSafeEqual } from 'node:crypto';
import * as nodeModule from 'node:module';

const [root, readyPath, launchToken, logPath, debugFlag] = process.argv.slice(2);
if (!root || !readyPath || !launchToken || !logPath) throw new Error('Missing host launch arguments.');

const runtimeHome = path.join(root, 'runtime', 'home');
const npmCache = path.join(root, 'cache', 'npm');
const npmPrefix = path.join(root, 'runtime', 'npm-prefix');
const npmTemp = path.join(root, 'staging', 'tmp');
const xdgCache = path.join(root, 'cache', 'xdg');
const clientsRoot = path.join(root, 'clients');
const mcpPackagesRoot = path.join(root, 'packages', 'mcp');

await Promise.all([
  path.join(root, 'runtime'),
  path.join(root, 'registry'),
  path.join(root, 'packages'),
  mcpPackagesRoot,
  path.join(root, 'packages', 'node-global'),
  clientsRoot,
  path.join(root, 'staging'),
  path.join(root, 'cache'),
  runtimeHome,
  npmCache,
  npmPrefix,
  npmTemp,
  xdgCache,
].map(directory => fs.mkdir(directory, { recursive: true })));

process.env.HOME = runtimeHome;
process.env.USERPROFILE = runtimeHome;
process.env.TMPDIR = npmTemp;
process.env.TMP = npmTemp;
process.env.TEMP = npmTemp;
process.env.XDG_CACHE_HOME = xdgCache;
process.env.npm_config_cache = npmCache;
process.env.NPM_CONFIG_CACHE = npmCache;
process.env.npm_config_prefix = npmPrefix;
process.env.NPM_CONFIG_PREFIX = npmPrefix;
process.env.npm_config_tmp = npmTemp;
process.env.NPM_CONFIG_TMP = npmTemp;

const npmUserConfig = path.join(root, 'runtime', 'npmrc');
await fs.writeFile(npmUserConfig, [
  `cache=${npmCache}`,
  `prefix=${npmPrefix}`,
  'audit=false',
  'fund=false',
  'ignore-scripts=true',
].join('\n'), { flag: 'w', mode: 0o600 });
process.env.npm_config_userconfig = npmUserConfig;
process.env.NPM_CONFIG_USERCONFIG = npmUserConfig;

const DEBUG = debugFlag === '1';
const modulePolicyHooksAvailable = typeof nodeModule.registerHooks === 'function';
if (!modulePolicyHooksAvailable) {
  throw new Error(`Node ${process.versions.node} does not provide module.registerHooks; RuntimeCore refuses to start unguarded.`);
}
const logStream = createWriteStream(logPath, { flags: 'a' });
diagnostic('runtime_paths_configured', {
  home: runtimeHome,
  npmCache,
  npmPrefix,
  npmTemp,
});

const { commitInstall, installPackage, previewPackage, rollbackInstall } =
  await import('./package-installer.mjs');
const { commitGlobalPackage, installGlobalPackage, listGlobalPackages, previewGlobalPackage, rollbackGlobalPackage, stageGlobalPackage, stageUninstallGlobalPackage, uninstallGlobalPackage } =
  await import('./global-package-manager.mjs');

const workerURL = new URL('./server-worker.mjs', import.meta.url);
const executionWorkerURL = new URL('./execution-worker.mjs', import.meta.url);
const servers = new Map();
const serverRestarts = new Map();
const serverGenerations = new Map();
const executionJobs = new ExecutionJobs({ root: path.join(root, 'jobs', 'node'), workerURL: executionWorkerURL, diagnosticWorkerURL: new URL('./diagnostic-worker.mjs', import.meta.url), globalNodeModules: () => globalNodeModules(root),
  inputInbox:path.join(root,'runtime','node','requests'),validateInput:validateExecutionInput });
await executionJobs.initialize();
const installProgress = new Map();
const maximumBody = 10 * 1024 * 1024;
const maximumLine = 8 * 1024 * 1024;
const gracefulStopTimeoutMilliseconds = 3_000;
const lifecycleCounters = {
  workerCreationCount: 0,
  activeWorkerCount: 0,
  maximumSimultaneousWorkers: 0,
  gracefulStopCount: 0,
  forcedTerminationCount: 0,
  finalizeCount: 0,
};
const lifecycleCountersByServer = new Map();

const server = http.createServer(async (request, response) => {
  try {
    if (!authorized(request)) return json(response, 401, { error: 'Unauthorized' });
    const url = new URL(request.url, 'http://127.0.0.1');
    if (request.method === 'GET' && url.pathname === '/v1/runtime/capabilities')return json(response,200,runtimeCapabilities());
    if (request.method === 'GET' && url.pathname === '/health') return json(response, 200, { ok: true, nodeVersion: process.versions.node, protocolVersion: 2, modulePolicyHooksAvailable });
    if (request.method === 'GET' && url.pathname === '/v1/runtime') {
      return json(response, 200, {
        nodeVersion: process.versions.node,
        protocolVersion: 2,
        modulePolicyHooksAvailable,
        workers: [...servers.values()].map(snapshot),
        executions: executionJobs.activeCount,
        lifecycle: lifecycleDiagnostics(),
      });
    }
    if (request.method === 'POST' && url.pathname === '/v1/executions') {
      const body = await readJSON(request);
      const stopTracing = body.environment?.HANLIN_NODE_TRACE_WARNINGS === '1' ? traceRuntimeWarnings() : () => {};
      try {
        return json(response, 200, await executeJavaScript(body));
      } finally {
        stopTracing();
      }
    }
    if (request.method === 'GET' && url.pathname === '/v1/commands/wait') {
      const controller=new AbortController();
      const close=()=>controller.abort();response.once('close',close);
      try {
        const pending=await executionJobs.waitForCommandRequests(controller.signal);
        if(!response.destroyed)json(response,200,pending);
      } finally {response.off('close',close);}
      return;
    }
    if (request.method === 'GET' && url.pathname === '/v1/commands') {
      return json(response, 200, await executionJobs.allCommandRequests());
    }
    const executionCommandFailure = url.pathname.match(/^\/v1\/executions\/([0-9a-f-]+)\/commands\/([0-9a-f-]+)\/fail$/i);
    if (request.method === 'POST' && executionCommandFailure) {
      const body = await readJSON(request);
      if (typeof body.error !== 'string') throw new Error('Missing adapter error.');
      await executionJobs.failCommand(executionCommandFailure[1].toLowerCase(), executionCommandFailure[2].toLowerCase(), body.error);
      return json(response, 200, { acknowledged: true });
    }
    const executionCommands = url.pathname.match(/^\/v1\/executions\/([0-9a-f-]+)\/commands$/i);
    if (request.method === 'GET' && executionCommands) {
      return json(response, 200, await executionJobs.commandRequests(executionCommands[1].toLowerCase()));
    }
    const executionPage = url.pathname.match(/^\/v1\/executions\/([0-9a-f-]+)\/(stdout|stderr)$/i);
    if (request.method === 'GET' && executionPage) {
      const page = await executionJobs.readOutput(executionPage[1].toLowerCase(), executionPage[2], Number(url.searchParams.get('offset') ?? 0), Number(url.searchParams.get('limit') ?? 16_384));
      return json(response, page ? 200 : 404, page ?? { error: 'Execution not found.' });
    }
    const executionStatus = url.pathname.match(/^\/v1\/executions\/([0-9a-f-]+)$/i);
    if (request.method === 'GET' && executionStatus) {
      const state = executionJobs.snapshot(executionStatus[1].toLowerCase());
      return json(response, state ? 200 : 404, state ?? { error: 'Execution not found.' });
    }
    const executionCancel = url.pathname.match(/^\/v1\/executions\/([0-9a-f-]+)\/cancel$/i);
    if (request.method === 'POST' && executionCancel) {
      const state = await executionJobs.cancel(executionCancel[1].toLowerCase());
      return json(response, 200, { cancelled: state?.cancellationRequested ?? false });
    }
    const executionInterrupt = url.pathname.match(/^\/v1\/executions\/([0-9a-f-]+)\/interrupt$/i);
    if (request.method === 'POST' && executionInterrupt) {
      const body = await readJSON(request);
      const state = await executionJobs.interrupt(executionInterrupt[1].toLowerCase(), body.reason);
      return json(response, 200, { interruptionRequested: state?.interruptionReason != null });
    }
    if (request.method === 'POST' && url.pathname === '/v1/typescript/compile') {
      return json(response, 200, await compileTypeScript(await readJSON(request), {root}));
    }
    if (request.method === 'POST' && url.pathname === '/v1/typescript/project') {
      return json(response, 200, await compileTypeScriptProject(await readJSON(request)));
    }
    if (request.method === 'GET' && url.pathname === '/v1/packages/node') {
      return json(response, 200, { packages: await listGlobalPackages({ root }) });
    }
    if (request.method === 'POST' && url.pathname === '/v1/packages/node/preview') {
      const body = await readJSON(request);
      return json(response, 200, await previewGlobalPackage({ root, name: body.name, version: body.version }));
    }
    if (request.method === 'POST' && url.pathname === '/v1/packages/lifecycle/verify') {
      const body = await readJSON(request);
      return json(response, 200, await verifyLifecyclePlan(body.packageRoot, body.plan));
    }
    if (request.method === 'POST' && url.pathname === '/v1/packages/node/install') {
      const body = await readJSON(request);
      return json(response, 200, await installGlobalPackage({ root, name: body.name, version: body.version }));
    }
    if (request.method === 'POST' && url.pathname === '/v1/packages/node/stage') {
      const body = await readJSON(request);
      return json(response, 200, await stageGlobalPackage({ root, name: body.name, version: body.version }));
    }
    if (request.method === 'POST' && url.pathname === '/v1/packages/node/stage-uninstall') {
      const body = await readJSON(request);
      return json(response, 200, await stageUninstallGlobalPackage({root,name:body.name}));
    }
    if (request.method === 'POST' && url.pathname === '/v1/packages/node/commit') {
      const body = await readJSON(request);
      return json(response, 200, await commitGlobalPackage({ root, transactionID: body.transactionID }));
    }
    if (request.method === 'POST' && url.pathname === '/v1/packages/node/rollback') {
      const body = await readJSON(request);
      return json(response, 200, await rollbackGlobalPackage({ root, transactionID: body.transactionID }));
    }
    if (request.method === 'POST' && url.pathname === '/v1/packages/node/uninstall') {
      const body = await readJSON(request);
      return json(response, 200, await uninstallGlobalPackage({ root, name: body.name }));
    }
    const installStatusMatch = url.pathname.match(/^\/v1\/install\/status\/([0-9a-f-]+)$/i);
    if (request.method === 'GET' && installStatusMatch) {
      const operationID = installStatusMatch[1].toLowerCase();
      if (!validID(operationID)) return json(response, 400, { error: 'Invalid operation ID' });
      const job=executionJobs.snapshot(operationID);
      let progress=installProgress.get(operationID)??job?.progress??null;
      if(job?.state==='interrupted'&&progress)progress={...progress,terminalError:{code:'interrupted',message:job.error}};
      return json(response, 200, { progress });
    }
    if (request.method === 'POST' && url.pathname === '/v1/install/preview') {
      const body = await readJSON(request);
      return json(response, 200, await previewPackage(body.source, { root, entryPointOverride: body.entryPointOverride }));
    }
    if (request.method === 'POST' && url.pathname === '/v1/install') {
      const body = await readJSON(request);
      const operation = await executionJobs.startOperation({executionID:body.operationID},async({signal,emit})=>{
        const progress=data=>{installProgress.set(body.operationID,data);emit(data);emitGlobal('install',data);};
        progress({operationID:body.operationID,phase:'resolving',fraction:0});
        try {
          const descriptor = await installPackage({
            root,
            operationID: body.operationID,
            serverID: body.serverID,
            source: body.source,
            entryPointOverride: body.entryPointOverride,
            arguments: body.arguments,
            signal,
            executeLifecycle: options=>executeLifecycleInJobs({...options,jobs:executionJobs,runtimeRoot:root,
              onProgress: detail=>{
                progress({operationID:body.operationID,phase:'installingDependencies',fraction:0.68,lifecycle:detail});
              }}),
            emit: (channel, data) => {
              if (channel === 'install') progress(data);
              else emitGlobal(channel, data);
            },
          });
          return descriptor;
        } catch (error) {
          error.operationID = body.operationID;
          const prior = installProgress.get(body.operationID);
          progress({
            operationID: body.operationID,
            phase: prior?.phase ?? 'checkingCompatibility',
            fraction: prior?.fraction ?? null,
            terminalError: {
              code: error.code ?? 'install_failed',
              message: redact(error.message),
              findings: error.findings ?? null,
            },
          });
          throw error;
        }
      });
      if(body.detached===true)return json(response,200,operation);
      const completed=await executionJobs.wait(operation.executionID);
      if(completed.state!=='completed')throw new Error(completed.error??completed.result?.stderr??'Installation failed.');
      return json(response,200,completed.result.value);
    }
    if (request.method === 'POST' && url.pathname === '/v1/install/cancel') {
      const body = await readJSON(request);
      await executionJobs.cancel(body.operationID);
      return json(response, 200, { cancelled: true });
    }
    if (request.method === 'POST' && url.pathname === '/v1/install/commit') {
      const body = await readJSON(request);
      await commitInstall({ root, operationID: body.operationID, serverID: body.serverID });
      installProgress.delete(body.operationID);
      return json(response, 200, { committed: true });
    }
    if (request.method === 'POST' && url.pathname === '/v1/install/rollback') {
      const body = await readJSON(request);
      await rollbackInstall({ root, operationID: body.operationID, serverID: body.serverID });
      installProgress.delete(body.operationID);
      return json(response, 200, { rolledBack: true });
    }

    const match = url.pathname.match(/^\/v1\/servers\/([0-9a-f-]+)(?:\/(start|stop|restart|stdin|events|logs))?$/i);
    if (!match || !validID(match[1])) return json(response, 404, { error: 'Not found' });
    const id = match[1].toLowerCase();
    const action = match[2];
    if (request.method === 'POST' && action === 'start') return json(response, 200, await startServer(id, await readJSON(request)));
    if (request.method === 'POST' && action === 'stop') return json(response, 200, await stopServer(id));
    if (request.method === 'POST' && action === 'restart') {
      return json(response, 200, await restartServer(id, await readJSON(request)));
    }
    if (request.method === 'POST' && action === 'stdin') {
      const body = await readJSON(request);
      const state = servers.get(id);
      if (!state?.worker.stdin) return json(response, 409, { error: 'Server is not running' });
      const data = Buffer.from(body.data ?? '', 'base64');
      if (data.length > maximumLine) return json(response, 413, { error: 'Input is too large' });
      await new Promise((resolve, reject) => state.worker.stdin.write(data, error => error ? reject(error) : resolve()));
      return json(response, 200, { accepted: data.length });
    }
    if (request.method === 'GET' && action === 'events') return attachEvents(id, request, response);
    if (request.method === 'GET' && action === 'logs') return sendLogs(id, response);
    if (request.method === 'DELETE' && !action) {
      await stopServer(id);
      const directory = safeServerDirectory(id);
      const trash = path.join(root, 'staging', `uninstall-${id}-${Date.now()}`);
      try { await fs.rename(directory, trash); await fs.rm(trash, { recursive: true, force: true }); } catch (error) {
        if (error.code !== 'ENOENT') throw error;
      }
      return json(response, 200, { deleted: true });
    }
    return json(response, 404, { error: 'Not found' });
  } catch (error) {
    diagnostic('request_failed', { path: request.url, message: redact(error.message) });
    const status=Number.isInteger(error.status)&&error.status>=400&&error.status<=599
      ? error.status:error.name==='AbortError'?499:400;
    if (!response.headersSent) json(response, status, {
      error: redact(error.message),
      operationID: error.operationID ?? null,
      code: error.code ?? null,
    });
    else response.end();
  }
});

server.on('clientError', (err, socket) => {
  if (err.code === 'ECONNRESET' || !socket.writable) {
    socket.destroy();
    return;
  }
  socket.end('HTTP/1.1 400 Bad Request\r\n\r\n');
});

server.listen(0, '127.0.0.1', async () => {
  const address = server.address();
  const ready = { port: address.port, nodeVersion: process.versions.node, protocolVersion: 2, modulePolicyHooksAvailable };
  const temporary = `${readyPath}.tmp`;
  await fs.writeFile(temporary, JSON.stringify(ready), { mode: 0o600 });
  await fs.rename(temporary, readyPath);
  diagnostic('host_ready', { port: address.port, nodeVersion: process.versions.node, modulePolicyHooksAvailable });
});

function authorized(request) {
  const expected = Buffer.from(`Bearer ${launchToken}`);
  const actual = Buffer.from(request.headers.authorization ?? '');
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

async function executeJavaScript(body) {
  const header = await executionJobs.start(body);
  if (body.detached === true) return executionJobs.snapshot(header.executionID);
  const completed = await executionJobs.wait(header.executionID);
  if (!completed.result) throw new Error(completed.error ?? 'Execution did not produce a result.');
  return completed.result;
}

async function validateExecutionInput(body) {
  const id = String(body.executionID ?? '').toLowerCase();
  if (!validID(id)) throw new Error('Invalid execution ID.');
  if (body.executionMode != null && !['source', 'cli'].includes(body.executionMode)) throw new Error('Unsupported Node execution mode.');
  const cli = body.executionMode === 'cli';
  if (!cli && typeof body.source !== 'string') throw new Error('JavaScript source is missing.');
  if (!['esm', 'commonjs'].includes(body.moduleKind)) throw new Error('Unsupported JavaScript module kind.');
  const workspace = path.resolve(String(body.workspace ?? ''));
  if (!workspace) throw new Error('Execution workspace must be specified.');
  let stat;
  try {
    stat = await fs.stat(workspace);
  } catch (err) {
    const error = new Error(`Execution workspace does not exist: ${err.message}`);
    error.status = 404;
    throw error;
  }
  if (!stat.isDirectory()) {
    const error = new Error('Execution workspace must be a directory.');
    error.status = 400;
    throw error;
  }
  if (cli) {
    if (typeof body.entryPoint !== 'string' || !path.isAbsolute(body.entryPoint)) throw new Error('CLI entryPoint must be an absolute file path.');
    body.entryPoint = await fs.realpath(body.entryPoint);
    if (!(await fs.stat(body.entryPoint)).isFile()) throw new Error('CLI entryPoint must be a regular file.');
    if (body.standardInputPath != null) {
      if (typeof body.standardInputPath !== 'string' || !path.isAbsolute(body.standardInputPath)) throw new Error('CLI stdin must be an absolute file path.');
      body.standardInputPath = await fs.realpath(body.standardInputPath);
      if (!(await fs.stat(body.standardInputPath)).isFile()) throw new Error('CLI stdin must be a regular file.');
    }
  } else rejectUnsafeSource(body.source);
  return {...body,workspace,environment:validatedEnvironment(body.environment)};
}


function validatedEnvironment(value) {
  const output = Object.create(null);
  if (value == null) return output;
  if (typeof value !== 'object' || Array.isArray(value)) throw new Error('Environment must be a dictionary.');
  for (const [name, item] of Object.entries(value)) {
    if ((!name || name.includes('=') || name.includes('\0'))) throw new Error(`Invalid environment name: ${name}`);
    const text = String(item);
    if (text.includes('\0')) throw new Error('Environment values cannot contain a NUL byte.');
    output[name] = text;
  }
  return output;
}

function rejectUnsafeSource(_source) {
  // R12: Removed word blocking. String/comments are not API calls.
}

async function startServer(id, configuration) {
  if (configuration.serverID?.toLowerCase() !== id) throw new Error('Server ID mismatch.');
  const existing = servers.get(id);
  if (existing) {
    if (existing.state === 'running') return snapshot(existing);
    if (existing.state === 'starting') {
      await existing.readyPromise;
      return snapshot(existing);
    }
    if (existing.state === 'stopping') {
      await existing.stopPromise;
      return startServer(id, configuration);
    }
    await finalizeServerState(existing, {
      state: existing.state === 'failed' ? 'failed' : 'stopped',
      reason: 'stale-state-before-start',
    });
  }
  const packageRoot = await resolveMCPPackageRoot(root, id, configuration.packageRoot);
  const requestedEntryPoint = path.resolve(configuration.entryPoint);
  const entryPoint = realpathSync(requestedEntryPoint);
  if (!isInside(packageRoot, entryPoint)) throw new Error('Entry point is outside package root.');
  if (!statSync(entryPoint).isFile()) throw new Error('Entry point is not a regular file.');

  const generation = (serverGenerations.get(id) ?? 0) + 1;
  serverGenerations.set(id, generation);
  const ready = deferred();
  const exited = deferred();
  const state = {
    id,
    generation,
    state: 'starting',
    worker: null,
    readyPromise: ready.promise,
    resolveReady: ready.resolve,
    rejectReady: ready.reject,
    exitPromise: exited.promise,
    resolveExit: exited.resolve,
    stopPromise: null,
    clients: new Set(),
    stdoutBacklog: [],
    stdoutBacklogBytes: 0,
    stderr: [],
    pending: Buffer.alloc(0),
    startedAt: new Date().toISOString(),
    moduleEdges: [],
    blockedAccesses: [],
    expectedStop: false,
    finalized: false,
    forcedTermination: false,
    stdinEnded: false,
    countedActive: true,
    handlers: {},
  };
  const worker = new Worker(workerURL, {
    workerData: { serverID: id, packageRoot, entryPoint, environment: validatedEnvironment(configuration.environment) },
    argv: Array.isArray(configuration.arguments) ? configuration.arguments : [],
    // Server values are applied after loading the wrapper, never as bootstrap
    // NODE_OPTIONS. The Host's launch identity/configuration stays immutable.
    env: { ...executionJobs.workerEnvironment, HANLIN_MCP_SERVER_ID: id },
    // Retain Node's default FD ownership tracking; never conceal regressions.
    stdin: true,
    stdout: true,
    stderr: true,
  });
  state.worker = worker;
  servers.set(id, state);
  lifecycleCounters.workerCreationCount += 1;
  lifecycleCounters.activeWorkerCount += 1;
  lifecycleCounters.maximumSimultaneousWorkers = Math.max(
    lifecycleCounters.maximumSimultaneousWorkers,
    lifecycleCounters.activeWorkerCount,
  );
  const serverCounters = lifecycleCountersByServer.get(id) ?? {
    workerCreationCount: 0,
    activeWorkerCount: 0,
    maximumSimultaneousWorkers: 0,
    gracefulStopCount: 0,
    forcedTerminationCount: 0,
    finalizeCount: 0,
  };
  serverCounters.workerCreationCount += 1;
  serverCounters.activeWorkerCount += 1;
  serverCounters.maximumSimultaneousWorkers = Math.max(
    serverCounters.maximumSimultaneousWorkers,
    serverCounters.activeWorkerCount,
  );
  lifecycleCountersByServer.set(id, serverCounters);
  state.handlers.stdout = chunk => handleStdout(state, chunk);
  state.handlers.stderr = chunk => {
    const message = redact(chunk.toString('utf8')).slice(0, maximumLine);
    state.stderr.push(message);
    if (state.stderr.length > 500) state.stderr.shift();
    emit(state, 'stderr', { text: message });
  };
  state.handlers.message = message => {
    if (message?.type === 'module-edge') state.moduleEdges.push(message);
    if (message?.type === 'policy-blocked') state.blockedAccesses.push(message);
    if (message?.type === 'loaded' && state.state === 'starting') {
      state.state = 'running';
      state.resolveReady();
      emit(state, 'lifecycle', {
        event: 'server-ready',
        generation: state.generation,
        modulePolicyHooksAvailable: message.modulePolicyHooksAvailable === true,
      });
    }
  };
  state.handlers.error = error => {
    if (state.state === 'stopping') {
      diagnostic('server_error_during_stop', {
        serverID: state.id,
        generation: state.generation,
        message: redact(error.message),
      });
      return;
    }
    state.state = 'failed';
    state.rejectReady(error);
    emit(state, 'lifecycle', { event: 'error', message: redact(error.message) });
  };
  state.handlers.exit = code => {
    state.resolveExit({ code });
    if (state.state === 'starting') {
      state.rejectReady(new Error(`Server worker exited during startup with code ${code}.`));
    }
    void handleWorkerExit(state, code);
  };
  worker.stdout.on('data', state.handlers.stdout);
  worker.stderr.on('data', state.handlers.stderr);
  worker.on('message', state.handlers.message);
  worker.on('error', state.handlers.error);
  worker.on('exit', state.handlers.exit);

  try {
    await withTimeout(state.readyPromise, 15_000, 'Server worker startup timed out.');
    return snapshot(state);
  } catch (error) {
    await stopServerState(state, {
      expectedStop: false,
      forceAfterTimeout: true,
      failure: error,
    });
    throw error;
  }
}

async function stopServer(id) {
  const state = servers.get(id);
  if (!state) return stoppedSnapshot(id);
  return stopServerState(state, { expectedStop: true });
}

function stopServerState(state, options = {}) {
  if (state.stopPromise) return state.stopPromise;
  state.stopPromise = (async () => {
    state.expectedStop ||= options.expectedStop === true;
    state.state = 'stopping';
    emit(state, 'lifecycle', {
      event: 'stopping',
      generation: state.generation,
      reason: options.failure ? redact(options.failure.message) : null,
    });
    finishEventClients(state, 'stopping');
    if (!state.stdinEnded) {
      state.stdinEnded = true;
      try { state.worker.stdin?.end(); } catch (error) {
        diagnostic('server_stdin_end_failed', {
          serverID: state.id,
          generation: state.generation,
          message: redact(error.message),
        });
      }
    }

    let exitResult = options.forceImmediately
      ? null
      : await settleWithin(state.exitPromise, gracefulStopTimeoutMilliseconds);
    if (!exitResult && state.worker.threadId !== -1 && !state.forcedTermination) {
      state.forcedTermination = true;
      lifecycleCounters.forcedTerminationCount += 1;
      lifecycleCountersByServer.get(state.id).forcedTerminationCount += 1;
      let termination;
      try {
        termination = state.worker.terminate();
      } catch (error) {
        diagnostic('server_terminate_failed', {
          serverID: state.id,
          generation: state.generation,
          message: redact(error.message),
        });
      }
      if (termination) {
        exitResult = await settleWithin(
          Promise.race([
            state.exitPromise,
            termination.then(code => ({ code })),
          ]),
          gracefulStopTimeoutMilliseconds,
        ).catch(error => {
          diagnostic('server_terminate_failed', {
            serverID: state.id,
            generation: state.generation,
            message: redact(error.message),
          });
          return null;
        });
      }
      if (!exitResult) {
        state.worker.unref();
        diagnostic('server_termination_timeout', {
          serverID: state.id,
          generation: state.generation,
          timeoutMilliseconds: gracefulStopTimeoutMilliseconds,
        });
      }
    } else if (exitResult && state.expectedStop) {
      lifecycleCounters.gracefulStopCount += 1;
      lifecycleCountersByServer.get(state.id).gracefulStopCount += 1;
    }

    const result = {
      state: state.expectedStop ? 'stopped' : 'failed',
      code: exitResult?.code ?? null,
      reason: options.failure ? redact(options.failure.message) : null,
    };
    await finalizeServerState(state, result);
    return stoppedSnapshot(state.id, state.generation, result.state);
  })();
  return state.stopPromise;
}

function restartServer(id, configuration) {
  const existing = serverRestarts.get(id);
  if (existing) return existing;
  const operation = (async () => {
    await stopServer(id);
    return startServer(id, configuration);
  })();
  serverRestarts.set(id, operation);
  operation.finally(() => {
    if (serverRestarts.get(id) === operation) serverRestarts.delete(id);
  }).catch(() => {});
  return operation;
}

async function handleWorkerExit(state, code) {
  const expected = state.expectedStop || state.state === 'stopping';
  const resultState = expected ? 'stopped' : (code === 0 ? 'stopped' : 'failed');
  emit(state, 'lifecycle', {
    event: 'exit',
    code,
    generation: state.generation,
    expected,
  });
  await finalizeServerState(state, { state: resultState, code, reason: 'worker-exit' });
}

async function finalizeServerState(state, result) {
  if (state.finalized) return;
  state.finalized = true;
  state.state = result.state;
  state.rejectReady(new Error(result.reason ?? `Server worker finalized as ${result.state}.`));
  finishEventClients(state, result.state);
  state.pending = Buffer.alloc(0);
  state.stdoutBacklog = [];
  state.stdoutBacklogBytes = 0;
  state.stderr = [];
  if (state.handlers.stdout) state.worker.stdout?.off('data', state.handlers.stdout);
  if (state.handlers.stderr) state.worker.stderr?.off('data', state.handlers.stderr);
  if (state.handlers.message) state.worker.off('message', state.handlers.message);
  if (state.handlers.error) state.worker.off('error', state.handlers.error);
  if (state.handlers.exit) state.worker.off('exit', state.handlers.exit);
  if (state.countedActive) {
    state.countedActive = false;
    lifecycleCounters.activeWorkerCount = Math.max(0, lifecycleCounters.activeWorkerCount - 1);
    const serverCounters = lifecycleCountersByServer.get(state.id);
    serverCounters.activeWorkerCount = Math.max(0, serverCounters.activeWorkerCount - 1);
  }
  lifecycleCounters.finalizeCount += 1;
  lifecycleCountersByServer.get(state.id).finalizeCount += 1;
  if (servers.get(state.id) === state) servers.delete(state.id);
  diagnostic('server_finalized', {
    serverID: state.id,
    generation: state.generation,
    state: result.state,
    forcedTermination: state.forcedTermination,
    code: result.code ?? null,
  });
}

function handleStdout(state, chunk) {
  if (state.finalized) return;
  state.pending = Buffer.concat([state.pending, chunk]);
  if (state.pending.length > maximumLine) {
    emit(state, 'lifecycle', { event: 'error', message: 'stdout line exceeded size limit' });
    void stopServerState(state, {
      expectedStop: false,
      forceImmediately: true,
      failure: new Error('stdout line exceeded size limit'),
    });
    return;
  }
  let newline;
  while ((newline = state.pending.indexOf(0x0a)) >= 0) {
    const line = state.pending.subarray(0, newline);
    state.pending = state.pending.subarray(newline + 1);
    if (!line.length) continue;
    try {
      JSON.parse(line.toString('utf8'));
      emit(state, 'stdout', { data: line.toString('base64') });
    } catch {
      emit(state, 'diagnostic', { message: redact(line.toString('utf8')).slice(0, 4096) });
    }
  }
}

function attachEvents(id, request, response) {
  response.writeHead(200, { 'Content-Type': 'application/x-ndjson', 'Cache-Control': 'no-store', Connection: 'keep-alive' });
  const state = servers.get(id);
  if (!state) { response.write(`${JSON.stringify({ channel: 'lifecycle', event: 'stopped' })}\n`); return response.end(); }
  state.clients.add(response);
  response.write(`${JSON.stringify({ channel: 'lifecycle', event: state.state })}\n`);
  for (const line of state.stdoutBacklog) response.write(line);
  state.stdoutBacklog = [];
  state.stdoutBacklogBytes = 0;
  request.on('close', () => state.clients.delete(response));
}

function finishEventClients(state, event) {
  for (const response of state.clients) {
    if (!response.writableEnded) {
      response.write(`${JSON.stringify({
        channel: 'lifecycle',
        serverID: state.id,
        generation: state.generation,
        event,
        timestamp: new Date().toISOString(),
      })}\n`);
      response.end();
    }
  }
  state.clients.clear();
}

function emit(state, channel, payload) {
  const line = `${JSON.stringify({ channel, serverID: state.id, timestamp: new Date().toISOString(), ...payload })}\n`;
  if (channel === 'stdout' && state.clients.size === 0) {
    state.stdoutBacklog.push(line);
    state.stdoutBacklogBytes += Buffer.byteLength(line);
    while (state.stdoutBacklogBytes > maximumLine && state.stdoutBacklog.length > 1) {
      state.stdoutBacklogBytes -= Buffer.byteLength(state.stdoutBacklog.shift());
    }
  }
  for (const response of state.clients) response.write(line);
  if (channel !== 'stdout') diagnostic(`server_${channel}`, { serverID: state.id, ...payload });
}

function emitGlobal(channel, payload) { diagnostic(channel, payload); }

async function sendLogs(id, response) {
  const state = servers.get(id);
  json(response, 200, { lines: state?.stderr ?? [] });
}

function snapshot(state) {
  return {
    id: state.id,
    generation: state.generation,
    state: state.state,
    startedAt: state.startedAt,
    modulePolicyHooksAvailable,
    resolvedModuleCount: state.moduleEdges.length,
    blockedAccesses: state.blockedAccesses,
    forcedTermination: state.forcedTermination,
  };
}

function stoppedSnapshot(id, generation = serverGenerations.get(id) ?? 0, state = 'stopped') {
  return {
    id,
    generation,
    state,
    startedAt: null,
    modulePolicyHooksAvailable,
    resolvedModuleCount: 0,
    blockedAccesses: [],
    forcedTermination: false,
  };
}

function lifecycleDiagnostics() {
  const activeByServer = Object.fromEntries(
    [...servers.entries()].map(([id, state]) => [id, {
      generation: state.generation,
      state: state.state,
      activeWorkerCount: state.finalized ? 0 : 1,
    }]),
  );
  return {
    ...lifecycleCounters,
    activeByServer,
    byServer: Object.fromEntries(lifecycleCountersByServer),
  };
}

function withTimeout(promise, milliseconds, message) {
  let timer;
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error(message)), milliseconds);
    }),
  ]).finally(() => clearTimeout(timer));
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
    resolve = value => {
      if (!settled) {
        settled = true;
        accept(value);
      }
    };
    reject = error => {
      if (!settled) {
        settled = true;
        decline(error);
      }
    };
  });
  return { promise, resolve, reject };
}

async function readJSON(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > maximumBody) throw new Error('Request body is too large.');
    chunks.push(chunk);
  }
  if (!chunks.length) return {};
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

function json(response, status, value) {
  if (response.writableEnded || response.destroyed) return;
  try {
    const body = JSON.stringify(value);
    response.writeHead(status, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body), 'Cache-Control': 'no-store' });
    response.end(body);
  } catch (error) {
    diagnostic('json_write_error', { message: redact(error.message) });
  }
}

function validID(value) { return /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value); }
function safeServerDirectory(id) { if (!validID(id)) throw new Error('Invalid server ID.'); return path.resolve(mcpPackagesRoot, id); }
function isInside(parent, child) { const relative = path.relative(path.resolve(parent), path.resolve(child)); return relative !== '..' && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative); }
function redact(value = '') { return String(value).replace(/(authorization|bearer|token|api[_-]?key|secret|password|cookie)\s*[:=]?\s*[^\s,;]+/gi, '$1=<redacted>'); }
function diagnostic(event, fields = {}) {
  const safeFields = Object.fromEntries(Object.entries(fields).map(([key, value]) => [key, redact(typeof value === 'string' ? value : JSON.stringify(value))]));
  const line = JSON.stringify({ timestamp: new Date().toISOString(), event, fields: safeFields });
  logStream.write(`${line}\n`);
  if (DEBUG) process.stderr.write(`${event}\n`);
}

process.on('uncaughtException', error => diagnostic('uncaught_exception', { message: redact(error.message) }));
process.on('unhandledRejection', error => diagnostic('unhandled_rejection', { message: redact(error?.message ?? error) }));
