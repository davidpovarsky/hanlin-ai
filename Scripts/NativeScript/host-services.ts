/** Typed facade over the existing Objective-C metadata bridge. No extra runtime. */
export type HanlinRuntimeKind = 'node' | 'typeScript' | 'localPython' | 'javaScriptCore' | 'shell';
export type RuntimeJSONValue = null | boolean | number | string | RuntimeJSONValue[] | { [key: string]: RuntimeJSONValue };
export interface RuntimeExecutionLimits {
  timeoutMilliseconds?: number;
  /** Preview only; full stdout/stderr remain in the job's artifacts. */
  maximumOutputBytes: number;
}
export interface RuntimeOutputArtifact { path: string; bytes: number; sha256: string }
export interface RuntimeExecutionResult {
  executionID: string;
  stdout: string;
  stderr: string;
  value?: RuntimeJSONValue;
  exitCode?: number;
  durationMilliseconds: number;
  didTimeOut: boolean;
  wasCancelled: boolean;
  outputWasTruncated: boolean;
  outputFiles?: Record<string, RuntimeOutputArtifact>;
}
export interface RuntimeExecutionOptions {
  arguments?: string[];
  environment?: Record<string, string>;
  limits?: RuntimeExecutionLimits;
}
export interface RuntimeRequestHandle {
  /** Null only when the native session rejected admission. */
  readonly requestID: string | null;
  readonly result: Promise<RuntimeExecutionResult>;
  /** Cooperative request, not a claim that a native operation has drained. */
  cancel(): boolean;
}
interface NativeRuntimeBridge {
  executeRuntimeCompletion(payloadJSON: string, completion: (result: string | null, error: string | null) => void): string | null;
  cancelRuntime(requestID: string): boolean;
}
declare const HanlinNativeServicesBridge: {
  activeSessionBridge(): NativeRuntimeBridge | null;
};

function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}
function nonnegativeInteger(value: unknown): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;
}
function jsonValue(value: unknown): value is RuntimeJSONValue {
  const pending: unknown[] = [value];
  while (pending.length) {
    const item = pending.pop();
    if (item === null || typeof item === 'boolean' || typeof item === 'string') continue;
    if (typeof item === 'number' && Number.isFinite(item)) continue;
    if (Array.isArray(item)) { for (const child of item) pending.push(child); continue; }
    if (record(item)) { for (const child of Object.values(item)) pending.push(child); continue; }
    return false;
  }
  return true;
}

/** Decode the existing Swift RuntimeExecutionResult wire contract. A native
 * callback or syntactically valid JSON alone does not establish a receipt. */
export function parseRuntimeExecutionResult(receipt: string): RuntimeExecutionResult {
  let value: unknown;
  try { value = JSON.parse(receipt); }
  catch { throw new Error('Runtime returned invalid receipt JSON.'); }
  if (!record(value) || typeof value.executionID !== 'string' ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value.executionID) ||
      typeof value.stdout !== 'string' || typeof value.stderr !== 'string' ||
      !nonnegativeInteger(value.durationMilliseconds) ||
      typeof value.didTimeOut !== 'boolean' || typeof value.wasCancelled !== 'boolean' ||
      typeof value.outputWasTruncated !== 'boolean' ||
      ('exitCode' in value && (typeof value.exitCode !== 'number' || !Number.isSafeInteger(value.exitCode))) ||
      ('value' in value && !jsonValue(value.value))) {
    throw new Error('Runtime returned an invalid execution receipt.');
  }
  if ('outputFiles' in value) {
    if (!record(value.outputFiles) || Object.values(value.outputFiles).some(artifact =>
        !record(artifact) || typeof artifact.path !== 'string' || !nonnegativeInteger(artifact.bytes) ||
        typeof artifact.sha256 !== 'string' || !/^[0-9a-f]{64}$/i.test(artifact.sha256))) {
      throw new Error('Runtime returned invalid output artifact descriptors.');
    }
  }
  return value as unknown as RuntimeExecutionResult;
}

/** Capture once inside this package's active session. A later global session
 * cannot redirect the returned facade's calls or cancellation handles. */
export function createHostServices() {
  if (typeof HanlinNativeServicesBridge === 'undefined') throw new Error('Hanlin Host Services metadata is unavailable.');
  const bridge = HanlinNativeServicesBridge.activeSessionBridge();
  if (!bridge) throw new Error('No active Hanlin NativeScript session.');
  const boundBridge = bridge;
  function startRuntime(kind: HanlinRuntimeKind, source: string, options: RuntimeExecutionOptions = {}): RuntimeRequestHandle {
    let requestID: string | null = null;
    const result = new Promise<RuntimeExecutionResult>((resolve, reject) => {
      requestID = boundBridge.executeRuntimeCompletion(JSON.stringify({kind, source, ...options}), (receipt, error) => {
        if (error !== null) { reject(new Error(error)); return; }
        if (receipt === null) { reject(new Error('Runtime returned no execution receipt.')); return; }
        try { resolve(parseRuntimeExecutionResult(receipt)); }
        catch (error) { reject(error); }
      });
    });
    return {requestID, result, cancel: () => requestID !== null && boundBridge.cancelRuntime(requestID)};
  }
  return {
    startRuntime,
    executeRuntime(kind: HanlinRuntimeKind, source: string, options: RuntimeExecutionOptions = {}): Promise<RuntimeExecutionResult> {
      return startRuntime(kind, source, options).result;
    },
  };
}
