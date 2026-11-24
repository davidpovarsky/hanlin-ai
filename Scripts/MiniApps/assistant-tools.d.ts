/** Shared composer declarations. These types describe data, not a second UI/runtime. */
export type HanlinComposerJSON = null | boolean | number | string | HanlinComposerJSON[]
  | { [key: string]: HanlinComposerJSON };

export interface HanlinComposerOption {
  id: string;
  title: string;
  children?: HanlinComposerOption[];
}
export interface HanlinComposerField {
  key: string;
  title: string;
  kind: 'text' | 'toggle' | 'number' | 'choice' | 'multiChoice' | 'catalog' | 'location';
  required?: boolean;
  defaultValue?: HanlinComposerJSON;
  options?: HanlinComposerOption[];
  /** Numeric bounds. For location, these bound radiusMeters. */
  minimum?: number;
  maximum?: number;
  placeholder?: string;
}
export interface HanlinComposerPanel {
  id: string;
  title: string;
  fields?: HanlinComposerField[];
  /** Optional view registered by the embedding host. No script executes on selection. */
  customViewID?: string;
}
export interface HanlinComposerConfiguration {
  schemaVersion?: 1;
  panels: HanlinComposerPanel[];
}
export interface HanlinAssistantToolAction {
  id: string;
  title: string;
  summary: string;
  inputSchema: { type: 'object'; [keyword: string]: HanlinComposerJSON };
  outputSchema?: { [keyword: string]: HanlinComposerJSON };
  /** Named source export, defaulting to id. The bridge registers id. */
  exportedSymbol?: string;
  /** Exact sibling embeddedResult entrypoint. No implicit renderer lookup. */
  embeddedResultID?: string;
}
export interface HanlinAssistantToolDeclaration {
  title: string;
  summary: string;
  actions: HanlinAssistantToolAction[];
  configuration?: HanlinComposerConfiguration;
}
export interface HanlinAssistantToolEntrypoint {
  id: string;
  kind: 'assistantTool';
  /** A dedicated prepared folder/bundle.js (Expo) or folder/bundle.mjs (NativeScript). */
  sourcePath: string;
  assistantTool: HanlinAssistantToolDeclaration;
}
export interface HanlinAssistantToolAuthoring {
  /** Keys must match declared assistantTool entrypoint IDs. Values are source paths. */
  assistantTools?: Record<string, string>;
}
export interface HanlinAssistantToolContext<Configuration = Record<string, HanlinComposerJSON>> {
  /** The explicit user snapshot. Never synthesized from model arguments. */
  readonly configuration: Configuration;
  readonly actionID: string;
  readonly caller: string;
}
export type HanlinAssistantToolHandler<
  Arguments = Record<string, HanlinComposerJSON>,
  Configuration = Record<string, HanlinComposerJSON>,
  Result extends HanlinComposerJSON = HanlinComposerJSON
> = (arguments_: Arguments, context: HanlinAssistantToolContext<Configuration>) => Result | Promise<Result>;
