import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import test from 'node:test';

const repository = new URL('../../../', import.meta.url);
const source = await readFile(new URL(
  'Packages/HanlinPlatform/Sources/HanlinScriptExtensions/ScriptWidget/HanlinScriptWidgetRuntime.swift',
  repository), 'utf8');
const start = source.indexOf('globalThis.$presentation = {');
const end = source.indexOf('\n                };', start);
assert.ok(start >= 0 && end > start, 'Load the actual installed host binding');
const binding = source.slice(start, end) + '\n};';

function fixture() {
  const edits = [], notifications = [], translations = [];
  const sandbox = {
    __hanlinKeyboardEdit(edit) { edits.push(JSON.parse(JSON.stringify(edit))); },
    __hanlinNotificationAction(action) { notifications.push(action); },
    __hanlinPresentationExpand() { translations.push({expand: true}); },
    __hanlinPresentationFinish(text) { translations.push({finish: text}); }
  };
  vm.createContext(sandbox);
  vm.runInContext(binding, sandbox, {filename: 'actual-host-binding.js'});
  return {sandbox, edits, notifications, translations};
}

test('actual binding forwards ordered text edits and notification actions', () => {
  const f = fixture();
  vm.runInContext([
    '$presentation.keyboard.insertText("שלום🙂");',
    '$presentation.keyboard.deleteBackward();',
    '$presentation.keyboard.adjustTextPosition(-2);',
    '$presentation.keyboard.nextInputMode();',
    '$presentation.notification.openApp();',
    '$presentation.notification.dismiss();'
  ].join('\n'), f.sandbox);
  assert.deepEqual(f.edits, [
    {operation: 'insertText', text: 'שלום🙂'},
    {operation: 'deleteBackward'},
    {operation: 'adjustTextPosition', offset: -2},
    {operation: 'nextInputMode'}
  ]);
  assert.deepEqual(f.notifications, ['openApp', 'dismiss']);
});

test('bad JS edit arguments fail before reaching the native document proxy', () => {
  const f = fixture();
  for (const expression of [
    '$presentation.keyboard.insertText(null)',
    '$presentation.keyboard.insertText(2)',
    '$presentation.keyboard.adjustTextPosition(1.5)',
    '$presentation.keyboard.adjustTextPosition(NaN)',
    '$presentation.keyboard.adjustTextPosition(Infinity)'
  ]) {
    assert.throws(() => vm.runInContext(expression, f.sandbox), {name: 'TypeError'});
  }
  assert.deepEqual(f.edits, []);
});

test('the same binding preserves existing translation helpers', () => {
  const f = fixture();
  vm.runInContext([
    '$presentation.expandSheet();',
    '$presentation.finish("שלום");',
    '$presentation.finish();'
  ].join('\n'), f.sandbox);
  assert.deepEqual(f.translations, [{expand: true}, {finish: 'שלום'}, {finish: null}]);
});
