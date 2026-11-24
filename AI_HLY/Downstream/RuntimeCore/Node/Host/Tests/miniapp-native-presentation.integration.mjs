import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, mkdir, writeFile, readFile, rm, access, rename} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {runMiniAppOperation} from '../miniapp-authoring.mjs';

const sdkRoot = process.env.HANLIN_AUTHORING_INTEGRATION_SDK;
assert.ok(sdkRoot, 'Supply the actual staged original SDK in HANLIN_AUTHORING_INTEGRATION_SDK.');
const json = (file, value) => writeFile(file, JSON.stringify(value, null, 2));
async function project(engine) {
  const root = await mkdtemp(path.join(os.tmpdir(), 'native-presentation-authoring-'));
  await mkdir(path.join(root, 'native/assets'), {recursive: true});
  await writeFile(path.join(root, 'native/assets/original.txt'), 'Exact native resource bytes');
  await json(path.join(root, 'script.json'), {name: 'Native type environments', version: '1.0.0',
    hanlinRuntime: engine === 'expo' ? 'hanlin-expo' : 'hanlin-nativescript', entry: 'bundle.js', runInApp: true,
    nativePresentations: {appIntents: {engine: 'scriptwidget', sourcePath: 'native/view.tsx', sourceFormat: 'tsx'}}});
  await json(path.join(root, 'package.json'), {name: 'native-type-environments', version: '1.0.0', type: 'module'});
  await json(path.join(root, 'hanlin.authoring.json'), {schemaVersion: 1, engine, entry: 'index.tsx', resources: ['native/assets']});
  await json(path.join(root, 'tsconfig.json'), {compilerOptions: {strict: true,
    ...(engine === 'expo' ? {skipLibCheck: false, lib: ['ES2023'], types: ['react', 'react-native']} : {})},
    include: ['index.tsx'], exclude: ['native']});
  await writeFile(path.join(root, 'index.tsx'), engine === 'expo'
    ? 'import type {ReactNode} from "react"; export const node: ReactNode = null;\n'
    : 'export const answer: number = 42;\n');
  await writeFile(path.join(root, 'native/helper.ts'), 'export const message: string = "Original native SDK";\n');
  await writeFile(path.join(root, 'native/view.tsx'),
    'import {message} from "./helper";\nexport default function render() { $render(<text font="headline">{message}</text>); }\n');
  return root;
}

test('Expo React types and original ScriptWidget JSX validate in isolated actual SDK environments', async () => {
  const root = await project('expo');
  try {
    const report = await runMiniAppOperation({operation: 'validate', engine: 'expo', projectRoot: root}, {sdkRoot});
    assert.equal(report.succeeded, true, JSON.stringify(report.diagnostics));
    assert.deepEqual(report.diagnostics, []);
  } finally { await rm(root, {recursive: true, force: true}); }
});

test('a native entry beside the primary project config keeps its own renderer environment', async () => {
  const root = await project('expo');
  try {
    for (const file of ['view.tsx', 'helper.ts'])
      await rename(path.join(root, 'native', file), path.join(root, file));
    const script = JSON.parse(await readFile(path.join(root, 'script.json'), 'utf8'));
    script.nativePresentations.appIntents.sourcePath = 'view.tsx';
    await json(path.join(root, 'script.json'), script);
    const report = await runMiniAppOperation({operation: 'validate', engine: 'expo', projectRoot: root}, {sdkRoot});
    assert.equal(report.succeeded, true, JSON.stringify(report.diagnostics));
    assert.deepEqual(report.diagnostics, []);
  } finally { await rm(root, {recursive: true, force: true}); }
});

test('an invalid native JSX property blocks packaging and reports the original native source location', async () => {
  const root = await project('expo');
  try {
    await writeFile(path.join(root, 'native/view.tsx'),
      'export default function render() { $render(<text font="not-a-native-font">Invalid</text>); }\n');
    const report = await runMiniAppOperation({operation: 'build', engine: 'expo', projectRoot: root}, {sdkRoot});
    assert.equal(report.succeeded, false);
    assert.ok(report.diagnostics.some(item => item.code === 'TS2322' && item.file === 'native/view.tsx' && item.line === 1 && item.column > 0), JSON.stringify(report.diagnostics));
    assert.equal(report.preparedPackagePath, undefined);
    await assert.rejects(access(path.join(root, '.hanlin-build')));
  } finally { await rm(root, {recursive: true, force: true}); }
});

test('actual compiler-discovered native presentation modules survive prepared output and source retention', async () => {
  const root = await project('nativescript');
  try {
    const report = await runMiniAppOperation({operation: 'build', engine: 'nativescript', projectRoot: root}, {sdkRoot});
    assert.equal(report.succeeded, true, JSON.stringify(report.diagnostics));
    for (const file of ['native/view.tsx', 'native/helper.ts', 'native/assets/original.txt']) {
      const original = await readFile(path.join(root, file), 'utf8');
      assert.equal(await readFile(path.join(report.preparedPackagePath, file), 'utf8'), original);
      assert.equal(await readFile(path.join(report.preparedPackagePath, 'source', file), 'utf8'), original);
    }
    const again = await runMiniAppOperation({operation: 'validate', engine: 'nativescript', projectRoot: report.preparedPackagePath}, {sdkRoot});
    assert.equal(again.succeeded, true, JSON.stringify(again.diagnostics));
  } finally { await rm(root, {recursive: true, force: true}); }
});
