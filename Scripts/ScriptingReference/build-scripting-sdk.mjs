#!/usr/bin/env node

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const referenceRoot = path.join(repositoryRoot, 'Reference', 'ScriptingCompatibility');
const generatedRoot = path.join(referenceRoot, 'GeneratedSDK');
const packageResourceRoot = path.join(repositoryRoot, 'Packages', 'HanlinPlatform', 'Sources', 'HanlinScriptingSDK', 'Resources');
const check = process.argv.slice(2).includes('--check');

const baseline = await readJSON(path.join(referenceRoot, 'BASELINE.json'));
const inventory = await readJSON(path.join(referenceRoot, 'Generated', 'api-inventory.json'));
const overlay = await readJSON(path.join(referenceRoot, 'Overlays', 'foundation-runtime.json'));
if (baseline.typescriptPackageVersion !== '7.0.2') throw new Error('SDK generation requires the authorized TypeScript 7.0.2 baseline.');
if (inventory.baselineID !== baseline.baselineID) throw new Error('API inventory baseline mismatch.');
if (overlay.schemaVersion !== 1 || !Array.isArray(overlay.symbols)) throw new Error('Unsupported foundation runtime overlay.');

const records = overlay.symbols.map(entry => {
  const matches = inventory.symbols.filter(candidate => candidate.name === entry.symbol);
  if (matches.length === 0) throw new Error(`Foundation symbol is absent from the authorized baseline: ${entry.symbol}`);
  return {
    ...entry,
    declarationEvidence: matches.map(match => ({
      category: match.category,
      declarationFile: match.declarationFile,
      line: match.line,
      signatureHash: match.signatureHash,
    })).sort(compareEvidence),
  };
}).sort((left, right) => left.symbol.localeCompare(right.symbol));

const declarations = `// Generated from ${baseline.baselineID}. Do not edit.\n` + String.raw`
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
`;

const metadata = {
  schemaVersion: 1,
  baselineID: baseline.baselineID,
  baselineDigest: baseline.aggregateSHA256,
  typescriptVersion: baseline.typescriptPackageVersion,
  module: 'scripting',
  records,
};
const declarationsBytes = Buffer.from(declarations.replaceAll('\r\n', '\n'));
const metadataBytes = canonicalJSON(metadata);
const manifest = canonicalJSON({
  schemaVersion: 1,
  baselineID: baseline.baselineID,
  files: {
    'scripting-foundation.d.ts': sha256(declarationsBytes),
    'runtime-registration.json': sha256(metadataBytes),
  },
});
const outputs = new Map([
  ['scripting-foundation.d.ts', declarationsBytes],
  ['runtime-registration.json', metadataBytes],
  ['manifest.json', manifest],
]);

const drift = [];
for (const outputRoot of [generatedRoot, packageResourceRoot]) {
  await fs.mkdir(outputRoot, { recursive: true });
  for (const [name, bytes] of outputs) {
    const destination = path.join(outputRoot, name);
    if (check) {
      const existing = await fs.readFile(destination).catch(() => null);
      if (!existing || !existing.equals(bytes)) drift.push(path.relative(repositoryRoot, destination).replaceAll('\\', '/'));
    } else {
      await fs.writeFile(destination, bytes);
    }
  }
}
if (check && drift.length > 0) throw new Error(`Generated Scripting SDK drift: ${drift.join(', ')}`);
console.log(check ? `Generated Scripting SDK matches ${baseline.baselineID}.` : `Generated Scripting SDK for ${baseline.baselineID}.`);

function compareEvidence(left, right) {
  return `${left.declarationFile}:${left.line}:${left.category}`.localeCompare(`${right.declarationFile}:${right.line}:${right.category}`);
}
function canonicalJSON(value) { return Buffer.from(`${JSON.stringify(value, null, 2)}\n`); }
function sha256(value) { return crypto.createHash('sha256').update(value).digest('hex'); }
async function readJSON(file) { return JSON.parse(await fs.readFile(file, 'utf8')); }
