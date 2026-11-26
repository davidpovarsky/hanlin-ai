import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {widgetSamples} from '../samples.mjs';

const root = path.resolve(import.meta.dirname, '../../..');
const read = relative => fs.readFileSync(path.join(root, relative), 'utf8');
const adapter = read('Packages/HanlinPlatform/Sources/HanlinScriptContracts/Resources/HanlinExpoWidgetInteractions.js');
const compiler = vm.createContext({});
vm.runInContext(read('Packages/HanlinPlatform/Sources/HanlinWidgetCompiler/Resources/core.js'), compiler);
vm.runInContext(read('Packages/HanlinPlatform/Sources/HanlinWidgetCompiler/Resources/prepare-widget.js'), compiler);
const bundles = {
  original: 'Packages/HanlinExpoRuntime/Sources/ExpoWidgets/Resources/ExpoWidgets.bundle/ExpoWidgets.bundle',
  prepared: 'Packages/HanlinPlatform/Sources/HanlinScriptExtensions/Resources/ExpoWidgets.bundle',
};
const source = `import {VStack, Toggle, Button} from '@expo/ui/swift-ui';
export default function Widget(props) {
  return <VStack>
    <Toggle label="Notifications" target="notifications" isOn={props.enabled ?? false}
      onIsOnChange={value => ({enabled: value, count: (props.count ?? 0) + 1})}/>
    <Button label="Increment" target="increment" onPress={() => ({count: (props.count ?? 0) + 1})}/>
  </VStack>;
}`;
function contextFor(bundle, code = source) {
  const context = vm.createContext({});
  vm.runInContext(read(bundle), context);
  vm.runInContext(adapter, context);
  const layout = compiler.__hanlinCompileWidget({engine:'expo', format:'tsx',
    entry:'widget.tsx', files:{'widget.tsx':code}, actions:[]});
  context.__expoWidgetLayout = vm.runInContext('(' + layout + ')', context);
  return context;
}
function toggle(context, props, value, target = 'notifications') {
  return context.__hanlinWidgetHandleToggle(props, {
    widgetFamily:'systemMedium', target, __hanlinToggleValue:value,
  });
}
for (const [engine, bundle] of Object.entries(bundles)) {
  test(engine + ': SDK matrix renders all eight families with authored clear background and native component nodes', () => {
    const sample = widgetSamples.find(s => s.name === 'Hanlin-Expo-Widget-Interactive-Matrix');
    const manifest = JSON.parse(sample.files['script.json']);
    assert.equal(manifest.hanlinWidget.families.length, 8);
    const context = contextFor(bundle, sample.files['widget.jsx']);
    for (const family of manifest.hanlinWidget.families) {
      const tree = context.__expoWidgetRender({enabled:false,count:3}, {widgetFamily:family});
      const wire = JSON.stringify(tree);
      assert.ok(tree && !wire.includes('RedBoxView'));
      if (!family.startsWith('accessory')) {
        for (const type of ['ToggleView','Button','ProgressView','GaugeView','ImageView','LinkView'])
          assert.ok(wire.includes(type), family + ' omitted ' + type);
        assert.ok(wire.includes('containerBackground'));
        assert.ok(wire.includes('clear'));
        if (family !== 'systemSmall') assert.ok(wire.includes('ChartView'));
      }
    }
    const updated = toggle(context, {enabled:false,count:3}, true, 'enabled');
    assert.equal(updated.enabled, true);
    assert.equal(updated.count, 4);
    assert.throws(() => context.__expoWidgetRender({fail:true}, {widgetFamily:'systemMedium'}), /Fixture refresh failed/);
  });
  test(engine + ': actual original Toggle wrapper returns props; intended values survive repeat requests', () => {
    const context = contextFor(bundle);
    let props = {};
    for (const value of [true, true, false, false, true]) {
      const previous = props.count ?? 0;
      props = {...props, ...toggle(context, props, value)};
      assert.equal(props.enabled, value);
      assert.equal(props.count, previous + 1);
      assert.match(JSON.stringify(context.__expoWidgetRender(props, {})), new RegExp('"isOn":' + value));
    }
  });
  test(engine + ': original Button callback is unchanged alongside Toggle and source instances stay isolated', () => {
    const first = contextFor(bundle), second = contextFor(bundle);
    const firstProps = toggle(first, {}, true);
    assert.equal(first.__expoWidgetHandlePress(firstProps, {target:'increment'}).count, 2);
    assert.match(JSON.stringify(second.__expoWidgetRender({}, {})), /"isOn":false/);
    assert.equal(second.__expoWidgetHandlePress({}, {target:'increment'}).count, 1);
    const eventOnly = contextFor(bundle, source.replace('() => ({count: (props.count ?? 0) + 1})', '() => undefined'));
    assert.ok(eventOnly.__expoWidgetHandlePress({}, {target:'increment'}) == null,
      'Original event-only Buttons may return no props');

    assert.throws(() => toggle(first, {}, true, 'missing'), /No matching/);
    assert.throws(() => toggle(first, {}, 'true'), /Boolean/);
  });
  test(engine + ': callback failures, promises and malformed values cannot become committed state', () => {
    const failure = contextFor(bundle, source.replace('({enabled: value, count: (props.count ?? 0) + 1})',
      '(() => { throw Error("refresh failed"); })()'));
    assert.throws(() => toggle(failure, {}, true), /refresh failed/);
    const asynchronous = contextFor(bundle, source.replace('value => ({enabled:',
      'async value => ({enabled:'));
    assert.throws(() => toggle(asynchronous, {}, true), /synchronously/);
    const invalid = contextFor(bundle, source.replace('props.enabled ?? false', '"false"'));
    assert.throws(() => invalid.__expoWidgetRender({}, {}), /Boolean/);
  });
  test(engine + ': duplicate targets and disabled modifiers fail before invoking a Toggle callback', () => {
    const duplicate = contextFor(bundle, `import {VStack,Toggle} from '@expo/ui/swift-ui';
      export default () => <VStack><Toggle isOn={false} target="same" onIsOnChange={v=>({v})}/>
        <Toggle isOn={true} target="same" onIsOnChange={v=>({v})}/></VStack>`);
    assert.throws(() => duplicate.__expoWidgetRender({}, {}), /unique/);
    const disabled = contextFor(bundle, source.replace('label="Notifications"',
      'label="Notifications" modifiers={[{$type:"disabled", disabled:true}]}'));
    assert.throws(() => toggle(disabled, {}, true), /disabled/);
  });
}
