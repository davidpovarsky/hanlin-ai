import { requireNativeModule } from 'expo';
import { fromByteArray, toByteArray } from 'base64-js';
import { serveMiniAppActions, type MiniAppActionHandlers } from './miniapp-actions';
export type { MiniAppActionInvocation, MiniAppActionHandler, MiniAppActionHandlers, MiniAppJSONValue } from './miniapp-actions';

interface NativeHostServicesModule {
  invoke(operation: string, payloadJSON: string): Promise<string>;
  hasCapability(capability: string): Promise<boolean>;
}
const NativeHostServices = requireNativeModule<NativeHostServicesModule>('HanlinHostServices');

export type HanlinRuntimeKind = 'node' | 'typeScript' | 'localPython' | 'javaScriptCore' | 'shell';
export type MiniAppOperation = 'display' | 'insert' | 'replaceSelection' | 'replaceDocument' | 'custom';
export interface MiniAppContent {
  kind: 'text' | 'url' | 'file' | 'json';
  text?: string; url?: string; attachmentID?: string; typeIdentifier?: string; name?: string;
}
export interface MiniAppSharedContext {
  id: string; appID: string; actionID?: string; operation: MiniAppOperation;
  inputs: MiniAppContent[]; opensInNewWindow: boolean;
  source: {
    appID: string; displayName: string; documentID?: string; documentTitle?: string;
    revision?: string; documentText?: string; kind?: string; locator?: string; sceneID?: string;
    selection?: {location: number; length: number; text: string; blockIDs: string[]};
    metadata: Record<string, string>;
  };
}
export interface MiniAppOutput {
  operation?: MiniAppOperation;
  status?: 'success' | 'error' | 'cancelled';
  items?: MiniAppContent[];
  message?: string;
  metadata?: Record<string, string>;
}
export interface MiniAppSharing {
  getContext(): Promise<MiniAppSharedContext>;
  complete(output: string | MiniAppOutput): Promise<{ok: true}>;
  cancel(): Promise<{ok: true}>;
  readAttachment(id: string): Promise<{base64: string}>;
  writeAttachment(file: {base64: string; name?: string; typeIdentifier?: string}): Promise<MiniAppContent>;
}

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
  actions: {
    /** Call once after loading the complete action table. Runs until session teardown. */
    register: (handlers: MiniAppActionHandlers): Promise<void> => serveMiniAppActions(invoke, handlers),
  },
  miniapps: {
    getContext: () => invoke<MiniAppSharedContext>('miniapps.context', {}),
    complete: async (output: string | MiniAppOutput) => {
      const receipt = await invoke<{ok: true}>('miniapps.complete', output);
      void invoke('miniapps.return', {}).catch(() => {});
      return receipt;
    },
    cancel: async () => {
      const receipt = await invoke<{ok: true}>('miniapps.cancel', {});
      void invoke('miniapps.return', {}).catch(() => {});
      return receipt;
    },
    readAttachment: (id: string) => invoke<{base64: string}>('miniapps.readAttachment', {id}),
    writeAttachment: (file: {base64: string; name?: string; typeIdentifier?: string}) => invoke<MiniAppContent>('miniapps.writeAttachment', file),
  } satisfies MiniAppSharing,
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
