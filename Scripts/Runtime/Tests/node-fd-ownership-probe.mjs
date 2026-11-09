import { Worker } from 'node:worker_threads';

// No package loader, network, app wrapper or shared descriptors: one Worker
// owns every open/read/close pair. Keep Node's descriptor tracking enabled.
export async function probeDescriptorOwnership(filePath, expected) {
  const worker = new Worker(`
    const { parentPort, workerData } = require('node:worker_threads');
    const fs = require('node:fs');
    const warnings = [];
    process.on('warning', warning => {
      if (warning.message.startsWith('File descriptor ')) warnings.push(warning.message);
    });
    const expected = Buffer.from(workerData.expected);
    for (let cycle = 0; cycle < 128; cycle++) {
      const fd = fs.openSync(workerData.filePath, 'r');
      try {
        const bytes = Buffer.alloc(expected.length);
        const count = fs.readSync(fd, bytes, 0, bytes.length, 0);
        if (count !== expected.length || !bytes.equals(expected)) throw new Error('Descriptor read mismatch');
      } finally {
        fs.closeSync(fd);
      }
    }
    setImmediate(() => parentPort.postMessage({
      answer: 42, cycles: 128, fdWarningCount: warnings.length,
      fdWarnings: warnings.slice(0, 4),
    }));
  `, { eval: true, trackUnmanagedFds: true, workerData: { filePath, expected } });
  let result;
  await new Promise((resolve, reject) => {
    worker.once('message', value => { result = value; });
    worker.once('error', reject);
    worker.once('exit', code => code === 0 && result ? resolve() : reject(new Error(`Descriptor Worker exited ${code} without a result`)));
  });
  return result;
}
