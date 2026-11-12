import {test, before, after} from 'node:test';
import assert from 'node:assert/strict';
import {readFile, mkdir} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {chromium} from 'playwright-core';

const root = path.dirname(fileURLToPath(import.meta.url));
const resources = path.resolve(root, '../../AI_HLY/Downstream/ChatPresentation/CodeFences/Resources');
const evidence = path.resolve(root, '../../build/code-fence-browser-evidence');
let browser, page, requests = [];
before(async () => {
  await mkdir(evidence, {recursive: true});
  browser = await chromium.launch({channel: 'msedge', headless: true});
  page = await browser.newPage({viewport: {width: 1200, height: 900}});
  await page.route('**/*', route => { requests.push(route.request().url()); return route.abort(); });
  const js = (await readFile(path.join(resources, 'HanlinCodeFenceRenderer.js'), 'utf8')).replace(/<\/script/gi, '<\\/script');
  const css = await readFile(path.join(resources, 'HanlinCodeFenceRenderer.css'), 'utf8');
  await page.setContent(`<!doctype html><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'nonce-test'; style-src 'unsafe-inline'; img-src data:; font-src data:; connect-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'; object-src 'none'"><style>${css}</style><div id="render-host"></div><script nonce="test">${js}</script>`);
});
after(async () => { await browser?.close(); });

test('official Mermaid renders all required diagram families and Unicode labels', async () => {
  const fixtures = [
    ['flowchart', 'flowchart LR\nA["שלום🙂"] --> B["OAuth"]'],
    ['sequence', 'sequenceDiagram\nparticipant U as משתמש\nparticipant S as Server\nU->>S: OAuth2 request\nS-->>U: token response'],
    ['state', 'stateDiagram-v2\n[*] --> Pending\nPending --> Paid: approve\nPaid --> [*]'],
    ['class', 'classDiagram\nclass Order {\n+String id\n+submit()\n}\nOrder --> Customer'],
    ['er', 'erDiagram\nCUSTOMER ||--o{ ORDER : places\nCUSTOMER {\nstring name\n}'],
    ['gantt', 'gantt\ntitle Release\ndateFormat YYYY-MM-DD\nsection Work\nBuild :2026-11-12, 2d\nTest :2026-11-14, 1d'],
    ['pie', 'pie title Status\n"Done" : 60\n"Open" : 40']
  ];
  const rendered = [];
  for (const [name, source] of fixtures) {
    const result = await page.evaluate(args => window.hanlinRenderCodeFence(args), {kind: 'mermaid', source});
    assert.ok(result.html.includes('<svg'), name);
    assert.ok(result.height > 0 && result.width > 0, name);
    rendered.push(`<section><h2>${name}</h2>${result.html}</section>`);
  }
  await page.evaluate(markup => {
    const gallery = document.createElement('div'); gallery.id = 'gallery'; gallery.innerHTML = markup;
    gallery.style.cssText = 'display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:20px;background:white;color:black;padding:20px';
    document.body.append(gallery);
  }, rendered.join(''));
  const geometry = await page.evaluate(() => [...document.querySelectorAll('#gallery svg')].map(svg => {
    const box = svg.getBBox(), view = svg.viewBox.baseVal;
    return {id: svg.id, scale: svg.getBoundingClientRect().width / view.width,
      inside: box.x >= view.x - 8 && box.y >= view.y - 8 && box.x + box.width <= view.x + view.width + 8 && box.y + box.height <= view.y + view.height + 8};
  }));
  assert.equal(new Set(geometry.map(item => item.id)).size, fixtures.length);
  assert.ok(geometry.every(item => item.inside && item.scale <= 1.01), JSON.stringify(geometry));
  await page.addStyleTag({content: '#gallery svg {max-width:100% !important;height:auto}'});
  await page.screenshot({path: path.join(evidence, 'mermaid-families.png'), fullPage: true});
  await page.evaluate(() => document.getElementById('gallery').remove());
});

