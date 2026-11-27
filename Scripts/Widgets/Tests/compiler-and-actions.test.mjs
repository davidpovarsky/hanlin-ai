import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { widgetSamples } from '../samples.mjs';
import { deterministicZip } from '../deterministic-zip.mjs';

const root = path.resolve(import.meta.dirname, '../../..');
const compilerRoot = path.join(root, 'Packages/HanlinPlatform/Sources/HanlinWidgetCompiler/Resources');
const compiler = vm.createContext({ __scriptWidgetBeginCompile() {}, __scriptWidgetCompileActive: () => true });
vm.runInContext(fs.readFileSync(path.join(compilerRoot, 'core.js'), 'utf8'), compiler);
vm.runInContext(fs.readFileSync(path.join(compilerRoot, 'prepare-widget.js'), 'utf8'), compiler);
const bundle = fs.readFileSync(path.join(root, 'Packages/HanlinPlatform/Sources/HanlinScriptExtensions/Resources/ExpoWidgets.bundle'), 'utf8');
function compile(sample) {
  const manifest = JSON.parse(sample.files['script.json']);
  return compiler.__hanlinCompileWidget({ engine: manifest.widgetEngine, format: manifest.hanlinWidget.sourceFormat,
    entry: manifest.entry, files: Object.fromEntries(Object.entries(sample.files).filter(([p]) => /\.[jt]sx?$/.test(p))), actions: manifest.hanlinWidget.actions });
}
function expo(sample, props = {}) {
  const context = vm.createContext({ __scriptWidgetCheckExecution: () => {} });
  vm.runInContext(bundle, context);
  context.__expoWidgetLayout = vm.runInContext('(' + compile(sample) + ')', context);
  return { context, render: () => context.__expoWidgetRender(props, { widgetFamily: 'systemMedium' }) };
}
test('P3-02: real Expo JSX wrappers run source callbacks, including arbitrary props', () => {
  const { context, render } = expo(widgetSamples[0]);
  const before = JSON.stringify(render());
  assert.match(before, /TextView/); assert.match(before, /"7"/);
  let props = context.__expoWidgetHandlePress({}, { target: 'increment' });
  assert.equal(props.count, 8);
  props = context.__expoWidgetHandlePress(props, { target: 'decrement' });
  assert.equal(props.count, 7);
  const custom = context.__expoWidgetHandlePress(props, { target: 'status' });
  assert.equal(custom.status, 'Source callback ran'); assert.equal(custom.trace, 'status-handler');
  assert.equal(context.__expoWidgetHandlePress(props, { target: 'undeclared' }), undefined);
});
test('P3-09: original Expo JSX preserves named slot and nested text nodes', () => {
  const { render, context } = expo(widgetSamples[1]);
  const tree = JSON.stringify(render());
  for (const type of ['SlotView', 'OverlayView', 'BackgroundView', 'MaskView', 'GaugeView', 'ChartView', 'TextView']) assert.ok(tree.includes(type), type);
  assert.match(tree, /"name":"content"/);
  assert.equal(context.__expoWidgetHandlePress({}, { target:'overlay' }).label, 'Overlay callback');
});
test('P3-08: separate executions cannot retain another package global', () => {
  const first = expo(widgetSamples[0]), second = expo(widgetSamples[0]);
  first.context.leaked = 42; assert.equal(second.context.leaked, undefined);
});
test('P3-15: the widget module closure excludes an unrelated foreground bundle', () => {
  const sample = { ...widgetSamples[0], files: { ...widgetSamples[0].files, 'app/bundle.js': 'invalid app-only bundle syntax '.repeat(30000) } };
  const result = expo(sample).context.__expoWidgetHandlePress({}, { target:'increment' });
  assert.equal(result.count, 8);
  const missing = { ...sample, files:{ ...sample.files, 'widget.tsx': 'import x from "./absent"; export default function W(){return x;}' } };
  assert.throws(()=>compile(missing), /Missing widget module/);
});
test('P3-03/P3-24: ScriptWidget source functions preserve typed state', async () => {
  const values = {};
  const program = compile(widgetSamples[3]);
  const run = async action => {
    let rendered;
    const context = vm.createContext({
      __scriptWidgetCheckExecution: () => {}, __hanlinAction: action,
      __hanlinEvent: {}, $element: {createElement:(tag,props,children)=>({tag,props,children})},
      $render: node => {rendered=node;}, $error: error => {throw Error(error);},
      $storage: { get:key=>values[key], set:(key,value)=>{values[key]=value;return true;} }
    });
    vm.runInContext(fs.readFileSync(path.join(root,'Packages/HanlinPlatform/Sources/HanlinScriptExtensions/Resources/support.bundle/util.js'),'utf8'),context);
    vm.runInContext(program,context); await context.$main(); return rendered;
  };
  await run('sync'); assert.equal(values.syncCount,1);
  await run('named'); assert.equal(values.status,'Named source function ran');
  values.backup=true; const tree=JSON.stringify(await run('')); assert.match(tree,/"on":true/);
  values.backup=false; assert.match(JSON.stringify(await run('')),/"on":false/);
});
test('ScriptWidget starts an independent original compile budget for every Babel operation', () => {
  // Observe the real compiler's lifecycle without replacing Babel, advancing a
  // clock, sleeping, or claiming this VM proves Apple execution-time behavior.
  let begins = 0;
  let checks = 0;
  let operationActive = false;
  const context = vm.createContext({
    __scriptWidgetBeginCompile() { begins += 1; operationActive = true; },
    __scriptWidgetCompileActive() { checks += 1; return operationActive; }
  });
  vm.runInContext(fs.readFileSync(path.join(compilerRoot, 'core.js'), 'utf8'), context);
  vm.runInContext(fs.readFileSync(path.join(compilerRoot, 'prepare-widget.js'), 'utf8'), context);
  const transform = context.Babel.transform;
  let operations = 0;
  context.Babel.transform = (...args) => {
    assert.equal(operationActive, true, 'An original Babel operation inherited an inactive prior budget');
    assert.equal(begins, operations + 1, 'Each original Babel operation must begin its own budget');
    operations += 1;
    return transform(...args);
  };
  const compile = input => {
    operationActive = false;
    const before = operations;
    const output = context.__hanlinCompileWidget(input);
    assert.ok(operations > before);
    assert.ok(checks >= operations, 'Every operation must retain its original deadline check');
    new vm.Script(output);
    return output;
  };
  const files = {
    'widget.tsx': 'import { title } from "./title"; export default function render() { $render(<text>{title}</text>); }',
    'title.ts': 'export const title: string = "Independent source";'
  };
  assert.match(compile({ engine: 'scriptwidget', format: 'tsx', entry: 'widget.tsx', files, actions: [] }), /Independent source/);
  compile({ engine: 'scriptwidget-import', format: 'jsx', entry: 'helper.jsx',
    files: { 'helper.jsx': 'function helper() { return <text>Imported source</text>; }' }, actions: [] });
  compile({ engine: 'scriptwidget', format: 'jsx', entry: 'single.jsx',
    files: { 'single.jsx': '$render(<text>Independent entry</text>);' }, actions: [] });
  assert.equal(begins, operations);
  assert.equal(operations, 6, 'Entry inspection, two modules, an import, inspection and a top-level compile all ran');
});
test('P3-12: reserved guard identifiers and malformed JSX fail compilation', () => {
  for (const source of ['while(true){}; const __scriptWidgetCheckExecution=()=>{};', '$render(<broken;)']) {
    const sample={...widgetSamples[3],files:{...widgetSamples[3].files,'widget.jsx':source}};
    assert.throws(()=>compile(sample));
  }
});
test('P3-26: fixture archives rebuild byte-for-byte in all three locations', () => {
  for(const sample of widgetSamples) {
    const bytes=deterministicZip(sample.files),name=sample.name+'.'+sample.extension;
    assert.deepEqual(bytes,fs.readFileSync(path.join(root,'Fixtures/Widgets',name)));
    assert.deepEqual(bytes,fs.readFileSync(path.join(root,'AI_HLYUITests/Fixtures',name)));
    assert.deepEqual(bytes,fs.readFileSync(path.join(root,'AI_HLYTests/Fixtures/WidgetEngineFixtures.bundle',name)));
  }
});
test('P3-26: Expo fixture contracts match the exact embedded native widget versions', () => {
  const pinned = JSON.parse(fs.readFileSync(path.join(root, 'Scripts/Expo/package.json'), 'utf8')).dependencies;
  for (const sample of widgetSamples.filter(sample => sample.files['package.json'])) {
    const manifest = JSON.parse(sample.files['package.json']);
    assert.equal(manifest.hanlinExpo.runtimeVersion, pinned['@expo/ui'], sample.name);
    assert.equal(manifest.hanlinExpo.plugins['@expo/ui'], pinned['@expo/ui'], sample.name);
    assert.equal(manifest.dependencies['@expo/ui'], pinned['@expo/ui'], sample.name);
    assert.equal(manifest.dependencies['expo-widgets'], pinned['expo-widgets'], sample.name);
    assert.equal(manifest.dependencies.react, pinned.react, sample.name);
  }
});
