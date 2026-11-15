import './fetch-compatibility.mjs';
import { workerData } from 'node:worker_threads';
import dns from 'node:dns';
import { configureExecutionContext } from './execution-context.mjs';
// The Worker starts the actual CLI entry file, so CommonJS require.main and
// package-relative module resolution retain Node's native entry semantics.
if (workerData?.hanlinManagedExecution === true) {
  if (typeof dns.setDefaultResultOrder === 'function') dns.setDefaultResultOrder('ipv4first');
  // Private bootstrap arguments must not leak into user-created nested Workers.
  if (workerData.launchNodeOptions == null) delete process.env.NODE_OPTIONS;
  else process.env.NODE_OPTIONS = workerData.launchNodeOptions;
  configureExecutionContext(workerData, { setArguments: false });
}
