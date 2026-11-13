import assert from 'node:assert/strict';
import https from 'node:https';
import http from 'node:http';
import net from 'node:net';
import {createHash, randomUUID} from 'node:crypto';
import {gzipSync} from 'node:zlib';

// Test-only, controlled loopback transport. Agent constructors come from the
// actual locked Host dependency, and all assertions use global native Fetch.
export async function runFetchConformance({Agent, ProxyAgent, tlsFixture}) {
  assert.equal(typeof WebAssembly, 'object');
  const nonce = randomUUID();
  const content = 'שלום-' + nonce;
  const contracts = [];
  let originRequests = 0;
  const tunnels = [];
  const sockets = new Set();
  const origin = https.createServer({key: tlsFixture.key, cert: tlsFixture.cert}, async (request, response) => {
    originRequests++;
    if (request.url === '/slow') return;
    if (request.url === '/body') return response.end(content);
    if (request.url === '/gzip') {response.setHeader('content-encoding', 'gzip'); return response.end(gzipSync(content));}
    if (request.url === '/stream') {response.write(content); return setImmediate(() => response.end('-last'));}
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    response.setHeader('content-type', 'application/json');
    response.end(JSON.stringify({nonce, method: request.method, body: Buffer.concat(chunks).toString('utf8'), contentType: request.headers['content-type']}));
  });
  const proxy = http.createServer((_request, response) => {response.writeHead(405); response.end();});
  const track = socket => {sockets.add(socket); socket.on('close', () => sockets.delete(socket)); socket.on('error', () => {});};
  origin.on('connection', track);
  proxy.on('connection', track);
  await new Promise(resolve => origin.listen(0, '127.0.0.1', resolve));
  const port = origin.address().port;
  let rejectTunnel = false;
  proxy.on('connect', (request, client, head) => {
    tunnels.push(request.url);
    if (rejectTunnel || request.url !== `origin.invalid:${port}`) return client.end('HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n');
    const upstream = net.connect(port, '127.0.0.1');
    track(upstream);
    upstream.on('connect', () => {
      client.write('HTTP/1.1 200 Connection Established\r\n\r\n');
      if (head.length) upstream.write(head);
      client.pipe(upstream); upstream.pipe(client);
    });
    client.on('close', () => upstream.destroy());
    upstream.on('error', () => client.destroy());
  });
  await new Promise(resolve => proxy.listen(0, '127.0.0.1', resolve));
  const trusted = new Agent({connect: {ca: tlsFixture.ca}});
  const proxied = new ProxyAgent({uri: `http://127.0.0.1:${proxy.address().port}`, requestTls: {ca: tlsFixture.ca}});
  let rejectedProxy;
  try {
    const base = `https://127.0.0.1:${port}`;
    const nativeAPIs = {Request, Response, Headers, FormData, File, Blob};
    assert.equal((await (await fetch(base + '/echo', {dispatcher: trusted})).json()).nonce, nonce);
    const post = await fetch(new Request(base + '/echo', {method: 'POST', body: content}), {dispatcher: trusted});
    assert.ok(post instanceof Response);
    assert.deepEqual(await post.json(), {nonce, method: 'POST', body: content, contentType: 'text/plain;charset=UTF-8'});
    contracts.push('TLS GET', 'TLS Request POST');

    // No global TLS override: the same local certificate remains untrusted by default.
    await assert.rejects(fetch(base + '/body'), error => /SELF_SIGNED|CERT_/.test(error.cause?.code ?? ''));
    contracts.push('untrusted TLS rejected');
    const integrity = 'sha384-' + createHash('sha384').update(content).digest('base64');
    assert.equal(await (await fetch(base + '/body', {dispatcher: trusted, integrity})).text(), content);
    await assert.rejects(fetch(base + '/body', {dispatcher: trusted, integrity: 'sha384-' + Buffer.alloc(48).toString('base64')}));
    contracts.push('SRI match', 'SRI mismatch rejected');

    const isolated = `https://origin.invalid:${port}`;
    const beforeDirect = originRequests;
    await assert.rejects(fetch(isolated + '/echo', {dispatcher: trusted, signal: AbortSignal.timeout(5000)}));
    assert.equal(originRequests, beforeDirect);
    assert.equal((await (await fetch(isolated + '/echo', {dispatcher: proxied})).json()).nonce, nonce);
    assert.deepEqual(tunnels, [`origin.invalid:${port}`]);
    assert.equal(originRequests, beforeDirect + 1);
    contracts.push('Proxy CONNECT actual route');
    rejectTunnel = true;
    rejectedProxy = new ProxyAgent({uri: `http://127.0.0.1:${proxy.address().port}`, requestTls: {ca: tlsFixture.ca}});
    const beforeReject = originRequests;
    await assert.rejects(fetch(isolated + '/echo', {dispatcher: rejectedProxy, signal: AbortSignal.timeout(5000)}));
    assert.equal(originRequests, beforeReject);
    assert.equal(tunnels.length, 2);
    contracts.push('Proxy failure has no direct fallback');

    const streaming = await fetch(base + '/stream', {dispatcher: trusted});
    const clone = streaming.clone();
    const reader = streaming.body.getReader();
    const decoder = new TextDecoder();
    let body = '';
    while (true) {const {done, value} = await reader.read(); if (done) break; body += decoder.decode(value, {stream:true});}
    body += decoder.decode();
    assert.equal(body, content + '-last');
    assert.equal(await clone.text(), body);
    assert.equal(await (await fetch(base + '/gzip', {dispatcher: trusted})).text(), content);
    contracts.push('TLS stream', 'TLS clone', 'TLS gzip');
    const form = new FormData();
    form.append('nonce', nonce); form.append('file', new File(['שלום'], 'probe.txt', {type:'text/plain'}));
    const multipart = await (await fetch(base + '/echo', {method:'POST', body:form, dispatcher:trusted})).json();
    assert.match(multipart.contentType, /^multipart\/form-data; boundary=/);
    assert.ok(multipart.body.includes(nonce) && multipart.body.includes('שלום'));
    await assert.rejects(fetch(base + '/slow', {dispatcher:trusted, signal:AbortSignal.timeout(100)}), error => ['TimeoutError','AbortError'].includes(error.name));
    contracts.push('TLS multipart File', 'TLS abort');
    for (const [name,value] of Object.entries(nativeAPIs)) assert.equal(globalThis[name], value);
    return {passed:true, nonce, contracts, tunnels, originRequests, nodeVersion:process.versions.node, wasm:true};
  } finally {
    await Promise.allSettled([trusted.destroy(), proxied.destroy(), rejectedProxy?.destroy()]);
    for (const socket of sockets) socket.destroy();
    await Promise.all([new Promise(resolve => origin.close(resolve)), new Promise(resolve => proxy.close(resolve))]);
  }
}
