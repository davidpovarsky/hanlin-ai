import { promises as fs } from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';

const validID = id => typeof id === 'string' && /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(id);
const canonical = value => Array.isArray(value) ? value.map(canonical) : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map(key=>[key,canonical(value[key])])) : value;
const digest = value => createHash('sha256').update(JSON.stringify(canonical(value))).digest('hex');

/** One live parent job, durable receipts; a restarted Host never replays work. */
export class RuntimeCommandBroker {
  #pending = new Map();
  #writes = Promise.resolve();
  #completing = Promise.resolve();
  #timer;
  #checking = false;
  constructor({ directory, port, parentExecutionID, onAvailable = () => {} }) {
    this.onAvailable = onAvailable;
    this.directory = directory;
    this.port = port;
    this.parentExecutionID = parentExecutionID;
    this.cancellationRequested = false;
    port.on('message', message => {
      this.#writes = this.#writes.then(() => this.#enqueue(message)).catch(error => {
        port.postMessage({ id: message?.id, error: String(error.message ?? error) });
      });
    });
    port.unref();
    this.#timer = setInterval(() => { void this.#collectResponses(); }, 50);
    this.#timer.unref();
  }
  async #write(id, name, value) {
    const file = path.join(this.directory, id, name + '.json');
    await fs.writeFile(file + '.tmp', JSON.stringify(value), { mode: 0o600 });
    await fs.rename(file + '.tmp', file);
  }
  async #enqueue(message) {
    if (this.cancellationRequested) throw new Error('The parent execution was cancelled.');
    if (!validID(message?.id) || typeof message.command !== 'string' || !Array.isArray(message.arguments)
        || !message.arguments.every(item => typeof item === 'string') || typeof message.cwd !== 'string'
        || !message.environment || typeof message.environment !== 'object' || Array.isArray(message.environment)
        || !Object.entries(message.environment).every(([name,value])=>name.length>0 && !name.includes('=') && !name.includes('\0') && typeof value==='string' && !value.includes('\0'))
        || (message.engine != null && !['node','python','shell'].includes(message.engine))
        || (message.entryPoint != null && (typeof message.entryPoint!=='string' || message.entryPoint.includes('\0')))) {
      throw new Error('Malformed runtime command request.');
    }
    const directory = path.join(this.directory, message.id);
    const input = path.join(directory, 'stdin');
    if (message.standardInputPath !== input || !(await fs.stat(input)).isFile()) throw new Error('Invalid command input artifact.');
    const record = { ...message, parentExecutionID: this.parentExecutionID, state: 'queued', cancellationRequested: false };
    // wx receipt prevents duplicate IDs from replacing a request with side effects.
    const receipt = path.join(directory, 'request.json');
    await fs.writeFile(receipt, JSON.stringify(record), { flag: 'wx', mode: 0o600 });
    let release;
    const done = new Promise(resolve => { release = resolve; });
    this.#pending.set(message.id, { record, done, release });
    this.onAvailable();
  }
  async requests() {
    await this.#writes;
    return [...this.#pending.values()].map(operation => ({ ...operation.record }));
  }
  complete(id, result) {
    const next = this.#completing.catch(() => {}).then(() => this.#complete(id, result));
    this.#completing = next.catch(() => {});
    return next;
  }
  async #complete(id, result) {
    await this.#writes;
    if (!validID(id) || !result || !Number.isInteger(result.exitCode)) throw new Error('Invalid command completion.');
    const operation = this.#pending.get(id);
    const file = path.join(this.directory, id, 'result.json');
    if (!operation) {
      const previous = JSON.parse(await fs.readFile(file, 'utf8'));
      if (previous.digest !== digest(result)) throw new Error('Conflicting command completion; execution is not replayed.');
      return;
    }
    await this.#write(id, 'result', { digest: digest(result), result });
    this.port.postMessage({ id, result });
    this.#pending.delete(id);
    operation.release();
  }
  async #collectResponses() {
    if (this.#checking) return;
    this.#checking = true;
    try {
      await this.#writes;
      for (const [id, operation] of this.#pending) {
        try {
          const result = JSON.parse(await fs.readFile(path.join(this.directory, id, 'response.json'), 'utf8'));
          await this.complete(id, result);
        } catch (error) {
          if (error.code === 'ENOENT') continue;
          await this.#write(id, 'failure', { error: String(error.message ?? error) }).catch(() => {});
          this.port.postMessage({ id, error: String(error.message ?? error) });
          this.#pending.delete(id);
          operation.release();
        }
      }
    } finally { this.#checking = false; }
  }
  async fail(id, error) {
    await this.#writes;
    const operation = this.#pending.get(id);
    if (!operation) return;
    const message = String(error);
    await this.#write(id, 'failure', { error: message }).catch(() => {});
    this.port.postMessage({ id, error: message });
    this.#pending.delete(id);
    operation.release();
  }
  async cancel() {
    this.cancellationRequested = true;
    await this.#writes;
    for (const operation of this.#pending.values()) {
      operation.record.cancellationRequested = true;
      await this.#write(operation.record.id, 'request', operation.record);
    }
  }
  async drain() {
    await this.#writes;
    await Promise.all([...this.#pending.values()].map(operation => operation.done));
    await this.#completing;
    clearInterval(this.#timer);
    this.port.close();
  }
}
