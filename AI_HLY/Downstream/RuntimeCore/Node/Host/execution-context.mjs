import fs from 'node:fs';
import path from 'node:path';
import { createRequire, syncBuiltinESMExports } from 'node:module';
import { configureExecutionModules } from './execution-modules.mjs';

/** Per-Worker context: never change the process-wide C working directory. */
export function configureExecutionContext(configuration, { setArguments = true } = {}) {
  const { workspace, arguments: argv, environment, commandPort, startGate } = configuration;
  commandPort?.unref();
  if (startGate) {
    const state = new Int32Array(startGate);
    // Only the Worker waits. The shared Host first commits its running journal,
    // then releases user code; an I/O failure cannot run unjournalled side effects.
    while (Atomics.load(state, 0) === 0) Atomics.wait(state, 0, 0);
  }
  const entryPoint = configureExecutionModules(configuration);
  globalThis.require = createRequire(entryPoint);
  globalThis.__filename = entryPoint;
  globalThis.__dirname = path.dirname(entryPoint);
  if (workspace) {
    process.cwd = () => workspace;
    const resolve = value => typeof value === 'string' && !path.isAbsolute(value) ? path.resolve(workspace, value) : value;
    const single = ['readFile', 'writeFile', 'appendFile', 'stat', 'lstat', 'access', 'open', 'readdir',
      'unlink', 'rm', 'rmdir', 'mkdir', 'exists', 'createReadStream', 'createWriteStream', 'chmod',
      'chown', 'utimes', 'truncate', 'realpath', 'readlink', 'opendir', 'watch', 'watchFile', 'unwatchFile', 'openAsBlob'];
    const pair = ['copyFile', 'cp', 'rename', 'link'];
    for (const module of [fs, fs.promises]) {
      const wrap = (name, indices) => {
        const original = module[name];
        if (typeof original !== 'function') return;
        const wrapFunction = target => function (...args) {
          for (const index of indices) if (index < args.length) args[index] = resolve(args[index]);
          return target.apply(this, args);
        };
        const replacement = wrapFunction(original);
        for (const key of Reflect.ownKeys(original)) {
          if (['name', 'length', 'prototype', 'caller', 'arguments'].includes(key)) continue;
          const descriptor = Object.getOwnPropertyDescriptor(original, key);
          if (typeof descriptor.value === 'function') descriptor.value = wrapFunction(descriptor.value);
          Object.defineProperty(replacement, key, descriptor);
        }
        module[name] = replacement;
      };
      for (const name of single) { wrap(name, [0]); wrap(name + 'Sync', [0]); }
      for (const name of pair) { wrap(name, [0, 1]); wrap(name + 'Sync', [0, 1]); }
      // Relative symlink targets are relative to the link's parent, not cwd.
      wrap('symlink', [1]); wrap('symlinkSync', [1]);
    }
    syncBuiltinESMExports();
  }
  for (const [name, value] of Object.entries(environment ?? {})) process.env[name] = String(value);
  if (setArguments) process.argv = ['node', entryPoint, ...(argv ?? []).map(String)];
}
