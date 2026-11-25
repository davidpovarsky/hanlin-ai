import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {mergeOriginal, originalInHostTarget} from '../refresh-original-sources.mjs';

test('original ScriptWidget list refresh preserves MainActor rendering and original layout bodies', async () => {
  const original = await readFile(new URL('./Fixtures/scriptwidget-4da256d5/ScriptWidgetElementTagStack.swift', import.meta.url));
  const target = 'Packages/HanlinPlatform/Sources/HanlinScriptExtensions/ScriptWidget/Original/Component/Elements/ScriptWidgetElementTagStack.swift';
  const current = await readFile(new URL('../../../' + target, import.meta.url));
  const declaration = 'struct ScriptWidgetElementTagList {';
  const annotation = '@MainActor\n' + declaration;
  const stale = Buffer.from(current.toString().replace(annotation, declaration));
  const expected = Buffer.from(stale.toString().replace(declaration, annotation));
  assert.notDeepEqual(stale, expected, 'the actual failing nonisolated original list declaration must be present');
  assert.deepEqual(originalInHostTarget(original, target),
    Buffer.from(original.toString().replace(declaration, annotation)),
    'only the original UI helper isolation changes in a fresh projection');
  const originalBodies = bytes => bytes.toString().replace(/^@MainActor\r?\n/gm, '').replace(/[ \t]+$/gm, '');
  assert.equal(originalBodies(expected), originalBodies(original),
    'all stack, list, layout and drawing bodies retain the immutable original source');
  const cache = await mkdtemp(path.join(tmpdir(), 'hanlin-tag-list-refresh-'));
  try {
    const unchanged = await mergeOriginal({local: stale, previous: original, next: original, cache, label: 'same original list', target});
    assert.deepEqual(unchanged, expected, 'same-version refresh repairs the missing isolation without changing any body');
    assert.deepEqual(originalInHostTarget(unchanged, target), unchanged, 'projection is idempotent');
    assert.deepEqual(originalInHostTarget(original, 'Other/ScriptWidgetElementTagStack.swift'), original, 'unrelated target stays byte-identical');
    // A controlled future-upstream body edit tests three-way update preservation;
    // it is not represented as a newly fetched upstream commit.
    const oldBody = 'let rowProposal = ProposedViewSize(width: bounds.width, height: nil)';
    const newBody = 'let rowProposal = ProposedViewSize(width: bounds.width, height: proposal.height)';
    const next = Buffer.from(original.toString().replace(oldBody, newBody));
    assert.notDeepEqual(next, original);
    const advanced = await mergeOriginal({local: unchanged, previous: original, next, cache, label: 'updated original list', target});
    assert.deepEqual(advanced, Buffer.from(expected.toString().replace(oldBody, newBody)),
      'upstream body changes and both host UI isolation annotations survive together');
  } finally {
    await rm(cache, {recursive: true, force: true});
  }
});
