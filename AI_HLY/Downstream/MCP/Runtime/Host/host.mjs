import http from 'node:http';
import { promises as fs, createWriteStream } from 'node:fs';
import path from 'node:path';
import { Worker } from 'node:worker_threads';
import { timingSafeEqual } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { commitInstall, installPackage, previewPackage, rollbackInstall } from './package-installer.mjs';

const [root, readyPath, launchToken, logPath, debugFlag] = process.argv.slice(2);
if (!root || !readyPath || !launchToken || !logPath) throw new Error('Missing host launch arguments.');
const DEBUG = debugFlag === '1';
const workerURL = new URL('./server-worker.mjs', import.meta.url);
const servers = new Map();
const installs = new Map();
const logStream = createWriteStream(logPath, { flags: 'a' });
const maximumBody = 10 * 1024 * 1024;
const maximumLine = 8 * 1024 * 1024;

await Promise.all(['runtime', 'registry', 'servers', 'staging', 'cache'].map(name => fs.mkdir(path.join(root, name), { recursive: true })));

const server = http.createServer(async (request, response) => {
  try {
    if (!authorized(request)) return json(response, 401, { error: 'Unauthorized' });
    const url = new URL(request.url, 'http://127.0.0.1');
    if (request.method === 'GET' && url.pathname === '/health') return json(response, 200, { ok: true });
    if (request.method === 'GET' && url.pathname === '/v1/runtime') {
      return json(response, 200, { nodeVersion: process.versions.node, protocolVersion: 1, workers: [...servers.values()].map(snapshot) });
    }
    if (request.method === 'POST' && url.pathname === '/v1/install/preview') {
      const body = await readJSON(request);
      return json(response, 200, await previewPackage(body.source, { entryPointOverride: body.entryPointOverride }));
    }
    if (request.method === 'POST' && url.pathname === '/v1/install') {
      const body = await readJSON(request);
      const controller = new AbortController();
      installs.set(body.operationID, controller);
      try {
        const descriptor = await installPackage({
          root,
          operationID: body.operationID,
          serverID: body.serverID,
          source: body.source,
          entryPointOverride: body.entryPointOverride,
          signal: controller.signal,
          emit: (channel, data) => emitGlobal(channel, data),
        });
        return json(response, 200, descriptor);
      } finally {
        installs.delete(body.operationID);
      }
    }
    if (request.method === 'POST' && url.pathname === '/v1/install/cancel') {
      const body = await readJSON(request);
      installs.get(body.operationID)?.abort(new Error('Installation cancelled.'));
      return json(response, 200, { cancelled: true });
    }
    if (request.method === 'POST' && url.pathname === '/v1/install/commit') {
      const body = await readJSON(request);
      await commitInstall({ root, operationID: body.operationID, serverID: body.serverID });
      return json(response, 200, { committed: true });
    }
    if (request.method === 'POST' && url.pathname === '/v1/install/rollback') {
      const body = await readJSON(request);
      await rollbackInstall({ root, operationID: body.operationID, serverID: body.serverID });
      return json(response, 200, { rolledBack: true });
    }

    const match = url.pathname.match(/^\/v1\/servers\/([0-9a-f-]+)(?:\/(start|stop|restart|stdin|events|logs))?$/i);
    if (!match || !validID(match[1])) return json(response, 404, { error: 'Not found' });
    const id = match[1].toLowerCase();
    const action = match[2];
    if (request.method === 'POST' && action === 'start') return json(response, 200, await startServer(id, await readJSON(request)));
    if (request.method === 'POST' && action === 'stop') { await stopServer(id); return json(response, 200, { state: 'stopped' }); }
    if (request.method === 'POST' && action === 'restart') {
      const body = await readJSON(request); await stopServer(id); return json(response, 200, await startServer(id, body));
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
    if (!response.headersSent) json(response, error.name === 'AbortError' ? 499 : 400, { error: redact(error.message) });
    else response.end();
  }
});

server.listen(0, '127.0.0.1', async () => {
  const address = server.address();
  const ready = { port: address.port, nodeVersion: process.versions.node, protocolVersion: 1 };
  const temporary = `${readyPath}.tmp`;
  await fs.writeFile(temporary, JSON.stringify(ready), { mode: 0o600 });
  await fs.rename(temporary, readyPath);
  diagnostic('host_ready', { port: address.port, nodeVersion: process.versions.node });
});

function authorized(request) {
  const expected = Buffer.from(`Bearer ${launchToken}`);
  const actual = Buffer.from(request.headers.authorization ?? '');
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

async function startServer(id, configuration) {
  if (servers.has(id)) return snapshot(servers.get(id));
  if (configuration.serverID?.toLowerCase() !== id) throw new Error('Server ID mismatch.');
  const packageRoot = path.resolve(configuration.packageRoot);
  const allowedRoot = safeServerDirectory(id);
  if (!isInside(allowedRoot, packageRoot)) throw new Error('Package root is outside the installed server directory.');
  const entryPoint = path.resolve(configuration.entryPoint);
  if (!isInside(packageRoot, entryPoint)) throw new Error('Entry point is outside package root.');

  const state = { id, state: 'starting', worker: null, clients: new Set(), stderr: [], pending: Buffer.alloc(0), startedAt: new Date().toISOString() };
  const worker = new Worker(workerURL, {
    workerData: { serverID: id, packageRoot, entryPoint },
    argv: Array.isArray(configuration.arguments) ? configuration.arguments : [],
    env: { ...process.env, ...(configuration.environment ?? {}), HANLIN_MCP_SERVER_ID: id },
    stdin: true,
    stdout: true,
    stderr: true,
  });
  state.worker = worker;
  servers.set(id, state);
  worker.stdout.on('data', chunk => handleStdout(state, chunk));
  worker.stderr.on('data', chunk => {
    const message = redact(chunk.toString('utf8')).slice(0, maximumLine);
    state.stderr.push(message);
    if (state.stderr.length > 500) state.stderr.shift();
    emit(state, 'stderr', { text: message });
  });
  worker.on('message', message => {
    if (message?.type === 'loaded') { state.state = 'running'; emit(state, 'lifecycle', { event: 'server-ready' }); }
  });
  worker.on('error', error => { state.state = 'failed'; emit(state, 'lifecycle', { event: 'error', message: redact(error.message) }); });
  worker.on('exit', code => { state.state = code === 0 ? 'stopped' : 'failed'; emit(state, 'lifecycle', { event: 'exit', code }); servers.delete(id); });
  return snapshot(state);
}

async function stopServer(id) {
  const state = servers.get(id);
  if (!state) return;
  state.worker.stdin?.end();
  await state.worker.terminate();
  for (const client of state.clients) client.end();
  servers.delete(id);
}

function handleStdout(state, chunk) {
  state.pending = Buffer.concat([state.pending, chunk]);
  if (state.pending.length > maximumLine) {
    emit(state, 'lifecycle', { event: 'error', message: 'stdout line exceeded size limit' });
    state.worker.terminate();
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

function snapshot(state) { return { id: state.id, state: state.state, startedAt: state.startedAt }; }

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
function safeServerDirectory(id) { if (!validID(id)) throw new Error('Invalid server ID.'); return path.resolve(root, 'servers', id); }
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
