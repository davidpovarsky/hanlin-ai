import { traceRuntimeWarnings } from './warning-diagnostics.mjs';

// Install before loading the execution worker and its dependencies so warnings
// during module loading retain their actual JavaScript stack and worker ID.
traceRuntimeWarnings();
await import('./execution-worker.mjs');
