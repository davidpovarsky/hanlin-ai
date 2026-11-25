/** Hanlin system-surface metadata. Runtime APIs/types come from the original engine SDK. */
export type NativePresentationEngine = 'expo' | 'scriptwidget';
export type NativePresentationSourceFormat = 'jsx' | 'tsx' | 'javascript' | 'expo-layout';
export type NativePresentationAction =
  | { id: string; kind: 'function'; handler: string }
  | { id: string; kind: 'setValue'; stateKey: string; handler?: string }
  | { id: string; kind: 'expoCallback' | 'reload' };
export interface NativePresentationDefinition {
  engine: NativePresentationEngine;
  sourcePath: string;
  sourceFormat: NativePresentationSourceFormat;
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
