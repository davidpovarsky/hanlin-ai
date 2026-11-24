import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const compilerRoot = path.join(root, 'Packages/HanlinPlatform/Sources/HanlinWidgetCompiler/Resources');
const babel = fs.readFileSync(path.join(compilerRoot, 'core.js'), 'utf8');
const compiler = fs.readFileSync(path.join(compilerRoot, 'prepare-widget.js'), 'utf8');
const compilerVM = vm.createContext({ __scriptWidgetCompileActive: () => true });
vm.runInContext(babel, compilerVM);
vm.runInContext(compiler, compilerVM);

function compile(input) {
  return compilerVM.__hanlinCompileWidget(input);
}

function execution(program, action = '', parameters = null, values = {}, globals = {}) {
  let rendered;
  let failure;
  const context = vm.createContext({
    ScriptWidget: {
      createElement: (tag, props, ...children) => ({ tag, props, children }),
      Fragment: 'Fragment'
    },
    __scriptWidgetCheckExecution() {},
    __hanlinAction: action,
    __hanlinEvent: { parameters },
    $storage: { get: key => values[key] ?? null, set: (key, value) => { values[key] = value; } },
    $render: node => { rendered = node; },
    $error: reason => { failure = reason; },
    ...globals
  });
  vm.runInContext(program, context);
  return context.$main().then(() => {
    if (failure) throw new Error(failure);
    return { rendered, values };
  });
}

test('original ScriptWidget compiler bundles typed local modules and action parameters', async () => {
  const program = compile({
    engine: 'scriptwidget', format: 'tsx', entry: 'native/panel.tsx',
    files: {
      'native/panel.tsx': 'import { label } from "./format"; export async function choose(event: { parameters: { id: string } }) { await Promise.resolve(); $storage.set("selected",event.parameters.id); } export default function render() { $render(<text>{label($storage.get("selected"))}</text>); }',
      'native/format.ts': 'export function label(value: unknown): string { return "מקור " + String(value ?? "none"); }',
      'bundle.js': 'THIS FOREGROUND BUNDLE IS NOT A NATIVE MODULE'
    },
    actions: [{ id: 'choose', kind: 'function', handler: 'choose' }]
  });
  const result = await execution(program, 'choose', { id: 'Berakhot 2a' });
  assert.equal(result.values.selected, 'Berakhot 2a');
  assert.equal(result.rendered.tag, 'text');
  assert.equal(result.rendered.children[0], 'מקור Berakhot 2a');
});

test('module closure does not resolve framework imports into the frozen Scripting engine', () => {
  assert.throws(() => compile({
    engine: 'scriptwidget', format: 'jsx', entry: 'native/panel.jsx',
    files: { 'native/panel.jsx': 'import { Text } from "scripting"; export default function render(){ $render(<Text>bad</Text>); }' },
    actions: []
  }), /Unsupported ScriptWidget import: scripting/);
});

test('original Expo layout compiler uses a declared JSON-suffixed entry expression', () => {
  const program = compile({
    engine: 'expo', format: 'expo-layout', entry: 'native/layout.json',
    files: {'native/layout.json': 'props => ({type: "TextView", props: {text: props.label}})'}, actions: []
  });
  const context = vm.createContext({__scriptWidgetCheckExecution() {}});
  const layout = vm.runInContext(program, context);
  assert.equal(layout({label: 'מקור מקורי'}).props.text, 'מקור מקורי');
});

test('ordinary original ScriptWidget top-level async source remains executable', async () => {
  const program = compile({
    engine: 'scriptwidget', format: 'jsx', entry: 'widget.jsx',
    files: { 'widget.jsx': 'const value = await Promise.resolve("ready"); $render(<text>{value}</text>);' },
    actions: []
  });
  const result = await execution(program);
  assert.equal(result.rendered.children[0], 'ready');
});

