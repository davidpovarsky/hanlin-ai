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
        try { resolve(JSON.parse(receipt) as RuntimeExecutionResult); }
        catch { reject(new Error('Runtime returned invalid receipt JSON.')); }
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
