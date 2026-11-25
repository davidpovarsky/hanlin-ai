// Hanlin cross-app extension; separate from the upstream scripting compatibility baseline.
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

declare global { const MiniApps: MiniAppSharing; }