test('ported attachment executes grouped search, version expansion, full text, pagination and replacement', async () => {
  const sample = path.join(root, 'Scripts/Expo/miniapps/modular-text-search');
  const manifest = JSON.parse(fs.readFileSync(path.join(sample, 'script.json'), 'utf8'));
  const declaration = manifest.nativePresentations.appIntents;
  const files = {};
  function read(directory) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const file = path.join(directory, entry.name);
      if (entry.isDirectory()) read(file);
      else if (/\.[jt]sx?$/.test(file)) files[path.relative(sample, file).split(path.sep).join('/')] = fs.readFileSync(file, 'utf8');
    }
  }
  read(path.join(sample, 'native'));
  const program = compile({ engine: declaration.engine, format: declaration.sourceFormat,
    entry: declaration.sourcePath, files, actions: declaration.actions });
  const state = {};
  const requests = [];
  let replacement;
  const globals = {
    $getenv: () => ({ kind: 'translationUI', inputText: 'בראשית', parameters: {}, allowsReplacement: true }),
    $storage: { getString: key => state[key] || '', setString: (key, value) => { state[key] = value; } },
    $presentation: { expandSheet() {}, finish(text) { replacement = text; } },
    $http: {
      async post(url, options) {
        const request = JSON.parse(options.body); requests.push(request);
        return JSON.stringify({took: 3, hits: {total: 30, hits: [
          {_id: 'preferred', _score: 10, _source: {ref: 'Genesis 1:1', heRef: 'בראשית א:א', version: 'ראשית', version_priority: 1}, highlight: {naive_lemmatizer: ['בראשית ברא']}},
          {_id: 'alternative', _score: 20, _source: {ref: 'Genesis 1:1', heRef: 'בראשית א:א', version: 'נוסח נוסף', version_priority: 2}, highlight: {naive_lemmatizer: ['נוסח נוסף']}}
        ]}});
      },
      async getResponse(url) {
        assert.match(url, /api\/v3\/texts\/Genesis/);
        assert.match(url, /version=/);
        return {status: 200, body: JSON.stringify({ref: 'Genesis 1:1',
          versions: [{language: 'he', versionTitle: 'מקור', text: ['בראשית ברא אלוהים']}]})};
      }
    }
  };
  await execution(program, '', null, {}, globals);
  const readState = () => JSON.parse(state['modular-search-presentation-v1']);
  assert.equal(readState().model.groups.length, 1);
  assert.equal(readState().model.groups[0].primary.version, 'ראשית');
  assert.equal(readState().model.groups[0].versionCount, 1);
  const group = readState().model.groups[0];
  await execution(program, 'toggleVersions', { id: group.id }, {}, globals);
  assert.equal(readState().expandedVersions[group.id], true);
  await execution(program, 'loadFullText', { id: group.primary.id }, {}, globals);
  const version = readState().expandedTexts[group.primary.id].versions[0];
  assert.match(version.text, /בראשית/);
  await execution(program, 'loadMore', {}, {}, globals);
  assert.ok(requests.at(-1).size > requests[0].size);
  await execution(program, 'replaceText', { id: group.primary.id, version: version.id }, {}, globals);
  assert.equal(replacement, 'בראשית ברא אלוהים');
});

test('original action-only source and exported control handlers do not require a rendered root', async () => {
  for (const [source, actionOnly] of [
    ['function press() { $storage.set("pressed", true); }', true],
    ['export function press() { $storage.set("pressed", true); }', true]
  ]) {
    const program = compile({engine: 'scriptwidget', format: 'jsx', entry: 'main.jsx',
      files: {'main.jsx': source}, actions: [{id: '__scriptwidget_control_press', kind: 'function', handler: 'press'}]});
    const result = await execution(program, '__scriptwidget_control_press', null, {}, {__hanlinActionOnly: actionOnly});
    assert.equal(result.values.pressed, true);
    assert.equal(result.rendered, undefined);
  }
});
