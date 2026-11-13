import { requireNativeModule } from 'expo';

const NativeHostServices = requireNativeModule('HanlinHostServices');

export type HanlinRuntimeKind = 'node' | 'typeScript' | 'localPython' | 'javaScriptCore' | 'shell';
export type HanlinDataArea = 'data' | 'documents' | 'state' | 'cache';

export interface RuntimeExecutionLimits {
  /** Omit for no explicit deadline; this is not a default timeout. */
  timeoutMilliseconds?: number;
  /** Preview budget; full output remains in the runtime job artifacts. */
  maximumOutputBytes: number;
}

export interface RuntimeOutputArtifact {
  path: string;
  bytes: number;
  sha256: string;
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
  outputFiles?: Record<string, RuntimeOutputArtifact>;
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
    const { base64 } = await invoke<{ base64?: string | null }>('files.read', { path, area });
    if (base64 == null) return null;
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

  publishWidget(
    entrypointID: string,
    family: string,
    root: unknown,
    validUntil?: string | number | Date
  ): Promise<{ ok: true }> {
    let validUntilISO: string | undefined;
    let validUntilEpochMilliseconds: number | undefined;
    if (validUntil instanceof Date) {
      validUntilISO = validUntil.toISOString();
      validUntilEpochMilliseconds = validUntil.getTime();
    } else if (typeof validUntil === 'number') {
      validUntilISO = new Date(validUntil).toISOString();
      validUntilEpochMilliseconds = validUntil;
    } else if (typeof validUntil === 'string') {
      validUntilISO = validUntil;
      const parsed = Date.parse(validUntil);
      if (!Number.isNaN(parsed)) {
        validUntilEpochMilliseconds = parsed;
      }
    }
    return invoke('widgets.publish', {
      entrypointID,
      family,
      root,
      validUntil: validUntilISO,
      validUntilEpochMilliseconds,
    });
  },
} as const;
