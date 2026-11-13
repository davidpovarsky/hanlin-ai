import { fetchImplementation, webAssemblyAvailable } from './fetch-compatibility.mjs';
import dns from 'node:dns';
import https from 'node:https';
import net from 'node:net';
import tls from 'node:tls';
import { randomUUID } from 'node:crypto';

export function networkError(error, depth = 0, seen = new Set()) {
  if (error == null || depth > 5) return null;
  if (typeof error !== 'object') return { message: String(error).slice(0, 1024) };
  if (seen.has(error)) return { message: '[circular cause]' };
  seen.add(error);
  const value = {};
  for (const key of ['name', 'message', 'code', 'errno', 'syscall', 'address', 'port']) {
    if (['string', 'number'].includes(typeof error[key])) value[key] = String(error[key]).slice(0, 1024);
  }
  if (error.cause) value.cause = networkError(error.cause, depth + 1, seen);
  if (Array.isArray(error.errors)) value.errors = error.errors.slice(0, 8).map(item => networkError(item, depth + 1, seen));
  return value;
}

// Sends only generated challenge data. Neither request headers nor echoed user
// information/IP addresses are retained. TLS verification stays enabled.
export async function probeNodeHTTPS({ endpoint = 'https://httpbingo.org/anything', rounds = 2, timeoutMilliseconds = 8000 } = {}) {
  const base = new URL(endpoint);
  if (base.protocol !== 'https:' || base.username || base.password) throw new Error('Use an HTTPS echo endpoint without credentials.');
  const count = Math.min(5, Math.max(1, Number(rounds) || 1));
  const timeout = Math.min(15000, Math.max(1000, Number(timeoutMilliseconds) || 8000));
  const report = {
    schemaVersion: 1, runID: randomUUID(), host: base.hostname,
    fetchImplementation, webAssemblyAvailable,
    runtime: { node: process.versions.node, openssl: process.versions.openssl, uv: process.versions.uv, platform: process.platform },
    dnsOrder: dns.getDefaultResultOrder(), autoSelectFamily: net.getDefaultAutoSelectFamily(),
    rootCACount: tls.getCACertificates('default').length,
    resourcesBefore: process.getActiveResourcesInfo(), dns: null, requests: [],
  };
  let dnsTimer;
  try {
    report.dns = await Promise.race([
      dns.promises.lookup(base.hostname, { all: true }),
      new Promise((_, reject) => { dnsTimer = setTimeout(() => reject(Object.assign(new Error('DNS lookup timed out'), { code: 'DNS_PROBE_TIMEOUT' })), timeout); }),
    ]);
  } catch (error) { report.dns = { error: networkError(error) }; }
  finally { clearTimeout(dnsTimer); }

  for (let round = 0; round < count; round += 1) {
    for (const client of ['fetch', 'https']) {
      for (const method of ['GET', 'POST']) {
        const nonce = randomUUID();
        const url = new URL(base);
        url.searchParams.set('hanlin_probe', nonce);
        const body = method === 'POST' ? JSON.stringify({ nonce, text: 'שלום' }) : undefined;
        const started = Date.now();
        let responseMetadata = {};
        try {
          const response = client === 'fetch'
            ? await fetchResponse(url, method, body, timeout)
            : await httpsResponse(url, method, body, timeout);
          responseMetadata = { status: response.status, bytes: Buffer.byteLength(response.body) };
          const decoded = JSON.parse(response.body);
          const echoed = decoded.args?.hanlin_probe;
          const nonceMatched = (Array.isArray(echoed) ? echoed[0] : echoed) === nonce
            && decoded.method === method && (method !== 'POST' || (decoded.json?.nonce === nonce && decoded.json?.text === 'שלום'));
          report.requests.push({ round, client, method, status: response.status,
            bytes: Buffer.byteLength(response.body), nonceMatched,
            passed: response.status === 200 && nonceMatched, milliseconds: Date.now() - started });
        } catch (error) {
          report.requests.push({ round, client, method, ...responseMetadata, passed: false, error: networkError(error), milliseconds: Date.now() - started });
        }
      }
    }
  }
  report.resourcesAfter = process.getActiveResourcesInfo();
  report.passed = report.requests.length === count * 4 && report.requests.every(request => request.passed);
  // Resource names are diagnostic observations, not proof of descriptor ownership.
  return report;
}

async function fetchResponse(url, method, body, timeout) {
  const response = await fetch(url, { method, body,
    headers: { 'user-agent': 'Hanlin-Node-HTTPS-Diagnostic/1', ...(body ? { 'content-type': 'application/json' } : {}) }, signal: AbortSignal.timeout(timeout) });
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.length > 65536) throw new Error('Echo response exceeds 64 KiB.');
  return { status: response.status, body: Buffer.from(bytes).toString('utf8') };
}

function httpsResponse(url, method, body, timeout) {
  return new Promise((resolve, reject) => {
    const request = https.request(url, { method, agent: false,
      headers: { 'user-agent': 'Hanlin-Node-HTTPS-Diagnostic/1', ...(body ? { 'content-type': 'application/json', 'content-length': Buffer.byteLength(body) } : {}) } }, response => {
      const chunks = [];
      let size = 0;
      response.on('data', chunk => {
        size += chunk.length;
        if (size > 65536) request.destroy(new Error('Echo response exceeds 64 KiB.'));
        else chunks.push(chunk);
      });
      response.once('error', reject);
      response.once('end', () => resolve({ status: response.statusCode, body: Buffer.concat(chunks).toString('utf8') }));
    });
    const timer = setTimeout(() => request.destroy(Object.assign(new Error('HTTPS request timed out'), { code: 'HTTPS_PROBE_TIMEOUT' })), timeout);
    request.once('close', () => clearTimeout(timer));
    request.once('error', reject);
    request.end(body);
  });
}
