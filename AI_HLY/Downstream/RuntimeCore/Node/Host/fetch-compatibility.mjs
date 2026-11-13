import { Readable } from 'node:stream';

// Undici's HTTP/1 parser needs WebAssembly. Older mobile bundles lack its
// interpreter; newer candidates must prove it on the actual engine. Select once
// before user code, without retries
// through another runtime. Keep Node's web API classes and stream semantics.
export const webAssemblyAvailable = typeof WebAssembly !== 'undefined';
export const fetchImplementation = webAssemblyAvailable ? 'node-undici' : 'node-fetch@3.3.2+native-web-api';
if (!webAssemblyAvailable) {
  const { default: transportFetch } = await import('node-fetch');
  globalThis.fetch = async function fetch(input, init) {
    if (init?.dispatcher != null) throw new TypeError('This Fetch transport cannot execute an Undici dispatcher; a verified WASM-enabled native transport is required.');
    const request = new Request(input, init);
    if (request.integrity) throw new TypeError('Fetch integrity validation is unavailable in JITless Node.');
    let response;
    try {
      response = await transportFetch(request.url, {
        method: request.method, headers: [...request.headers],
        body: request.body ? Readable.fromWeb(request.body) : undefined,
        signal: request.signal, redirect: request.redirect,
      });
    } catch (cause) {
      if (request.signal.aborted) throw request.signal.reason;
      throw new TypeError('fetch failed', { cause });
    }
    const noBody = request.method === 'HEAD' || [204, 205, 304].includes(response.status);
    if (noBody) response.body?.resume();
    const headers = Object.entries(response.headers.raw()).flatMap(([name, values]) => values.map(value => [name, value]));
    const nativeResponse = new Response(noBody || !response.body ? null : Readable.toWeb(response.body), {
      status: response.status, statusText: response.statusText, headers,
    });
    return withResponseMetadata(nativeResponse, { url: response.url, redirected: response.redirected, type: 'basic' });
  };
}

function withResponseMetadata(response, metadata) {
  for (const [key, value] of Object.entries(metadata)) Object.defineProperty(response, key, { value, configurable: true });
  const clone = response.clone.bind(response);
  Object.defineProperty(response, 'clone', { value: () => withResponseMetadata(clone(), metadata), configurable: true });
  return response;
}
