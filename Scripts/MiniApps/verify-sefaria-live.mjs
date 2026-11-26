import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const requests = [];
async function request(url, options) {
  const started = performance.now();
  const response = await fetch(url, { ...options, signal: AbortSignal.timeout(25_000) });
  const body = await response.text();
  requests.push({ method: options.method || 'GET', url, status: response.status,
    milliseconds: Math.round(performance.now() - started), bytes: Buffer.byteLength(body),
    sha256: crypto.createHash('sha256').update(body).digest('hex') });
  if (!response.ok) throw new Error('Sefaria HTTP ' + response.status + ': ' + body.slice(0, 200));
  return { status: response.status, body };
}
// The retained client calls exactly the original ScriptWidget $http contract.
// This verification adapts only that transport to real Node HTTPS; Apple CI
// separately tests original JavaScriptCore and native provider execution.
globalThis.$http = {
  post: async (url, options = {}) => (await request(url, { ...options, method: 'POST' })).body,
  getResponse: async (url, options = {}) => request(url, { ...options, method: 'GET' })
};
const client = await import(pathToFileURL(path.join(root,
  'Scripts/Expo/miniapps/modular-text-search/native/src/engines/sefaria/client.js')));
const { cloneDefaultSearchOptions, cloneDefaultTextOptions } = await import(pathToFileURL(path.join(root,
  'Scripts/Expo/miniapps/modular-text-search/native/src/engines/registry.js')));
const query = 'בראשית';
const response = await client.search({ ...cloneDefaultSearchOptions(), query, size: 2 });
assert.ok(response.results.length > 0, 'The public search returned no results');
const source = response.results.find(item => typeof item.ref === 'string' && item.ref);
assert.ok(source, 'Search did not expose a text reference');
const text = await client.getText(source.ref, cloneDefaultTextOptions());
assert.ok(text.versions.length > 0, 'Full text returned no versions');
assert.ok(text.versions.some(version => version.text.length > 0), 'All returned versions were empty');
console.log(JSON.stringify({
  verifiedAt: new Date().toISOString(),
  execution: 'Retained original modular engine/client using actual public HTTPS with Node transport; not an Apple device test.',
  query, resultCount: response.results.length, total: response.total, reference: source.ref,
  textReference: text.ref,
  versions: text.versions.map(version => ({ language: version.language, title: version.versionTitle,
    characterCount: version.text.length })),
  requests
}, null, 2));
