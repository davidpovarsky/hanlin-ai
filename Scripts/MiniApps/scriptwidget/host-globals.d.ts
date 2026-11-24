/// <reference path="./components.d.ts" />
/// <reference path="./service-types.d.ts" />
/// <reference path="./original-api.d.ts" />
// Hanlin additions to the original installed native APIs; no parallel service stubs.
declare function $import(path: string): boolean;
declare function $render(element: JSX.Element): void;
declare function $error(message: string): void;
declare function $getenv(key: "presentation"): ScriptWidgetPresentationContext | "";
declare function $getenv(key: string): ScriptWidgetJSON;
declare const $widget: Readonly<Record<string, ScriptWidgetJSON | undefined>> & {readonly presentation?: ScriptWidgetPresentationContext};
declare function $fetch(url: string, options?: ScriptWidgetHTTPOptions): ScriptWidgetNativePromise<string>;
declare const fetch: typeof $fetch;

// Original support.bundle/util.js, evaluated by HanlinScriptWidgetRuntime.
declare class ScriptWidget {
  static readonly Fragment: "Fragment";
  static createElement<K extends keyof JSX.IntrinsicElements>(tag: K, props: JSX.IntrinsicElements[K] | null, ...children: JSX.Child[]): JSX.Element;
  static createElement<P>(tag: (props: P) => JSX.Element, props: P, ...children: JSX.Child[]): JSX.Element;
}
declare function $gradient(value: ScriptWidgetJSONObject): string;
declare function $animation(value: ScriptWidgetJSONObject): string;
declare function $json(value: ScriptWidgetJSON): string;
declare function $type_of_object(value: unknown): "undefined" | "object" | "boolean" | "number" | "bigint" | "string" | "symbol" | "function";
declare const $xml: { parse(source: string): ScriptWidgetXMLNode };
declare const $runtime: {
  readonly apiVersion: string;
  readonly limits: Readonly<{sourceBytes: number; transpiledBytes: number; executionMilliseconds: number; elementNodes: number; elementDepth: number; propsPerElement: number; systemDataQueries: number}>;
};