test('unified and split diff use the maintained parser and expose full long Unicode lines', async () => {
  const source = 'diff --git a/auth.ts b/auth.ts\n--- a/auth.ts\n+++ b/auth.ts\n@@ -1,2 +1,2 @@\n-old("שלום")\n+updated("שלום🙂")\n context\n';
  for (const split of [false, true]) {
    const result = await page.evaluate(args => window.hanlinRenderCodeFence(args), {kind: 'diff', source, split});
    assert.equal(result.files, 1);
    assert.ok(result.html.includes('d2h-ins') && result.html.includes('d2h-del'));
    const renderedText = await page.evaluate(markup => {
      const template = document.createElement('template'); template.innerHTML = markup;
      return template.content.textContent;
    }, result.html);
    assert.ok(renderedText.includes('שלום🙂') && renderedText.includes('auth.ts'));
    assert.ok(result.html.includes('d2h-code-linenumber') || result.html.includes('d2h-code-side-linenumber'));
  }
  const long = 'x'.repeat(2000);
  const lines = Array.from({length: 1000}, (_, i) => `-before${i}\n+after${i} שלום`).join('\n');
  const sourceLarge = `--- a/large.txt\n+++ b/large.txt\n@@ -1,1000 +1,1000 @@\n${lines}\n`;
  const result = await page.evaluate(args => window.hanlinRenderCodeFence(args), {kind: 'diff', source: sourceLarge});
  assert.ok(result.html.includes('after999') && result.html.includes('before999'));
  const lineResult = await page.evaluate(args => window.hanlinRenderCodeFence(args), {kind: 'diff', source: `--- a/x\n+++ b/x\n@@ -1 +1 @@\n-${long}\n+${long}y\n`});
  assert.ok(lineResult.html.includes(long));
});

test('active content, navigation references and init directives cannot enable external resources', async () => {
  const source = '%%{init: {"securityLevel":"loose","themeCSS":"@import url(https://attack.invalid/font)"}}%%\nflowchart LR\nA["<img src=\'https://attack.invalid/image\' onerror=\'window.pwned=true\'>"] --> B["שלום"]\nclick A "https://attack.invalid/link"';
  const result = await page.evaluate(args => window.hanlinRenderCodeFence(args), {kind: 'mermaid', source});
  await page.evaluate(markup => { document.getElementById('render-host').innerHTML = markup; }, result.html);
  const state = await page.evaluate(() => ({pwned: window.pwned === true,
    active: document.querySelectorAll('#render-host script,#render-host iframe,#render-host img,#render-host foreignObject').length,
    external: [...document.querySelectorAll('#render-host [href],#render-host [xlink\\:href]')].some(n => [...n.attributes].some(a => ['href', 'xlink:href'].includes(a.name) && !a.value.startsWith('#')))}));
  assert.deepEqual(state, {pwned: false, active: 0, external: false});
  await page.evaluate(() => { fetch('https://attack.invalid/fetch').catch(() => {}); new Image().src = 'https://attack.invalid/pixel'; });
  assert.deepEqual(requests, []);
});

test('malformed inputs fail explicitly and vendored asset hashes match', async () => {
  await assert.rejects(page.evaluate(args => window.hanlinRenderCodeFence(args), {kind: 'diff', source: 'not a unified diff'}));
  await assert.rejects(page.evaluate(args => window.hanlinRenderCodeFence(args), {kind: 'mermaid', source: 'sequenceDiagram\nINVALID ->'}));
  const manifest = JSON.parse(await readFile(path.join(resources, 'HanlinCodeFenceAssets.json'), 'utf8'));
  for (const file of manifest.files) {
    const data = await readFile(path.join(resources, file.name));
    assert.equal(data.length, file.bytes);
    assert.equal(createHash('sha256').update(data).digest('hex'), file.sha256);
  }
  assert.deepEqual(requests, []);
});
