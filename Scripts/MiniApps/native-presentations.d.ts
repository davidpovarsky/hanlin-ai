/** Hanlin system-surface metadata. Runtime APIs/types come from the original engine SDK. */
export type NativePresentationEngine = 'expo' | 'scriptwidget';
export type NativePresentationSourceFormat = 'jsx' | 'tsx' | 'javascript' | 'expo-layout';
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
  families: ('systemSmall' | 'systemMedium' | 'systemLarge' | 'systemExtraLarge' | 'systemExtraLargePortrait' | 'accessoryCircular' | 'accessoryRectangular' | 'accessoryInline')[];
}
export interface NativePresentationDefinition {
  engine: NativePresentationEngine;
  sourcePath: string;
  sourceFormat: NativePresentationSourceFormat;
  /** Panels use local actions; hostAction belongs to widgets and Live Activities. */
  actions?: NativePresentationAction[];
  input?: { title: string; placeholder?: string; submitTitle: string };
}
export interface NativePresentationManifest {
  /** Keys are explicitly declared appIntent or translationUI entrypoint IDs. */
  nativePresentations?: Record<string, NativePresentationDefinition>;
}
export interface NativePresentationEffect {
  expandsSheet: boolean;
  finishRequested: boolean;
  replacementText?: string | null;
}
/** Return this field from an original Expo Widgets callback to affect its translation panel. */
export interface NativePresentationPropsEffect {
  __hanlinPresentationEffect: NativePresentationEffect;
}
