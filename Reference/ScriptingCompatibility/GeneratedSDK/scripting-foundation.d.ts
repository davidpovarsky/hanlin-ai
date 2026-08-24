// Generated from scripting-compat-2026-08-25-0b7b8e715573. Do not edit.

export type JSONValue = null | boolean | number | string | JSONValue[] | { [key: string]: JSONValue }
export type ScriptEnvironment = "index" | "widget" | "intent" | "app_intents" | "assistant_tool" | "live_activity" | "control_widget" | "notification" | "keyboard" | "translation_ui_provider"
export type ResumeEventDetails = {
  resumeFromMinimized: boolean
  widgetParameter: string | null
  controlWidgetParameter: string | null
  queryParameters: Record<string, JSONValue> | null
}
export interface ScriptMetadata {
  readonly name: string
  readonly version: string
  readonly icon?: string
  readonly color?: string
  readonly description?: string
}
export const Script: {
  readonly env: ScriptEnvironment
  readonly name: string
  readonly metadata: ScriptMetadata
  readonly queryParameters: Record<string, JSONValue>
  onResume(callback: (details: ResumeEventDetails) => void): () => void
  exit(result?: JSONValue): void
}
export const console: {
  log(...values: unknown[]): void
  warn(...values: unknown[]): void
  error(...values: unknown[]): void
}
export function setTimeout(callback: () => void, milliseconds?: number): number
export function clearTimeout(id: number): void
export class URLSearchParams {
  constructor(init?: string | Record<string, string> | Iterable<[string, string]>)
  append(name: string, value: string): void
  get(name: string): string | null
  set(name: string, value: string): void
  toString(): string
}
export class URL {
  constructor(input: string, base?: string | URL)
  href: string
  readonly origin: string
  pathname: string
  search: string
  readonly searchParams: URLSearchParams
  toString(): string
}
export class TextEncoder { encode(input?: string): Uint8Array }
export class TextDecoder { constructor(label?: string); decode(input?: Uint8Array): string }
export class AbortSignal { readonly aborted: boolean; readonly reason: unknown }
export class AbortController { readonly signal: AbortSignal; abort(reason?: unknown): void }
export class Headers {
  constructor(init?: Headers | Record<string, string> | Iterable<[string, string]>)
  append(name: string, value: string): void
  get(name: string): string | null
  set(name: string, value: string): void
}
export interface RequestInit { method?: string; headers?: Headers | Record<string, string>; body?: string; signal?: AbortSignal }
export class Request { constructor(input: string | URL | Request, init?: RequestInit); readonly url: string; readonly method: string; readonly headers: Headers }
export class Response { readonly ok: boolean; readonly status: number; readonly headers: Headers; text(): Promise<string>; json(): Promise<JSONValue> }
export function fetch(input: string | URL | Request, init?: RequestInit): Promise<Response>
