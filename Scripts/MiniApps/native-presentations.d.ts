/** Hanlin system-surface metadata. Runtime APIs/types come from the original engine SDK. */
export type NativePresentationEngine = 'expo' | 'scriptwidget';
export type NativePresentationSourceFormat = 'jsx' | 'tsx' | 'javascript' | 'expo-layout';
export type NativePresentationKind = 'snippet' | 'translationUI' | 'keyboard' | 'notificationUI';
/** Widget-local and native-panel actions execute in their original renderer. */
export type NativePresentationAction =
  | { id: string; kind: 'function'; handler: string }
  | { id: string; kind: 'setValue'; stateKey: string; handler?: string }
  | { id: string; kind: 'expoCallback' | 'reload' };
/** Ordinary JSON, not the Host's internal tagged HanlinValue wire encoding. */
export type WidgetActionJSON = null | boolean | number | string
  | WidgetActionJSON[] | { [key: string]: WidgetActionJSON };
export interface WidgetHostAction {
  /** A declared appIntent entrypoint in this same Expo or NativeScript package. */
  entrypointID: string;
  /** The exact registered actions[].id, including its original letter case. */
  actionName: string;
  /** A rendered event's parameters override these defaults; explicit null is retained. */
  parameters?: WidgetActionJSON;
}
/** Continues a declared package action in the foreground Host and retains its actual receipt. */
export type WidgetAction = NativePresentationAction
  | { id: string; kind: 'hostAction'; hostAction: WidgetHostAction; handler?: never; stateKey?: never };
export interface WidgetProgramDefinition {
  abiVersion: 1;
  sourceFormat: NativePresentationSourceFormat;
  actions: WidgetAction[];
  families: ('systemSmall' | 'systemMedium' | 'systemLarge' | 'systemExtraLarge')[];
}
export interface NativePresentationDefinition {
  engine: NativePresentationEngine;
  sourcePath: string;
  sourceFormat: NativePresentationSourceFormat;
  /** Panels use local original-engine actions. A notification continues its existing event envelope. */
  actions?: NativePresentationAction[];
  input?: { title: string; placeholder?: string; submitTitle: string };
}
/** An explicit exposure of an installed Expo or NativeScript package. */
interface PreparedMiniAppEntrypointBase {
  id: string;
  /**
   * keyboard/notificationUI/spotlight/capture/assistantTool reference the prepared foreground
   * bundle here. Only keyboard/notificationUI use a separately declared
   * nativePresentations entry pointing to original-renderer UI source.
   * Assistant tools do not require a presentation. The foreground bundle
   * is not executed in a keyboard.
   */
  sourcePath: string;
}
/** Capture and assistantTool select one declared prepared action; Spotlight may only open the app. */
export type PreparedMiniAppEntrypoint = PreparedMiniAppEntrypointBase & (
  | {kind: 'capture' | 'assistantTool'; exportedSymbol: string}
  | {kind: 'appIntent' | 'embeddedResult' | 'share' | 'translationUI' | 'liveActivity'
      | 'keyboard' | 'notificationUI' | 'spotlight'; exportedSymbol?: string}
);
/** The actual canonical schema contract has an object root; JSON Schema keywords and dialect are preserved. */
export type PreparedActionSchema = { [keyword: string]: WidgetActionJSON };
/**
 * Metadata for one action selected by a prepared assistantTool entrypoint.
 * This does not register its JavaScript handler. The native loader validates
 * the cross-reference and decodes the actual schemas before registering a tool.
 */
export type PreparedAssistantToolAction = {
  id: string;
  /** Defaults to id. */
  title?: string;
  /** Summary takes precedence over description, then defaults to the title. */
  summary?: string;
  description?: string;
  capability?: string;
  /** Canonical function-tool parameters are objects. Other schema keywords remain available. */
  inputSchema: PreparedActionSchema & { type: 'object' };
  /** A schema document which may describe any JSON result, including scalars and arrays. */
  outputSchema?: PreparedActionSchema;
} & (
  /** handler is preferred when both names are present. */
  | {handler: string; entrypoint?: string}
  | {handler?: never; entrypoint: string}
);
export interface NativePresentationManifest {
  entrypoints?: PreparedMiniAppEntrypoint[];
  /** Keys are declared appIntent, translationUI, keyboard or notificationUI entrypoint IDs. */
  nativePresentations?: Record<string, NativePresentationDefinition>;
}
export interface KeyboardPresentationContext {
  documentContextBeforeInput?: string;
  documentContextAfterInput?: string;
  selectedText?: string;
  /** Actual iOS setting. Reads of the installed shared catalog do not require Full Access. */
  hasFullAccess: boolean;
}
export type KeyboardPresentationEdit =
  | { operation: 'insertText'; text: string; offset?: never }
  | { operation: 'deleteBackward' | 'nextInputMode'; text?: never; offset?: never }
  | { operation: 'adjustTextPosition'; offset: number; text?: never };
export interface NativePresentationContext {
  kind: NativePresentationKind;
  sessionID: string;
  inputText: string;
  parameters: WidgetActionJSON;
  allowsReplacement: boolean;
  /** Present in a keyboard. Offsets count characters, as UITextDocumentProxy specifies. */
  keyboard?: KeyboardPresentationContext;
}
export interface NativePresentationEffect {
  /** Defaults to false when omitted; retained for existing translation panels. */
  expandsSheet?: boolean;
  finishRequested?: boolean;
  replacementText?: string | null;
  /** Applied sequentially by the current keyboard's textDocumentProxy. */
  keyboardEdits?: KeyboardPresentationEdit[];
  /** openApp persists the notification's exact event, then performs its system default action. */
  notificationAction?: 'openApp' | 'dismiss';
}
/** Return this field from an original Expo Widgets callback to affect its current surface. */
export interface NativePresentationPropsEffect {
  __hanlinPresentationEffect: NativePresentationEffect;
}
export interface NativePresentationIdentity {
  installedPackageID: string;
  packageID: string;
  generation: number;
  entrypointID: string;
  variantID?: string;
}
/** Plain JSON in userInfo["hanlin-miniapp-presentation"]. */
export interface NotificationPresentationPayloadV1 {
  schemaVersion: 1;
  /** Identifies a declared notificationUI presentation in the current installed generation. */
  identity: NativePresentationIdentity;
  parameters?: WidgetActionJSON;
}
/**
 * For foreground continuation, also supply the existing typed
 * userInfo["hanlin-miniapp-event"]. Its action entrypoint may differ, but its
 * installedPackageID/packageID/generation must match the presentation.
 * Queue admission reports queued; only the actual Host records completion.
 */
export interface NotificationPresentationUserInfoV1 {
  'hanlin-miniapp-presentation': NotificationPresentationPayloadV1;
  [key: string]: unknown;
}

/** Files delivered by the native capture handoff are already copied into this package's Documents area. */
export interface NativeCaptureFile {
  id: string;
  area: 'documents';
  /** Relative path accepted by the existing Host.files API. */
  path: `captures/${string}/${string}.jpg`;
  contentType: 'public.jpeg';
  mimeType: 'image/jpeg';
  byteCount: number;
  sha256: string;
  width: number;
  height: number;
}
/** Ordinary JSON passed to the action selected by a capture entrypoint's exportedSymbol. */
export interface NativeCaptureInput {
  source: 'lockedCamera' | 'applicationCamera';
  sessionID: string;
  installedPackageID: string;
  packageID: string;
  generation: number;
  entrypointID: string;
  files: NativeCaptureFile[];
}
/** Ordinary input for a Spotlight entrypoint which declares an action. */
export interface NativeSpotlightInput {
  source: 'spotlight';
}
