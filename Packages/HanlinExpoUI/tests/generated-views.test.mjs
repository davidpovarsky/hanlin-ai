import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import vm from 'node:vm';
import test from 'node:test';

// Execute the actual generated wrapper with the installed original React and
// TypeScript. Only the native-view bindings are inert tags: these assertions
// cover the JavaScript slot boundary, not SwiftUI rendering or UI acceptance.
const packageRoot = process.env.HANLIN_EXPO_TEST_PACKAGE_ROOT
  ?? fileURLToPath(new URL('../../../Scripts/Expo/', import.meta.url));
const require = createRequire(resolve(packageRoot, 'package.json'));
const ts = require('typescript');
const React = require('react');

async function generatedViews(relativePath) {
  const source = await readFile(new URL(relativePath, import.meta.url), 'utf8');
  const compiled = ts.transpileModule(source, {fileName: 'views.tsx', reportDiagnostics: true,
    compilerOptions: {jsx: ts.JsxEmit.React, esModuleInterop: true,
      target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS}});
  assert.deepEqual(compiled.diagnostics, []);
  const exports = {};
  vm.runInNewContext(compiled.outputText, {exports, require(name) {
    if (name === 'react') return React;
    if (name === 'expo') return {requireNativeView(module, view) {
      assert.equal(module, 'HanlinGeneratedExpoUI');
      return view;
    }};
    assert.equal(name, '@expo/ui/swift-ui/modifiers');
    return {createViewModifierEventListener() {throw Error('No modifiers in this slot regression');}};
  }});
  return exports;
}

test('generated GroupBox forwards ordinary children and gives explicit content including null precedence', async () => {
  const paths = ['../src/generated/views.tsx', '../../../Generated/SwiftUIBridge/views.tsx'];
  const ordinary = React.createElement('Text', null, 'ordinary child');
  const explicit = React.createElement('Text', null, 'explicit content');
  const label = React.createElement('Text', null, 'native group label');
  for (const path of paths) {
    const {GroupBox} = await generatedViews(path);
    for (const [name, props, expected] of [
      ['omitted content', {children: ordinary}, ordinary],
      ['undefined content', {children: ordinary, content: undefined}, ordinary],
      ['explicit content', {children: ordinary, content: explicit}, explicit],
      ['explicit null', {children: ordinary, content: null}, null],
      ['explicit false', {children: ordinary, content: false}, false],
      ['explicit zero', {children: ordinary, content: 0}, 0],
      ['explicit empty string', {children: ordinary, content: ''}, ''],
    ]) {
      const element = GroupBox({...props, label});
      assert.equal(element.type, 'HanlinGeneratedGroupBoxView');
      const slots = React.Children.toArray(element.props.children);
      assert.equal(slots.length, 2, path + ': ' + name + ' must retain content and label slots');
      const content = slots.find(slot => slot.props.name === 'content');
      assert.ok(content, path + ': ' + name + ' lost content');
      assert.equal(content.type, 'HanlinGeneratedSlotView');
      assert.equal(content.props.children, expected, path + ': ' + name);
      assert.equal(slots.find(slot => slot.props.name === 'label').props.children, label);
    }
    assert.equal(React.Children.toArray(GroupBox({}).props.children).length, 0);
    assert.equal(React.Children.toArray(GroupBox({label}).props.children).length, 1);
  }
});
