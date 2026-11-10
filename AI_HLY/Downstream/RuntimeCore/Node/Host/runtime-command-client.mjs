import { workerData } from 'node:worker_threads';
import { randomUUID } from 'node:crypto';
import { promises as fs, createReadStream, createWriteStream } from 'node:fs';
import path from 'node:path';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { resolveRuntimeCommand } from './runtime-command-resolution.mjs';

let connected = false;
const pending = new Map();

/** Private transferred MessagePort, separate from user parentPort messages. */
export async function dispatchRuntimeCommand({ command, arguments: argv, cwd, environment, stdin, stdout, stderr }) {
  const port = workerData?.commandPort;
  const root = workerData?.commandDirectory;
  if (!port || !root) {
    stderr.write(`The native command broker is not connected for: ${command}\n`);
    return 127;
  }
  if (!connected) {
    port.on('message', message => {
      const operation = pending.get(message?.id);
      if (!operation) return;
      pending.delete(message.id);
      if (pending.size === 0) port.unref();
      if (message.error) operation.reject(new Error(message.error)); else operation.resolve(message.result);
    });
    port.on('close', () => {
      for (const operation of pending.values()) operation.reject(new Error('The runtime command broker disconnected.'));
      pending.clear();
    });
    port.unref();
    connected = true;
  }
  const id = randomUUID();
  const directory = path.join(root, id);
  await fs.mkdir(directory, { recursive: true, mode: 0o700 });
  const input = path.join(directory, 'stdin');
  // Spool with stream backpressure, never serialize stdin/output into a JSON RPC.
  // This adapter is for finite, noninteractive commands; TTY is not emulated.
  await pipeline(stdin ?? Readable.from([]), createWriteStream(input, { mode: 0o600 }));
  const route = await resolveRuntimeCommand(command, cwd, environment);
  const result = await new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject });
    port.ref();
    port.postMessage({ id, command, arguments: argv, cwd, environment, standardInputPath: input, ...route });
  });
  if (result.stdoutPath) await pipeline(createReadStream(result.stdoutPath), stdout, { end: false });
  if (result.stderrPath) await pipeline(createReadStream(result.stderrPath), stderr, { end: false });
  if (!Number.isInteger(result.exitCode)) throw new Error('The command broker returned no actual exit code.');
  return result.exitCode;
}
