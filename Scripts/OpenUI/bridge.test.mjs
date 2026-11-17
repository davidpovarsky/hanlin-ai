import test from 'node:test';
import assert from 'node:assert/strict';
import { openuiLibrary } from '@openuidev/react-ui';
import { NativeRuntime } from './native-runtime.mjs';
import { encodeState, decodeState } from './state-wire.mjs';

const controls = `$budget = [1200]
$nights = "3"
slider = Slider("budget", "continuous", 0, 10000, 100, [1200], "Budget", null, $budget)
nights = Input("nights", "Nights", "text", null, $nights)
root = Stack([slider, nights])`;
const summary = `root = Stack([TextContent("Budget: " + $budget[0] + ", nights: " + $nights)])`;
function nodes(tree) {
  if (!tree || typeof tree !== 'object') return [];
  return [...(tree.typeName ? [tree] : []), ...Object.values(tree).flatMap(nodes)];
}
const settle = () => new Promise(resolve => setImmediate(resolve));

test('upstream bindings update separate controls and summary programs in both directions', async () => {
  let state = {}, firstTree, secondTree;
  const onState = next => { state = { ...state, ...next }; };
  const one = new NativeRuntime({ library: openuiLibrary, onState, onTree: tree => { firstTree = tree; } });
  const two = new NativeRuntime({ library: openuiLibrary, onState, onTree: tree => { secondTree = tree; } });
  try {
    one.update(controls, true, state); two.update(summary, true, state);
    assert.equal(nodes(secondTree).find(n => n.typeName === 'TextContent').props.text, 'Budget: 1200, nights: 3');
    const slider = nodes(firstTree).find(n => n.typeName === 'Slider');
    one.setField(slider.id, [2400]); await settle();
    two.update(summary, true, state);
    assert.equal(nodes(secondTree).find(n => n.typeName === 'TextContent').props.text, 'Budget: 2400, nights: 3');
    // A React onStateUpdate supplies the exact same original raw state shape.
    state = { ...state, $nights: '5' }; one.update(controls, true, state);
    assert.equal(nodes(firstTree).find(n => n.typeName === 'Input').props.currentValue, '5');
    const saved = JSON.parse(JSON.stringify(state));
    one.update(controls, true, saved);
    assert.deepEqual(nodes(firstTree).find(n => n.typeName === 'Slider').props.currentValue, [2400]);
  } finally { one.dispose(); two.dispose(); }
});

test('local actions use upstream plans; ToAssistant retains form state', async () => {
  let tree, event;
  const runtime = new NativeRuntime({ library: openuiLibrary, onTree: next => { tree = next; }, onAction: next => { event = next; } });
  try {
    runtime.update('$nights = "3"\nchange = Button("Choose", @Set($nights, "5"))\nsend = Button("Continue", @ToAssistant("Use this plan"))\nroot = Stack([Buttons([change, send]), TextContent($nights)])', true, {});
    await runtime.act(nodes(tree).find(n => n.props?.label === 'Choose').id); await settle();
    assert.equal(nodes(tree).find(n => n.typeName === 'TextContent').props.text, '5');
    await runtime.act(nodes(tree).find(n => n.props?.label === 'Continue').id);
    assert.equal(event.type, 'continue_conversation'); assert.equal(event.formState.$nights, '5');
  } finally { runtime.dispose(); }
});

test('partial streaming does not dispatch queries or actions', async () => {
  const calls = [];
  const runtime = new NativeRuntime({ library: openuiLibrary, toolProvider: { callTool: async (...args) => { calls.push(args); return {}; } } });
  try {
    runtime.update('result = Query("lookup", {query: "real"}, {})\nroot = Stack([TextContent(result.title)])', false, {});
    await settle(); assert.equal(calls.length, 0);
  } finally { runtime.dispose(); }
});

