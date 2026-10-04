import { requireNativeModule } from 'expo';

const NativeHostServices = requireNativeModule('HanlinHostServices');

export type HanlinRuntimeKind = 'node' | 'typeScript' | 'localPython' | 'javaScriptCore' | 'shell';
export type HanlinDataArea = 'data' | 'documents' | 'state' | 'cache';

export interface RuntimeExecutionLimits {
  timeoutMilliseconds: number;
  maximumOutputBytes: number;
}

export interface RuntimeExecutionResult {
  executionID: string;
  stdout: string;
  stderr: string;
  value?: unknown;
  exitCode?: number;
  durationMilliseconds: number;
  didTimeOut: boolean;
  wasCancelled: boolean;
  outputWasTruncated: boolean;
}

async function invoke<T>(operation: string, payload: unknown): Promise<T> {
  const response = await NativeHostServices.invoke(operation, JSON.stringify(payload));
  return JSON.parse(response) as T;
}

export const hostServices = {
  hasCapability(capability: string): Promise<boolean> {
    return NativeHostServices.hasCapability(capability);
  },

  executeRuntime(
    kind: HanlinRuntimeKind,
    source: string,
    options: {
      arguments?: string[];
      environment?: Record<string, string>;
      limits?: RuntimeExecutionLimits;
    } = {}
  ): Promise<RuntimeExecutionResult> {
    return invoke('runtime.execute', { kind, source, ...options });
  },

  async readFile(path: string, area: HanlinDataArea = 'data'): Promise<Uint8Array | null> {
    const { base64 } = await invoke<{ base64?: string }>('files.read', { path, area });
    if (!base64) return null;
    const binary = globalThis.atob(base64);
    return Uint8Array.from(binary, (character) => character.charCodeAt(0));
  },

  writeFile(path: string, data: Uint8Array, area: HanlinDataArea = 'data'): Promise<{ ok: true }> {
    let binary = '';
    for (const byte of data) binary += String.fromCharCode(byte);
    return invoke('files.write', { path, area, base64: globalThis.btoa(binary) });
  },

  deleteFile(path: string, area: HanlinDataArea = 'data'): Promise<{ ok: true }> {
    return invoke('files.delete', { path, area });
  },

  async listFiles(area: HanlinDataArea = 'data'): Promise<string[]> {
    return (await invoke<{ files: string[] }>('files.list', { area })).files;
  },
} as const;
