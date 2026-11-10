import { createHash, randomUUID } from 'node:crypto';
import { promises as fs, createWriteStream, createReadStream, readFileSync } from 'node:fs';
import path from 'node:path';
import { finished } from 'node:stream/promises';
import { Worker } from 'node:worker_threads';

const terminalStates = new Set(['completed', 'failed', 'cancelled', 'interrupted']);
const validID = id => typeof id === 'string' && /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(id);

/** Durable job headers and full stdout/stderr; preview/page budgets never discard log files. */
export class ExecutionJobs {
  #jobs = new Map();
  #writes = new Map();
  constructor({ root, workerURL, diagnosticWorkerURL, globalNodeModules }) {
    this.root = root;
    this.workerURL = workerURL;
    this.diagnosticWorkerURL = diagnosticWorkerURL;
    this.globalNodeModules = globalNodeModules;
    // Freeze launch environment before another native engine temporarily mutates C environ.
    this.workerEnvironment = Object.freeze({ ...process.env });
  }

  async initialize() {
    await fs.mkdir(this.root, { recursive: true, mode: 0o700 });
    for (const id of await fs.readdir(this.root)) {
      if (!validID(id)) continue;
      let header;
      try { header = JSON.parse(await fs.readFile(path.join(this.root, id, 'job.json'), 'utf8')); }
      catch { continue; } // An interrupted atomic write is not proof of a completed job.
      if (header.executionID !== id) continue;
      header.result = null; // Retained on disk; do not load every historical preview into RAM.
      if (!terminalStates.has(header.state)) {
        header.state = 'interrupted';
        header.error = 'The app process ended before this job completed. Existing output is retained; side effects are not replayed.';
        await this.#persist(header);
      }
      this.#jobs.set(id, { header });
    }
  }