test('the host handles original Query without a new network transport', async () => {
  const calls = []; let tree;
  const runtime = new NativeRuntime({ library: openuiLibrary, onTree: next => { tree = next; },
    toolProvider: { callTool: async (name, args) => { calls.push({ name, args }); return { title: 'Original host result' }; } } });
  try {
    runtime.update('result = Query("lookup", {query: "real"}, {})\nroot = Stack([TextContent(result.title)])', true, {});
    await settle(); await settle();
    assert.deepEqual(calls, [{ name: 'lookup', args: { query: 'real' } }]);
    assert.equal(nodes(tree).find(n => n.typeName === 'TextContent').props.text, 'Original host result');
  } finally { runtime.dispose(); }
});

test('the original required-field validator prevents submission until the user repairs the form', async () => {
  let tree; const events = [];
  const runtime = new NativeRuntime({ library: openuiLibrary, onTree: value => { tree = value; }, onAction: value => { events.push(value); } });
  try {
    runtime.update('$name = ""\nnameField = Input("traveler", "Full name", "text", {required: true}, $name)\nsubmit = Button("Continue", @ToAssistant("Use this name"))\nroot = Form("trip", Buttons([submit]), [FormControl("Name", nameField)])', true, {});
    const submit = nodes(tree).find(n => n.typeName === 'Button');
    assert.ok(submit);
    await runtime.act(submit.id); await settle();
    assert.equal(events.length, 0);
    let field = nodes(tree).find(n => n.typeName === 'Input');
    assert.equal(typeof field.props.validationError, 'string');
    assert.ok(field.props.validationError.length > 0);
    runtime.setField(field.id, 'Miriam'); await settle();
    field = nodes(tree).find(n => n.typeName === 'Input');
    assert.equal(field.props.validationError, null);
    await runtime.act(submit.id); await settle();
    assert.equal(events.length, 1);
    assert.equal(events[0].type, 'continue_conversation');
    assert.equal(events[0].formState.$name, 'Miriam');
  } finally { runtime.dispose(); }
});

test('native list item actions preserve the original action and item title', async () => {
  let tree, event;
  const runtime = new NativeRuntime({ library: openuiLibrary, onTree: value => { tree = value; }, onAction: value => { event = value; } });
  try {
    runtime.update('item = ListItem("Original item", "Details", null, "Open", @ToAssistant("Read this item"))\nroot = ListBlock([item])', true, {});
    const item = nodes(tree).find(n => n.typeName === 'ListItem');
    assert.equal(item.props.hasAction, true);
    await runtime.act(item.id);
    assert.equal(event.type, 'continue_conversation');
    assert.equal(event.humanFriendlyMessage, 'Read this item');
  } finally { runtime.dispose(); }
});

test('original DatePicker range values survive native edits, JSON persistence and React rehydration', async () => {
  const start = new Date('2026-11-17T00:00:00.000Z'), end = new Date('2026-11-20T00:00:00.000Z');
  const state = { $dates: { from: start, to: end } };
  const saved = JSON.parse(JSON.stringify(encodeState(state)));
  const restored = decodeState(saved);
  assert.ok(restored.$dates.from instanceof Date);
  assert.equal(restored.$dates.to.getTime(), end.getTime());
  let tree, changed;
  const runtime = new NativeRuntime({ library: openuiLibrary, onTree: value => { tree = value; }, onState: value => { changed = value; } });
  try {
    runtime.update('root = DatePicker("tripDates", "range", null, $dates)', true, restored);
    const picker = nodes(tree).find(n => n.typeName === 'DatePicker');
    assert.ok(picker.props.currentValue.from instanceof Date);
    const edited = decodeState({ from: saved.$dates.from, to: { __hanlinOpenUIDate: '2026-11-22T00:00:00.000Z' } });
    runtime.setField(picker.id, edited); await settle();
    const reopened = decodeState(JSON.parse(JSON.stringify(encodeState(changed))));
    assert.equal(reopened.$dates.from.getTime(), start.getTime());
    assert.equal(reopened.$dates.to.toISOString(), '2026-11-22T00:00:00.000Z');
    assert.deepEqual(decodeState({ __hanlinOpenUIDate: 'not-a-date' }), { __hanlinOpenUIDate: 'not-a-date' });
  } finally { runtime.dispose(); }
});
