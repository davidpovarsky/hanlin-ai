import { requireNativeModule } from 'expo';
import { fromByteArray, toByteArray } from 'base64-js';
import { parseRuntimeExecutionResult, type HanlinRuntimeKind, type RuntimeExecutionLimits, type RuntimeExecutionResult } from './runtime-receipt';
export type { HanlinRuntimeKind, RuntimeExecutionLimits, RuntimeOutputArtifact, RuntimeExecutionResult } from './runtime-receipt';

interface NativeHostServicesModule {
  invoke(operation: string, payloadJSON: string): Promise<string>;
  hasCapability(capability: string): Promise<boolean>;
}
const NativeHostServices = requireNativeModule<NativeHostServicesModule>('HanlinHostServices');

export type HanlinDataArea = 'data' | 'documents' | 'state' | 'cache';

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
    return NativeHostServices.invoke('runtime.execute', JSON.stringify({kind, source, ...options}))
      .then(parseRuntimeExecutionResult);
  },

  async readFile(path: string, area: HanlinDataArea = 'data'): Promise<Uint8Array | null> {
    const { base64 } = await invoke<{ base64?: string | null }>('files.read', { path, area });
    if (base64 == null) return null;
    return toByteArray(base64);
  },

  writeFile(path: string, data: Uint8Array, area: HanlinDataArea = 'data'): Promise<{ ok: true }> {
    return invoke('files.write', { path, area, base64: fromByteArray(data) });
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