  get activeCount() { return [...this.#jobs.values()].filter(job => !terminalStates.has(job.header.state)).length; }
  snapshot(id) {
    const header = this.#jobs.get(id)?.header;
    if (!header) return null;
    if (terminalStates.has(header.state) && !header.result) {
      return JSON.parse(readFileSync(path.join(this.root, id, 'job.json'), 'utf8'));
    }
    return structuredClone(header);
  }

  async start(body) {
    const id = String(body.executionID ?? randomUUID()).toLowerCase();
    if (!validID(id)) throw new Error('Invalid execution ID.');
    if (this.#jobs.has(id)) throw Object.assign(new Error('This execution ID already exists; jobs are never replayed implicitly.'), { status: 409 });
    const timeout = body.timeoutMilliseconds;
    if (timeout != null && (!Number.isSafeInteger(timeout) || timeout <= 0 || !Number.isSafeInteger(Date.now() + timeout))) {
      throw new Error('timeoutMilliseconds must be a positive representable integer, or omitted for no deadline.');
    }
    const previewBytes = body.maximumOutputBytes ?? 1_048_576;
    if (!Number.isSafeInteger(previewBytes) || previewBytes < 1) throw new Error('maximumOutputBytes must be a positive integer preview budget.');
    const directory = path.join(this.root, id);
    await fs.mkdir(directory, { mode: 0o700 });
    const header = { executionID: id, state: 'queued', startedAt: Date.now(), cancellationRequested: false, stdoutBytes: 0, stderrBytes: 0, result: null };
    const job = { header, startedContinuous: performance.now(), worker: null, completion: null, cancel: null };
    this.#jobs.set(id, job);
    await this.#persist(header);
    job.completion = this.#run(job, body, previewBytes, timeout).catch(async error => {
      await job.worker?.terminate().catch(() => {});
      for (const stream of Object.values(job.streams ?? {})) stream.destroy();
      header.state = 'failed';
      header.error = String(error.message ?? error);
      await this.#persist(header).catch(() => {});
      return header;
    }).then(() => { job.completion = null; });
    return header;
  }

  async wait(id) {
    const job = this.#jobs.get(id);
    if (!job) return null;
    if (job.completion) await job.completion;
    return this.snapshot(id);
  }

  async cancel(id) {
    const job = this.#jobs.get(id);
    if (!job || terminalStates.has(job.header.state)) return job?.header ?? null;
    job.header.cancellationRequested = true;
    await this.#persist(job.header);
    if (job.cancel) await job.cancel();
    return job.header;
  }

  async readOutput(id, channel, offset = 0, limit = 16_384) {
    if (!this.#jobs.has(id) || !['stdout', 'stderr'].includes(channel)) return null;
    if (!Number.isSafeInteger(offset) || offset < 0 || !Number.isSafeInteger(limit) || limit < 1) throw new Error('Invalid output page.');
    let file;
    try { file = await fs.open(path.join(this.root, id, channel + '.log'), 'r'); }
    catch (error) {
      if (error.code !== 'ENOENT') throw error;
      return { executionID: id, channel, offset, nextOffset: offset, totalBytes: 0, hasMore: false, base64: '' };
    }
    try {
      const total = (await file.stat()).size;
      const buffer = Buffer.alloc(Math.min(limit, 65_536, Math.max(0, total - offset)));
      const { bytesRead } = await file.read(buffer, 0, buffer.length, offset);
      const bytes = buffer.subarray(0, bytesRead);
      // Base64 is lossless even for a byte page splitting UTF-8 or binary stdout.
      return { executionID: id, channel, offset, nextOffset: offset + bytesRead, totalBytes: total, hasMore: offset + bytesRead < total, base64: bytes.toString('base64') };
    } finally { await file.close(); }
  }

  async #persist(header) {
    const file = path.join(this.root, header.executionID, 'job.json');
    const contents = JSON.stringify(header);
    const previous = this.#writes.get(header.executionID) ?? Promise.resolve();
    const write = previous.catch(() => {}).then(async () => {
      await fs.writeFile(file + '.tmp', contents, { mode: 0o600 });
      await fs.rename(file + '.tmp', file);
    });
    this.#writes.set(header.executionID, write);
    try { await write; }
    finally { if (this.#writes.get(header.executionID) === write) this.#writes.delete(header.executionID); }
  }

  async #run(job, body, previewBytes, timeout) {
    const { header } = job;
    const directory = path.join(this.root, header.executionID);
    const extension = body.moduleKind === 'commonjs' ? 'cjs' : 'mjs';
    const cli = body.executionMode === 'cli';
    const entryPoint = cli ? await fs.realpath(body.entryPoint) : path.join(directory, `main.${extension}`);
    if (cli) {
      if (!(await fs.stat(entryPoint)).isFile()) throw new Error('The CLI entry must be an existing regular file.');
    } else await fs.writeFile(entryPoint, body.source, { mode: 0o600 });
    if (this.globalNodeModules) {
      try { await fs.access(this.globalNodeModules); await fs.symlink(this.globalNodeModules, path.join(directory, 'node_modules'), 'dir'); }
      catch (error) { if (error.code !== 'ENOENT') throw error; }
    }
    const streams = {};
    job.streams = streams;
    const hashes = {};
    const previews = { stdout: [], stderr: [] };
    let acceptedBytes = 0;
    let outputWasTruncated = false;
    let ioError = null;
    for (const channel of ['stdout', 'stderr']) {
      streams[channel] = createWriteStream(path.join(directory, channel + '.log'), { mode: 0o600 });
      hashes[channel] = createHash('sha256');
      streams[channel].on('error', error => { ioError = error; void job.cancel?.(); });
    }
    const workerURL = body.environment?.HANLIN_NODE_TRACE_WARNINGS === '1' && this.diagnosticWorkerURL ? this.diagnosticWorkerURL : this.workerURL;
    const environment = { ...this.workerEnvironment, ...body.environment };
    if (cli) {
      // Internal bootstrap is separate from the CLI's user environment. A job
      // cannot replace the preload needed to establish its virtual cwd.
      environment.NODE_OPTIONS = [this.workerEnvironment.NODE_OPTIONS,
        '--import ' + new URL('./cli-preload.mjs', import.meta.url).href].filter(Boolean).join(' ');
    }
    const worker = new Worker(cli ? entryPoint : workerURL, {
      workerData: { entryPoint, workspace: body.workspace, moduleKind: body.moduleKind, arguments: body.arguments ?? [], environment: body.environment ?? {}, maximumOutputBytes: previewBytes },
      stdout: true, stderr: true, stdin: cli,
      env: environment, argv: cli ? (body.arguments ?? []).map(String) : [],
      // Keep Node's FD tracking enabled. Disabling it would conceal ownership regressions.
    });
    job.worker = worker;
    header.state = 'running';
    for (const channel of ['stdout', 'stderr']) {
      worker[channel].on('data', chunk => {
        hashes[channel].update(chunk);
        header[channel + 'Bytes'] += chunk.length;
        const end = Math.min(chunk.length, Math.max(0, previewBytes - acceptedBytes));
        if (end) previews[channel].push(chunk.subarray(0, end));
        acceptedBytes += end;
        if (end < chunk.length) outputWasTruncated = true;
      });
      worker[channel].pipe(streams[channel]);
    }
    let timer;
    let didTimeOut = false;
    let message;
    let workerError;
    if (cli) {
      worker.stdin.on('error', error => { if (error.code !== 'EPIPE' && error.code !== 'ERR_STREAM_DESTROYED') workerError = error; });
      if (body.standardInputPath) {
        const input = createReadStream(body.standardInputPath);
        input.once('error', error => { workerError = error; void job.cancel?.(); });
        worker.once('exit', () => input.destroy());
        input.pipe(worker.stdin);
      } else worker.stdin.end();
    }
    job.cancel = async () => { await worker.terminate(); };
    const deadline = timeout == null ? null : job.startedContinuous + timeout;
    const armDeadline = () => {
      const remaining = deadline - performance.now();
      if (remaining <= 0) { didTimeOut = true; void job.cancel(); }
      else timer = setTimeout(armDeadline, Math.min(remaining, 2_147_483_647));
    };
    if (deadline != null) armDeadline();
    const exited = new Promise(resolve => {
      // Module evaluation may finish before timers/stdio. Let Node's actual event loop
      // complete naturally; only an explicit deadline/cancellation terminates a worker.
      worker.on('message', value => {
        if (!cli && (value?.type === 'completed' || value?.type === 'failed')) message = value;
      });
      worker.once('error', error => { workerError = error; });
      worker.once('exit', resolve);
      if (header.cancellationRequested) void job.cancel();
    });
    await this.#persist(header);
    const exitCode = await exited;
    clearTimeout(timer);
    await Promise.all(Object.values(streams).map(stream => finished(stream)));
    const wasCancelled = header.cancellationRequested;
    const failed = ioError || workerError || message?.type === 'failed' || exitCode !== 0;
    header.state = wasCancelled ? 'cancelled' : didTimeOut || failed ? 'failed' : 'completed';
    header.error = ioError?.message ?? workerError?.message ?? (didTimeOut ? 'Execution timed out.' : null);
    const files = Object.fromEntries(['stdout', 'stderr'].map(channel => [channel, { path: path.join(directory, channel + '.log'), bytes: header[channel + 'Bytes'], sha256: hashes[channel].digest('hex') }]));
    const preview = channel => {
      const bytes = Buffer.concat(previews[channel]);
      let end = bytes.length;
      if (end) {
        let start = end - 1;
        while (start > 0 && (bytes[start] & 0xc0) === 0x80) start--;
        const lead = bytes[start];
        const required = lead >= 0xf0 ? 4 : lead >= 0xe0 ? 3 : lead >= 0xc0 ? 2 : 1;
        if (end - start < required) end = start;
      }
      return bytes.subarray(0, end).toString('utf8');
    };
    header.result = {
      executionID: header.executionID, stdout: preview('stdout'), stderr: preview('stderr'),
      value: message?.value ?? null, exitCode: header.state === 'completed' ? 0 : (Number.isInteger(exitCode) && exitCode !== 0 ? exitCode : 1),
      durationMilliseconds: Math.round(performance.now() - job.startedContinuous), didTimeOut, wasCancelled,
      outputWasTruncated, outputFiles: files,
    };
    if (header.error) header.result.stderr += '\n' + header.error;
    header.completedAt = Date.now();
    job.worker = null;
    job.cancel = null;
    await this.#persist(header);
    header.result = null;
    return this.snapshot(header.executionID);
  }
}
