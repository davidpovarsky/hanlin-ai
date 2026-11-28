const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { pathToFileURL } = require('node:url');

const root = path.resolve(__dirname, '..');
const file = fs.readFileSync(path.join(root, 'src/engines/sefaria/nativeTransport.js'), 'utf8');
const code = file
  .replace(/^import[^\n]*\n/gm, '')
  .replace(/^export async function /gm, 'async function ');
const grants = { 'ios-native-api': true, network: true };
const calls = [];
let setupCount = 0;
let callbackCount = 0;

const nativeFoundation = {
  NSURL: {
    URLWithString(value) { return { url: String(value) }; }
  },
  NSMutableURLRequest: {
    requestWithURL(nativeUrl) {
      const headers = {};
      return {
        url: nativeUrl.url, headers, HTTPMethod: 'GET',
        setValueForHTTPHeaderField(value, field) { headers[field] = value; }
      };
    }
  },
  NSString: {
    stringWithString(value) {
      return { dataUsingEncoding(encoding) {
        assert.equal(encoding, 4);
        return Buffer.from(String(value), 'utf8');
      } };
    },
    alloc() {
      return { initWithDataEncoding(data, encoding) {
        assert.equal(encoding, 4);
        return Buffer.from(data).toString('utf8');
      } };
    }
  },
  NSURLSession: {
    sharedSession: {
      dataTaskWithRequestCompletionHandler(request, callback) {
        assert(request.url.startsWith('https://www.sefaria.org/api/'));
        calls.push(request);
        return {
          resume() {
            (async () => {
              const response = await fetch(request.url, {
                method: request.HTTPMethod,
                headers: request.headers,
                body: request.HTTPBody
              });
              callbackCount++;
              callback(Buffer.from(await response.text(), 'utf8'),
                { statusCode: response.status }, null);
            })().catch(error => {
              callbackCount++;
              callback(null, null, { localizedDescription: error.message });
            });
          },
          cancel() {}
        };
      }
    }
  }
};
const sandbox = {
  ...nativeFoundation, console, URL, String, Number, Boolean, Error, JSON,
  Promise, setTimeout, clearTimeout, Buffer,
  hostServices: { async hasCapability(name) { return Boolean(grants[name]); } },
  init(_path, options) {
    assert.equal(options.globals, true);
    setupCount++;
    return true;
  },
  jsInvoker(callback) {
    assert.equal(typeof callback, 'function');
    return callback;
  }
};
const request = vm.runInNewContext(code + '\nrequestJson', sandbox);

(async () => {
  const payload = {
    query: 'חיים', type: 'text', field: 'naive_lemmatizer',
    start: 0, size: 10, slop: 10,
    sort_method: 'score', sort_fields: ['pagesheetrank'],
    sort_reverse: false, sort_score_missing: 0.04,
    source_proj: true, filters: [], filter_fields: [], aggs: ['path']
  };
  const result = await request('https://www.sefaria.org/api/search-wrapper', {
    method: 'POST', body: JSON.stringify(payload)
  });
  assert(Array.isArray(result.hits?.hits));
  assert(result.hits.hits.length > 0, 'Expected live Sefaria results');
  assert.equal(calls[0].HTTPMethod, 'POST');
  assert.equal(calls[0].headers['Content-Type'], 'application/json');
  assert.equal(callbackCount, 1);
  assert.equal(setupCount, 1);
  console.log('PASS: native NSURLSession POST -> callback -> Sefaria hits=' + result.hits.hits.length);

  const fullText = await request('https://www.sefaria.org/api/v3/texts/Genesis%201%3A1?version=source&return_format=text_only');
  assert(Array.isArray(fullText.versions) && fullText.versions.length > 0, 'Expected Sefaria full-text versions');
  assert.equal(calls[1].HTTPMethod, 'GET');
  console.log('PASS: native NSURLSession GET -> Sefaria full-text versions=' + fullText.versions.length);
  await assert.rejects(request('https://www.google.com/api/search-wrapper'),
    /Only https:\/\/www.sefaria.org/);
  await assert.rejects(request('https://www.sefaria.org/library'),
    /Only Sefaria API paths/);
  grants.network = false;
  await assert.rejects(request('https://www.sefaria.org/api/search-wrapper'),
    /Missing required permission: network/);
  console.log('PASS: host allow-list and network-capability rejection');
})().catch(error => {
  console.error('FAIL:', error?.stack || error);
  process.exitCode = 1;
});
