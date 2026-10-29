const fs = require('node:fs');
const vm = require('node:vm');
const cp = require('node:child_process');
const path = require('node:path');
const assert = require('node:assert/strict');

const source = fs.readFileSync(path.resolve(__dirname, '../src/engines/sefaria/client.js'), 'utf8');
const start = source.indexOf('async function requestJson(');
const end = source.indexOf('export async function search(', start);
assert(start !== -1 && end !== -1, 'Request wrapper must be present');
const requestSource = source.slice(start, end);
assert(!requestSource.includes('const response = await fetch(url, options)'), 'Never fetch directly from React Native');
let invoked = 0;
const hostServices = {
  async executeRuntime(kind, js, options) {
    assert.equal(kind, 'node');
    assert(options.limits.timeoutMilliseconds > 10000);
    assert(js.includes('https://www.sefaria.org'));
    invoked += 1;
    try {
      const stdout = cp.execFileSync(process.execPath, ['--input-type=module','--eval',js], {
        encoding: 'utf8', timeout: 29000, maxBuffer: 8 * 1024 * 1024
      });
      return { stdout, stderr: '', exitCode: 0, didTimeOut: false, wasCancelled: false, outputWasTruncated: false };
    } catch (e) {
      return { stdout: '', stderr: String(e.stderr || e.message), exitCode: 1 };
    }
  }
};
const fn = vm.runInNewContext('const SEFARIA_BASE_URL = "https://www.sefaria.org";\n' + requestSource + '\nrequestJson', { hostServices, JSON, String, Error, URLSearchParams });
(async () => {
  const payload = {
    query: 'שבת', type: 'text', field: 'naive_lemmatizer',
    start: 0, size: 1, slop: 10, sort_method: 'score',
    sort_fields: ['pagesheetrank'], sort_reverse: false,
    sort_score_missing: 0.04, source_proj: true, filters: [], filter_fields: [], aggs: ['path']
  };
  const data = await fn('https://www.sefaria.org/api/search-wrapper', {
    method: 'POST', body: JSON.stringify(payload)
  });
  assert(Array.isArray(data.hits.hits), 'Missing search hits');
  assert(data.hits.hits.length > 0, 'Expected real Sefaria search results');
  assert.equal(invoked, 1);
  console.log('PASS: Sefaria POST via isolated Node execution; hits=' + data.hits.hits.length);
  await assert.rejects(fn('https://example.org/api/search-wrapper'), /Only the Sefaria HTTPS API/);
  console.log('PASS: non-Sefaria host rejected');
})().catch(e => { console.error('FAIL:', e); process.exitCode=1; });
