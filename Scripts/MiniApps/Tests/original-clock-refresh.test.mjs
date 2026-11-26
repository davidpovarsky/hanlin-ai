import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {mergeOriginal, originalInHostTarget} from '../refresh-original-sources.mjs';

test('original ScriptWidget clock refresh retains Sendable closures and complete upstream behavior', async () => {
  const original = await readFile(new URL('./Fixtures/scriptwidget-4da256d5/ClockHandRotationEffect.swift', import.meta.url));
  const target = 'Packages/HanlinPlatform/Sources/HanlinScriptExtensions/ScriptWidget/Original/Component/Attributes/Animation/ClockHandRotationEffect.swift';
  const current = await readFile(new URL('../../../' + target, import.meta.url));
  const stale = Buffer.from(current.toString().replace('forms: [@Sendable (', 'forms: [('));
  const expected = Buffer.from(stale.toString().replace('forms: [(', 'forms: [@Sendable ('));
  assert.notDeepEqual(stale, expected, 'the actual failing original declaration must be present');
  const cache = await mkdtemp(path.join(tmpdir(), 'hanlin-clock-refresh-'));
  try {
    const unchanged = await mergeOriginal({local: stale, previous: original, next: original, cache, label: 'same original clock', target});
    assert.deepEqual(unchanged, expected, 'unchanged upstream still repairs a stale host declaration without changing its behavior');
    assert.deepEqual(originalInHostTarget(unchanged, target), unchanged, 'projection is idempotent');
    assert.deepEqual(originalInHostTarget(original, 'Other/ClockHandRotationEffect.swift'), original, 'unrelated target stays byte-identical');
    const next = Buffer.from(original.toString().replace('WidgetKit clock-hand effect found', 'WidgetKit clock-hand effect located'));
    assert.notDeepEqual(next, original);
    const advanced = await mergeOriginal({local: unchanged, previous: original, next, cache, label: 'updated original clock', target});
    assert.deepEqual(advanced, Buffer.from(expected.toString().replace('WidgetKit clock-hand effect found', 'WidgetKit clock-hand effect located')), 'the full upstream change and existing host composition annotation survive refresh');
  } finally {
    await rm(cache, {recursive: true, force: true});
  }
});
