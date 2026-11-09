import test from 'node:test';
import assert from 'node:assert/strict';
import net from 'node:net';
import { networkError, probeNodeHTTPS } from '../network-diagnostics.mjs';

test('network diagnostics preserve bounded cyclic AggregateError cause codes', () => {
  const socket = Object.assign(new Error('connection refused'), { code: 'ECONNREFUSED', syscall: 'connect' });
  const error = new TypeError('fetch failed', { cause: new AggregateError([socket], 'all addresses failed') });
  socket.cause = error;
  const result = networkError(error);
  assert.equal(result.cause.errors[0].code, 'ECONNREFUSED');
  assert.equal(result.cause.errors[0].cause.message, '[circular cause]');
  assert.ok(JSON.stringify(result).length < 4096);
});

test('the HTTPS diagnostic never disables TLS or accepts credential-bearing echo URLs', async () => {
  await assert.rejects(probeNodeHTTPS({ endpoint: 'http://localhost' }), /HTTPS/);
  await assert.rejects(probeNodeHTTPS({ endpoint: 'https://user:secret@localhost' }), /credentials/);
});

test('real TLS handshake failures remain failures for both fetch and node:https GET/POST', { timeout: 10000 }, async () => {
  const server = net.createServer(socket => socket.end('HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n', () => socket.destroy()));
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    const report = await probeNodeHTTPS({ endpoint: `https://127.0.0.1:${server.address().port}/echo`, rounds: 1 });
    assert.equal(report.passed, false);
    assert.equal(report.requests.length, 4);
    assert.deepEqual(new Set(report.requests.map(item => item.client)), new Set(['fetch', 'https']));
    assert.ok(report.requests.every(item => item.passed === false && item.error));
    for (const request of report.requests) {
      if (request.client === 'fetch') assert.match(request.error.cause.code, /^ERR_SSL_/);
      else assert.match(request.error.code, /^(ERR_SSL_|EPROTO$)/);
    }
    assert.equal(typeof report.rootCACount, 'number');
    assert.ok(Array.isArray(report.resourcesAfter));
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});
