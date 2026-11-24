import test from 'node:test';
import assert from 'node:assert/strict';
import {fetchOriginalResponse} from '../upstream-fetch.mjs';

function credentials(t, {gh = 'job-test-token', github = 'fallback-test-token'} = {}) {
  const saved = {GH_TOKEN: process.env.GH_TOKEN, GITHUB_TOKEN: process.env.GITHUB_TOKEN};
  for (const [name, value] of Object.entries({GH_TOKEN: gh, GITHUB_TOKEN: github})) {
    if (value == null) delete process.env[name]; else process.env[name] = value;
  }
  t.after(() => {
    for (const [name, value] of Object.entries(saved)) {
      if (value == null) delete process.env[name]; else process.env[name] = value;
    }
  });
}

test('exact GitHub API source requests use the existing job token and retain response bytes', async t => {
  credentials(t);
  const expected = new Response(new Uint8Array([0, 255, 3, 128]));
  const url = 'https://api.github.com/repos/everettjf/scriptwidget/git/trees/' + '4'.repeat(40) + '?recursive=1';
  t.mock.method(globalThis, 'fetch', async (actual, options) => {
    assert.equal(actual, url);
    assert.equal(options.headers.Authorization, 'Bearer job-test-token');
    assert.equal(options.headers.Accept, 'application/vnd.github+json');
    assert.equal(options.headers['User-Agent'], 'Hanlin-MiniApp-Upstream-Resolver');
    assert.ok(options.signal instanceof AbortSignal);
    return expected;
  });
  const response = await fetchOriginalResponse(url);
  assert.equal(response, expected);
  assert.deepEqual([...new Uint8Array(await response.arrayBuffer())], [0, 255, 3, 128]);
});

test('raw sources and artifact hosts never receive the GitHub credential', async t => {
  credentials(t);
  const urls = [
    'https://raw.githubusercontent.com/everettjf/scriptwidget/commit/file.swift',
    'https://registry.npmjs.org/expo/-/expo-58.0.26.tgz',
    'https://api.github.com.example.test/tree',
    'http://api.github.com/repos/example/tree',
    'https://api.github.com:444/repos/example/tree'
  ];
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    assert.ok(urls.includes(url));
    assert.equal(options.headers.Authorization, undefined);
    assert.equal(options.headers.Accept, 'application/json');
    return new Response('original');
  });
  for (const url of urls) assert.equal(await (await fetchOriginalResponse(url, {accept: 'application/json'})).text(), 'original');
});

test('the conventional GITHUB_TOKEN is used when GH_TOKEN is absent or blank', async t => {
  credentials(t, {gh: '   ', github: 'fallback-test-token'});
  t.mock.method(globalThis, 'fetch', async (_, options) => {
    assert.equal(options.headers.Authorization, 'Bearer fallback-test-token');
    return new Response('{}');
  });
  await fetchOriginalResponse('https://api.github.com/repos/example/source');
});

test('a GitHub403 retains its actual reason and rate metadata without exposing credentials', async t => {
  credentials(t);
  let calls = 0;
  t.mock.method(globalThis, 'fetch', async () => {
    calls++;
    return new Response(JSON.stringify({message: 'Resource not accessible by integration. job-test-token\nfallback-test-token'}), {
      status: 403, headers: {'x-ratelimit-remaining': '17', 'x-ratelimit-reset': '1795482000', 'retry-after': '60'}
    });
  });
  await assert.rejects(fetchOriginalResponse('https://api.github.com/repos/example/source?recursive=1&token=job-test-token'), error => {
    assert.match(error.message, /Original source fetch failed \(403\)/);
    assert.match(error.message, /Resource not accessible by integration/);
    assert.match(error.message, /x-ratelimit-remaining=17/);
    assert.match(error.message, /x-ratelimit-reset=1795482000/);
    assert.match(error.message, /retry-after=60/);
    assert.match(error.message, /recursive=1/);
    assert.doesNotMatch(error.message, /job-test-token|fallback-test-token|\n|API rate limit exceeded/);
    return true;
  });
  assert.equal(calls, 1, 'Failures must not silently retry with old inputs or anonymous credentials');
});

test('a malformed GitHub error body still reports the failed source and HTTP status', async t => {
  credentials(t, {gh: null, github: null});
  t.mock.method(globalThis, 'fetch', async (_, options) => {
    assert.equal(options.headers.Authorization, undefined);
    return new Response('upstream gateway unavailable', {status: 502});
  });
  await assert.rejects(fetchOriginalResponse('https://api.github.com/repos/example/source'), /Original source fetch failed \(502\): https:\/\/api.github.com\/repos\/example\/source$/);
});
