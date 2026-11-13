import { threadId } from 'node:worker_threads';

// Scoped to an explicit diagnostic run; retain Node's own warning handler and
// descriptor tracking. Concurrent probes share a listener until the last ends.
let active = 0;
const trace = warning => process.stderr.write(`[HANLIN_NODE_WARNING thread=${threadId}] ${warning.stack ?? warning}\n`);
export function traceRuntimeWarnings() {
  if (active++ === 0) process.on('warning', trace);
  let stopped = false;
  return () => {
    if (stopped) return;
    stopped = true;
    if (--active === 0) process.off('warning', trace);
  };
}
