import type {NativeCaptureFile, NativeCaptureInput, NativeSpotlightInput, NotificationPresentationUserInfoV1} from '@hanlin/system-surfaces';
import type {HanlinNotificationUserInfoV1} from '@hanlin/notification-events';

export interface NotebookState {
  schemaVersion: 1;
  appID: string;
  spotlightCount: number;
  captureCount: number;
  notificationCount: number;
  lastCapture: NativeCaptureInput | null;
  lastMessage: string;
}
export type ActionResult = {source: string; message: string; count: number; readBytes?: number; sessionID?: string};
export const ids = {spotlight: 'search', capture: 'photo', keyboard: 'keys', notification: 'notice', notificationAction: 'notice-action'} as const;
export function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
function text(value: unknown, field: string): string {
  if (typeof value !== 'string' || !value) throw new Error('Missing ' + field);
  return value;
}
function positive(value: unknown, field: string): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value <= 0) throw new Error('Invalid ' + field);
  return value;
}
function capturePath(value: unknown, sessionID: string, id: string): NativeCaptureFile['path'] {
  const expected: NativeCaptureFile['path'] = `captures/${sessionID.toLowerCase()}/${id.toLowerCase()}.jpg`;
  if (value !== expected || sessionID.includes('/') || id.includes('/') || sessionID.includes('..') || id.includes('..')) {
    throw new Error('Capture path does not match its supplied session/photo identity.');
  }
  return expected;
}
/** Validate the actual JSON delivered by the Host; a TypeScript annotation is not runtime validation. */
export function captureInput(value: unknown): NativeCaptureInput {
  if (!isObject(value) || (value.source !== 'lockedCamera' && value.source !== 'applicationCamera')) throw new Error('Not a native capture input.');
  const sessionID = text(value.sessionID, 'sessionID');
  if (!Array.isArray(value.files) || !value.files.length) throw new Error('No captured files were delivered.');
  const files: NativeCaptureFile[] = value.files.map((item: unknown) => {
    if (!isObject(item) || item.area !== 'documents' || item.contentType !== 'public.jpeg' || item.mimeType !== 'image/jpeg') throw new Error('Unexpected capture file.');
    const id = text(item.id, 'file.id');
    const digest = text(item.sha256, 'file.sha256');
    if (!/^[a-f0-9]{64}$/.test(digest)) throw new Error('Invalid capture digest.');
    return {id, area: 'documents', path: capturePath(item.path, sessionID, id), contentType: 'public.jpeg', mimeType: 'image/jpeg',
      byteCount: positive(item.byteCount, 'file.byteCount'), sha256: digest,
      width: positive(item.width, 'file.width'), height: positive(item.height, 'file.height')};
  });
  if (new Set(files.map(file => file.id)).size !== files.length) throw new Error('Duplicate captured photo identity.');
  return {source: value.source, sessionID, installedPackageID: text(value.installedPackageID, 'installedPackageID'),
    packageID: text(value.packageID, 'packageID'), generation: positive(value.generation, 'generation'),
    entrypointID: text(value.entrypointID, 'entrypointID'), files};
}
export function emptyState(appID: string): NotebookState {
  return {schemaVersion: 1, appID, spotlightCount: 0, captureCount: 0, notificationCount: 0, lastCapture: null,
    lastMessage: 'טרם התקבלה פעולה ממערכת ההפעלה.'};
}
export function createNotebook(io: {appID: string; read(): Promise<string | null>; write(text: string): Promise<void>;
  readCapture(file: NativeCaptureFile): Promise<number>}) {
  let tail: Promise<unknown> = Promise.resolve();
  let observer: ((state: NotebookState) => void) | undefined;
  const serial = <T>(operation: () => Promise<T>): Promise<T> => {
    const next = tail.then(operation, operation); tail = next.then(() => undefined, () => undefined); return next;
  };
  const load = async (): Promise<NotebookState> => {
    const raw = await io.read(); if (raw === null) return emptyState(io.appID);
    const value: unknown = JSON.parse(raw);
    if (!isObject(value) || value.schemaVersion !== 1 || value.appID !== io.appID ||
        typeof value.lastMessage !== 'string') throw new Error('Saved notebook identity/shape changed.');
    const count = (n: unknown) => { if (typeof n !== 'number' || !Number.isSafeInteger(n) || n < 0) throw new Error('Invalid saved count.'); return n; };
    return {schemaVersion: 1, appID: io.appID, spotlightCount: count(value.spotlightCount), captureCount: count(value.captureCount),
      notificationCount: count(value.notificationCount), lastMessage: value.lastMessage,
      lastCapture: value.lastCapture === null ? null : captureInput(value.lastCapture)};
  };
  const save = async (state: NotebookState) => { await io.write(JSON.stringify(state)); observer?.(state); };
  return {
    observe(next: (state: NotebookState) => void) { observer = next; return () => { if (observer === next) observer = undefined; }; },
    read: () => serial(async () => { const state = await load(); observer?.(state); return state; }),
    spotlight: (input: unknown) => serial(async (): Promise<ActionResult> => {
      if (!isObject(input) || input.source !== 'spotlight') throw new Error('Expected a Spotlight action input.');
      const actual: NativeSpotlightInput = {source: input.source};
      const state = await load(); state.spotlightCount += 1;
      state.lastMessage = 'פעולת Spotlight התקבלה ביישום הפעיל.'; await save(state);
      return {source: actual.source, message: state.lastMessage, count: state.spotlightCount};
    }),
    capture: (input: unknown) => serial(async (): Promise<ActionResult> => {
      const actual = captureInput(input); let readBytes = 0;
      for (const file of actual.files) {
        const count = await io.readCapture(file);
        if (count !== file.byteCount) throw new Error('The actual captured file length differs from its Host metadata.');
        readBytes += count;
      }
      const state = await load(); state.captureCount += 1; state.lastCapture = actual;
      state.lastMessage = `נקראו בפועל ${actual.files.length} תמונות, ${readBytes} בתים.`; await save(state);
      return {source: actual.source, message: state.lastMessage, count: state.captureCount, readBytes, sessionID: actual.sessionID};
    }),
    notification: (input: unknown) => serial(async (): Promise<ActionResult> => {
      if (!isObject(input) || input.source !== 'notification' || typeof input.message !== 'string') throw new Error('Expected the declared notification continuation.');
      const state = await load(); state.notificationCount += 1; state.lastMessage = input.message; await save(state);
      return {source: 'notification', message: state.lastMessage, count: state.notificationCount};
    })
  };
}
function eventID(): string {
  // A fresh event identifier, not an authorization token or an invented installation.
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, character => {
    const random = Math.floor(Math.random() * 16); return (character === 'x' ? random : (random & 3) | 8).toString(16);
  });
}
export function notificationForCapture(appID: string, capture: NativeCaptureInput) {
  const id = eventID(); const created = Date.now();
  const identity = {installedPackageID: capture.installedPackageID, packageID: capture.packageID, generation: capture.generation};
  const userInfo: NotificationPresentationUserInfoV1 & HanlinNotificationUserInfoV1 = {
    'hanlin-miniapp-presentation': {schemaVersion: 1, identity: {...identity, entrypointID: ids.notification},
      parameters: {message: 'התמונות נשמרו. אפשר להמשיך למחברת או לסגור את ההתראה.'}},
    'hanlin-miniapp-event': {schemaVersion: 1, id, createdAtUnixMilliseconds: created,
      expiresAtUnixMilliseconds: created + 24 * 60 * 60 * 1000, appID,
      identity: {...identity, entrypointID: ids.notificationAction}, actionID: 'notification.open',
      parameters: {source: 'notification', message: 'הפעולה מההתראה העשירה המשיכה למחברת.'}}
  };
  return {id, userInfoJSON: JSON.stringify(userInfo)};
}
