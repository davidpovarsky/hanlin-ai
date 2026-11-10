const nativeAPIs = { Request, Response, Headers, FormData, File, Blob };
const { fetchImplementation, webAssemblyAvailable } = await import('../../fetch-compatibility.mjs');
for (const [name, value] of Object.entries(nativeAPIs)) assert.equal(globalThis[name], value);
import assert from 'node:assert/strict';
import http from 'node:http';
import { gzipSync } from 'node:zlib';
import { randomUUID } from 'node:crypto';
assert.equal(webAssemblyAvailable, false);
assert.equal(fetchImplementation, 'node-fetch@3.3.2+native-web-api');
const nonce = randomUUID();
const server = http.createServer(async (request, response) => {
  if (request.url === '/redirect') { response.writeHead(302, { location: '/echo' }); response.end(); return; }
  if (request.url === '/slow') return;
  if (request.url === '/empty') { response.writeHead(204); response.end(); return; }
  if (request.url === '/compressed') { response.setHeader('content-encoding', 'gzip'); response.end(gzipSync('שלום-' + nonce)); return; }
  if (request.url === '/missing') { response.writeHead(404); response.end('missing'); return; }
  if (request.url === '/stream') { response.write('first-' + nonce); setImmediate(() => response.end('-last')); return; }
  let body = '';
  for await (const chunk of request) body += chunk;
  response.setHeader('content-type', 'application/json');
  response.end(JSON.stringify({ method: request.method, body, nonce, contentType: request.headers['content-type'], header: request.headers['x-probe'] }));
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const base = `http://127.0.0.1:${server.address().port}`;
try {
  const get = await fetch(base + '/echo');
  await assert.rejects(fetch(base + '/echo', {dispatcher:{dispatch(){throw new Error('Unexpected fallback');}}}), /cannot execute an Undici dispatcher/);
  assert.ok(get instanceof Response);
  assert.equal((await get.json()).nonce, nonce);
  const request = new Request(base + '/echo', { method: 'POST', headers: new Headers({ 'x-probe': nonce }), body: 'שלום-' + nonce });
  const post = await fetch(request);
  assert.deepEqual(await post.json(), { method: 'POST', body: 'שלום-' + nonce, nonce, contentType: 'text/plain;charset=UTF-8', header: nonce });
  const redirect = await fetch(base + '/redirect');
  assert.equal(redirect.redirected, true);
  assert.equal(redirect.url, base + '/echo');
  assert.equal((await redirect.json()).nonce, nonce);
  const missing = await fetch(base + '/missing');
  assert.equal(missing.status, 404); assert.equal(missing.ok, false); assert.equal(await missing.text(), 'missing');
  const empty = await fetch(base + '/empty');
  assert.equal(empty.status, 204); assert.equal(empty.body, null); assert.equal(await empty.text(), '');
  const head = await fetch(base + '/echo', {method:'HEAD'});
  assert.equal(head.body, null); assert.equal(await head.text(), '');
  const streaming = await fetch(base + '/stream');
  const cloned = streaming.clone();
  const reader = streaming.body.getReader();
  let text = '';
  const decoder = new TextDecoder();
  while (true) { const {done, value} = await reader.read(); if (done) break; text += decoder.decode(value, {stream:true}); }
  text += decoder.decode();
  assert.equal(text, 'first-' + nonce + '-last');
  assert.equal(await cloned.text(), text);
  assert.equal(await (await fetch(base + '/compressed')).text(), 'שלום-' + nonce);
  const form = new FormData(); form.append('nonce', nonce); form.append('file', new File(['שלום'], 'probe.txt', {type:'text/plain'}));
  const multipart = await (await fetch(base + '/echo', { method:'POST', body:form })).json();
  assert.match(multipart.contentType, /^multipart\/form-data; boundary=/);
  assert.ok(multipart.body.includes(nonce) && multipart.body.includes('שלום'));
  await assert.rejects(fetch(base + '/slow', {signal:AbortSignal.timeout(100)}), error => ['TimeoutError', 'AbortError'].includes(error.name));
  console.log(JSON.stringify({passed:true, fetchImplementation, webAssemblyAvailable, nonce, contracts:['GET','Request POST Unicode','redirect','HTTP error','ReadableStream','clone','gzip','multipart File','abort','HEAD','204']}));
} finally {
  server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
}
