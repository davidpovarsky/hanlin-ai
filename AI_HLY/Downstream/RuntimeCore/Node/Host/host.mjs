import http from 'node:http';
import { promises as fs, createWriteStream, mkdirSync } from 'node:fs';
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
const { commitGlobalPackage, installGlobalPackage, listGlobalPackages, previewGlobalPackage, rollbackGlobalPackage, stageGlobalPackage, uninstallGlobalPackage } =
  await import('./global-package-manager.mjs');

const workerURL = new URL('./server-worker.mjs', import.meta.url);
const executionWorkerURL = new URL('./execution-worker.mjs', import.meta.url);
const servers = new Map();
const serverRestarts = new Map();
const serverGenerations = new Map();
const executions = new Map();
const installs = new Map();
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
    if (request.method === 'GET' && url.pathname === '/health') return json(response, 200, { ok: true, nodeVersion: process.versions.node, protocolVersion: 2, modulePolicyHooksAvailable });
    if (request.method === 'GET' && url.pathname === '/v1/runtime') {
      return json(response, 200, {
        nodeVersion: process.versions.node,
        protocolVersion: 2,
        modulePolicyHooksAvailable,
        workers: [...servers.values()].map(snapshot),
        executions: executions.size,
        lifecycle: lifecycleDiagnostics(),
      });
    }
    if (request.method === 'POST' && url.pathname === '/v1/executions') {
      return json(response, 200, await executeJavaScript(await readJSON(request)));
    }
    const executionCancel = url.pathname.match(/^\/v1\/executions\/([0-9a-f-]+)\/cancel$/i);
    if (request.method === 'POST' && executionCancel) {
      const state = executions.get(executionCancel[1].toLowerCase());
      if (state) { state.cancelled = true; await state.worker.terminate(); }
      return json(response, 200, { cancelled: Boolean(state) });
    }
    if (request.method === 'POST' && url.pathname === '/v1/typescript/compile') {
      return json(response, 200, await compileTypeScript(await readJSON(request)));
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
    if (request.method === 'POST' && url.pathname === '/v1/packages/node/install') {
      const body = await readJSON(request);
      return json(response, 200, await installGlobalPackage({ root, name: body.name, version: body.version }));
    }
    if (request.method === 'POST' && url.pathname === '/v1/packages/node/stage') {
      const body = await readJSON(request);
      return json(response, 200, await stageGlobalPackage({ root, name: body.name, version: body.version }));
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
      return json(response, 200, { progress: installProgress.get(operationID) ?? null });
    }
    if (request.method === 'POST' && url.pathname === '/v1/install/preview') {
      const body = await readJSON(request);
      return json(response, 200, await previewPackage(body.source, { root, entryPointOverride: body.entryPointOverride }));
    }
    if (request.method === 'POST' && url.pathname === '/v1/install') {
      const body = await readJSON(request);
      const controller = new AbortController();
      installs.set(body.operationID, controller);
      installProgress.set(body.operationID, {
        operationID: body.operationID,
        phase: 'resolving',
        fraction: 0,
      });
      try {
        try {
          const descriptor = await installPackage({
            root,
            operationID: body.operationID,
            serverID: body.serverID,
            source: body.source,
            entryPointOverride: body.entryPointOverride,
            arguments: body.arguments,
            signal: controller.signal,
            emit: (channel, data) => {
              if (channel === 'install') installProgress.set(body.operationID, data);
              emitGlobal(channel, data);
            },
          });
          return json(response, 200, descriptor);
        } catch (error) {
          error.operationID = body.operationID;
          const prior = installProgress.get(body.operationID);
          installProgress.set(body.operationID, {
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
      } finally {
        installs.delete(body.operationID);
      }
    }
    if (request.method === 'POST' && url.pathname === '/v1/install/cancel') {
      const body = await readJSON(request);
      installs.get(body.operationID)?.abort(new Error('Installation cancelled.'));
      installProgress.delete(body.operationID);
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
      if (!state || state.finalized || state.stdinEnded) {
        return json(response, 409, { error: 'Server is not running' });
      }
      const data = Buffer.from(body.data ?? '', 'base64');
      if (data.length > maximumLine) return json(response, 413, { error: 'Input is too large' });
      state.worker.postMessage({ type: 'stdio-input', data });
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
    if (!response.headersSent) json(response, error.name === 'AbortError' ? 499 : 400, {
      error: redact(error.message),
      operationID: error.operationID ?? null,
      code: error.code ?? null,
    });
    else response.end();
  }
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
  const id = String(body.executionID ?? '').toLowerCase();
  if (!validID(id)) throw new Error('Invalid execution ID.');
  if (typeof body.source !== 'string' || Buffer.byteLength(body.source) > maximumBody) throw new Error('JavaScript source is missing or too large.');
  if (!['esm', 'commonjs'].includes(body.moduleKind)) throw new Error('Unsupported JavaScript module kind.');
  const workspace = path.resolve(String(body.workspace ?? ''));
  if (!isInside(clientsRoot, workspace)) throw new Error('Execution workspace is outside RuntimeCore clients.');
  const stat = await fs.lstat(workspace);
  if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error('Execution workspace must be a real directory.');
  rejectUnsafeSource(body.source);
  const executionRoot = path.join(workspace, '.hanlin-executions', id);
  await fs.rm(executionRoot, { recursive: true, force: true });
  await fs.mkdir(executionRoot, { recursive: true });
  const globalNodeModules = path.join(root, 'packages', 'node-global', 'node_modules');
  try { await fs.access(globalNodeModules); await fs.symlink(globalNodeModules, path.join(executionRoot, 'node_modules'), 'dir'); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  const extension = body.moduleKind === 'commonjs' ? 'cjs' : 'mjs';
  const entryPoint = path.join(executionRoot, `main.${extension}`);
  await fs.writeFile(entryPoint, body.source, { mode: 0o600 });
  const maximumOutputBytes = Math.min(Math.max(Number(body.maximumOutputBytes) || 1_048_576, 1024), 8 * 1024 * 1024);
  const timeoutMilliseconds = Math.min(Math.max(Number(body.timeoutMilliseconds) || 30_000, 1000), 300_000);
  const started = Date.now();
  const state = { worker: null, cancelled: false };
  const result = await new Promise(resolve => {
    const worker = new Worker(executionWorkerURL, {
      workerData: {
        entryPoint,
        moduleKind: body.moduleKind,
        arguments: Array.isArray(body.arguments) ? body.arguments : [],
        environment: validatedEnvironment(body.environment),
        maximumOutputBytes,
      },
    });
    state.worker = worker;
    executions.set(id, state);
    let settled = false;
    const finish = value => { if (!settled) { settled = true; clearTimeout(timer); resolve(value); } };
    const timer = setTimeout(async () => {
      await worker.terminate();
      finish({ executionID: id, stdout: '', stderr: 'Execution timed out.\n', value: null, exitCode: null, didTimeOut: true, wasCancelled: false, outputWasTruncated: false });
    }, timeoutMilliseconds);
    worker.once('message', message => finish({
      executionID: id,
      stdout: message.stdout ?? '',
      stderr: message.stderr ?? '',
      value: message.value ?? null,
      exitCode: message.type === 'completed' ? 0 : 1,
      didTimeOut: false,
      wasCancelled: state.cancelled,
      outputWasTruncated: Boolean(message.outputWasTruncated),
    }));
    worker.once('error', error => finish({ executionID: id, stdout: '', stderr: `${redact(error.stack ?? error.message)}\n`, value: null, exitCode: 1, didTimeOut: false, wasCancelled: state.cancelled, outputWasTruncated: false }));
    worker.once('exit', code => { if (state.cancelled) finish({ executionID: id, stdout: '', stderr: '', value: null, exitCode: code, didTimeOut: false, wasCancelled: true, outputWasTruncated: false }); });
  });
  executions.delete(id);
  await fs.rm(executionRoot, { recursive: true, force: true });
  result.durationMilliseconds = Date.now() - started;
  return result;
}

async function compileTypeScript(body) {
  if (typeof body.source !== 'string' || Buffer.byteLength(body.source) > maximumBody) throw new Error('TypeScript source is missing or too large.');
  const ts = await import('typescript');
  const baseOptions = {
    target: ts.ScriptTarget.ES2022,
    module: ts.ModuleKind.ESNext,
    moduleResolution: ts.ModuleResolutionKind.Bundler,
    strict: true,
    sourceMap: true,
    inlineSources: true,
  };
  const converted = ts.convertCompilerOptionsFromJson(body.tsconfig?.compilerOptions ?? {}, '.');
  const result = ts.transpileModule(body.source, {
    fileName: typeof body.fileName === 'string' ? body.fileName : 'main.ts',
    compilerOptions: { ...baseOptions, ...converted.options },
    reportDiagnostics: true,
  });
  const diagnostics = [...(converted.errors ?? []), ...(result.diagnostics ?? [])].map(diagnostic => {
    const position = diagnostic.file && typeof diagnostic.start === 'number' ? diagnostic.file.getLineAndCharacterOfPosition(diagnostic.start) : null;
    return { code: diagnostic.code, category: diagnostic.category, message: ts.flattenDiagnosticMessageText(diagnostic.messageText, '\n'), line: position ? position.line + 1 : null, column: position ? position.character + 1 : null };
  });
  const failed = diagnostics.some(item => item.category === ts.DiagnosticCategory.Error);
  return { javaScript: failed ? null : result.outputText, sourceMap: failed ? null : result.sourceMapText ?? null, diagnostics: diagnostics.map(({ category, ...item }) => item), succeeded: !failed };
}

async function compileTypeScriptProject(body) {
  const workspace = path.resolve(String(body.workspace ?? ''));
  if (!isInside(clientsRoot, workspace)) throw new Error('TypeScript lifecycle workspace is outside RuntimeCore clients.');
  const args = Array.isArray(body.arguments) ? body.arguments.map(String) : [];
  if (args.length > 128 || args.some(argument => /[\0\r\n]/.test(argument))) throw new Error('Invalid TypeScript lifecycle arguments.');
  const ts = await import('typescript');
  const commandLine = ts.parseCommandLine(args);
  const diagnostics = [...commandLine.errors];
  const requestedProject = commandLine.options.project;
  const configPath = requestedProject
    ? path.resolve(workspace, requestedProject)
    : ts.findConfigFile(workspace, ts.sys.fileExists, 'tsconfig.json');
  if (!configPath || !isInside(workspace, configPath)) throw new Error('A tsconfig.json inside the package workspace is required.');
  const config = ts.readConfigFile(configPath, ts.sys.readFile);
  if (config.error) diagnostics.push(config.error);
  const parsed = ts.parseJsonConfigFileContent(config.config ?? {}, ts.sys, path.dirname(configPath), commandLine.options, configPath);
  diagnostics.push(...parsed.errors);
  const emittedFiles = [];
  if (!diagnostics.some(item => item.category === ts.DiagnosticCategory.Error)) {
    const program = ts.createProgram({ rootNames: parsed.fileNames, options: parsed.options, projectReferences: parsed.projectReferences });
    diagnostics.push(...ts.getPreEmitDiagnostics(program));
    if (!diagnostics.some(item => item.category === ts.DiagnosticCategory.Error)) {
      const emit = program.emit(undefined, (fileName, data, writeByteOrderMark) => {
        const destination = path.resolve(fileName);
        if (!isInside(workspace, destination)) throw new Error(`TypeScript output escapes the package workspace: ${fileName}`);
        mkdirSync(path.dirname(destination), { recursive: true });
        ts.sys.writeFile(destination, data, writeByteOrderMark);
        emittedFiles.push(path.relative(workspace, destination));
      });
      diagnostics.push(...emit.diagnostics);
    }
  }
  const normalized = diagnostics.map(diagnostic => {
    const position = diagnostic.file && typeof diagnostic.start === 'number' ? diagnostic.file.getLineAndCharacterOfPosition(diagnostic.start) : null;
    return { code: diagnostic.code, message: ts.flattenDiagnosticMessageText(diagnostic.messageText, '\n'), line: position ? position.line + 1 : null, column: position ? position.character + 1 : null };
  });
  return { diagnostics: normalized, emittedFiles, succeeded: !diagnostics.some(item => item.category === ts.DiagnosticCategory.Error) };
}

function validatedEnvironment(value) {
  const output = {};
  if (!value || typeof value !== 'object' || Array.isArray(value)) return output;
  for (const [name, item] of Object.entries(value)) {
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) throw new Error(`Invalid environment name: ${name}`);
    if (['HOME', 'USERPROFILE', 'PATH', 'TMPDIR', 'TMP', 'TEMP', 'XDG_CACHE_HOME', 'NODE_PATH', 'NPM_CONFIG_CACHE', 'NPM_CONFIG_PREFIX', 'PYTHONHOME', 'PYTHONPATH'].includes(name.toUpperCase())) throw new Error(`Reserved environment name: ${name}`);
    output[name] = String(item);
  }
  return output;
}

function rejectUnsafeSource(source) {
  if (/\b(?:child_process|cluster)\b/.test(source)) throw new Error('This script requests an unavailable process API.');
  if (/\b(?:docker|sudo)\b/.test(source) || /curl\s+[^\n|]+\|\s*(?:sh|bash)/.test(source)) throw new Error('This script requests an unsupported executable chain.');
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
  const packageRoot = path.resolve(configuration.packageRoot);
  const allowedRoot = safeServerDirectory(id);
  if (!isInside(allowedRoot, packageRoot)) throw new Error('Package root is outside the installed server directory.');
  const entryPoint = path.resolve(configuration.entryPoint);
  if (!isInside(packageRoot, entryPoint)) throw new Error('Entry point is outside package root.');

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
    workerData: { serverID: id, packageRoot, entryPoint },
    argv: Array.isArray(configuration.arguments) ? configuration.arguments : [],
    env: { ...process.env, ...(configuration.environment ?? {}), HANLIN_MCP_SERVER_ID: id },
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
  state.handlers.stderr = chunk => {
    const message = redact(chunk.toString('utf8')).slice(0, maximumLine);
    state.stderr.push(message);
    if (state.stderr.length > 500) state.stderr.shift();
    emit(state, 'stderr', { text: message });
  };
  state.handlers.message = message => {
    if (message?.type === 'stdio-output') {
      const chunk = Buffer.from(message.data);
      if (message.channel === 'stderr') state.handlers.stderr(chunk);
      else handleStdout(state, chunk);
      return;
    }
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
      try { state.worker.postMessage({ type: 'stdio-end' }); } catch (error) {
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
  state.stderr = [];
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
  const body = JSON.stringify(value);
  response.writeHead(status, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body), 'Cache-Control': 'no-store' });
  response.end(body);
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
