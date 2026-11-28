import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import test from 'node:test';

const sourceURL = new URL('../../../Packages/HanlinPlatform/Sources/HanlinScriptUI/Resources/jsx-runtime.js', import.meta.url);
const source = await fs.readFile(sourceURL, 'utf8');
const runtime = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);

test('JSX runtime flattens children and converts scalar text nodes', () => {
  const node = runtime.jsxs('vStack', {
    spacing: 8,
    children: ['hello', [null, runtime.jsx('divider', {})], false, 42],
  }, 'root');
  assert.equal(node.kind, 'vStack');
  assert.equal(node.key, 'root');
  assert.deepEqual(node.children.map(child => child.kind), ['text', 'divider', 'text']);
  assert.deepEqual(node.children.map(child => child.properties.text), ['hello', undefined, '42']);
});

test('hooks preserve state, compare dependencies, and release effects', () => {
  let invalidations = 0;
  let setups = 0;
  let disposals = 0;
  const hooks = runtime.createHooks({ invalidate() { invalidations += 1; } });
  hooks.beginRender();
  const [value, setValue] = hooks.useState(1);
  hooks.useEffect(() => { setups += 1; return () => { disposals += 1; }; }, [value]);
  setValue(previous => previous + 1);
  assert.equal(invalidations, 1);
  hooks.beginRender();
  const [updated] = hooks.useState(0);
  hooks.useEffect(() => { setups += 1; return () => { disposals += 1; }; }, [updated]);
  assert.equal(updated, 2);
  assert.equal(setups, 2);
  assert.equal(disposals, 1);
  hooks.dispose();
  assert.equal(disposals, 2);
});
