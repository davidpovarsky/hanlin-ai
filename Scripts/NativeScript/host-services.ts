import type { MiniAppLiveActivities } from "../../Packages/HanlinExpoUI/src/system-surfaces";
export type { NativeSurfaceJSON, NativeSurfaceAction, NativeSurfaceNode, NativeSurfaceProperties, LiveActivityStart, NativeSurfaceLiveActivityStart, ScriptWidgetLiveActivityStart, LiveActivityUpdate, LiveActivityEnd, MiniAppLiveActivities } from "../../Packages/HanlinExpoUI/src/system-surfaces";
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
export interface MiniAppShortcutProgress {
  completedUnitCount: number;
  totalUnitCount: number;
  message?: string;
}
export interface MiniAppSharing {
  /** Report actual completed work inside a long-running Shortcuts action. */
  reportShortcutProgress(progress: MiniAppShortcutProgress): Promise<{ok: true}>;
  getContext(): Promise<MiniAppSharedContext>;
  complete(output: string | MiniAppOutput): Promise<{ok: true}>;
  cancel(): Promise<{ok: true}>;
  readAttachment(id: string): Promise<{base64: string}>;
  writeAttachment(file: {base64: string; name?: string; typeIdentifier?: string}): Promise<MiniAppContent>;
}

interface NativeRuntimeBridge {
  sendRequestActionCapabilityPayloadJSONCompletion(target: string, action: string, capability: string, payloadJSON: string, completion: (result: string | null, error: string | null) => void): void;
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
  function share<T>(operation: string, payload: unknown = {}): Promise<T> {
    return new Promise((resolve, reject) => {
      boundBridge.sendRequestActionCapabilityPayloadJSONCompletion(
        'hanlin.cross-app', operation, 'miniapps', JSON.stringify(payload), (receipt, error) => {
          if (error !== null) { reject(new Error(error)); return; }
          if (receipt === null) { reject(new Error('MiniApps returned no receipt.')); return; }
          try { resolve(JSON.parse(receipt) as T); } catch { reject(new Error('MiniApps returned invalid JSON.')); }
        });
    });
  }
  function surface<T>(operation: string, payload: unknown = {}): Promise<T> {
    return new Promise((resolve, reject) => {
      boundBridge.sendRequestActionCapabilityPayloadJSONCompletion(
        'hanlin.host-services', operation, 'live-activity', JSON.stringify(payload), (receipt, error) => {
          if (error !== null) { reject(new Error(error)); return; }
          if (receipt === null) { reject(new Error('Live Activity operation returned no result.')); return; }
          try { resolve(JSON.parse(receipt) as T); } catch { reject(new Error('Live Activity operation returned invalid JSON.')); }
        });
    });
  }
  const liveActivities: MiniAppLiveActivities = {
    areEnabled: async () => (await surface<{enabled: boolean}>('liveActivities.areEnabled')).enabled,
    list: async () => (await surface<{activityIDs: string[]}>('liveActivities.list')).activityIDs,
    start: request => surface('liveActivities.start', request),
    update: (activityID, request) => surface('liveActivities.update', {...request, activityID}),
    end: (activityID, request = {}) => surface('liveActivities.end', {...request, activityID}),
  };
  const miniapps: MiniAppSharing = {
    reportShortcutProgress: progress => share('miniapps.shortcutProgress', progress),
    getContext: () => share('miniapps.context'),
    complete: async output => {
      const receipt = await share<{ok: true}>('miniapps.complete', output);
      void share('miniapps.return').catch(() => {});
      return receipt;
    },
    cancel: async () => {
      const receipt = await share<{ok: true}>('miniapps.cancel');
      void share('miniapps.return').catch(() => {});
      return receipt;
    },
    readAttachment: id => share('miniapps.readAttachment', {id}),
    writeAttachment: file => share('miniapps.writeAttachment', file),
  };
  return {
    miniapps,
    liveActivities,
    startRuntime,
    executeRuntime(kind: HanlinRuntimeKind, source: string, options: RuntimeExecutionOptions = {}): Promise<RuntimeExecutionResult> {
      return startRuntime(kind, source, options).result;
    },
  };
}
