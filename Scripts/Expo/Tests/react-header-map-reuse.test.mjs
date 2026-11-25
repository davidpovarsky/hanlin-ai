import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import * as fs from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { basename, dirname, resolve } from 'node:path';
import test from 'node:test';
import { preserveOriginalReactNativeHeaderModulemaps, pruneNonIOSSlicesFromXCFramework } from '../prepare-ios-dependencies.mjs';

const sha256 = (value) => createHash('sha256').update(value).digest('hex');
const fixture = resolve(import.meta.dirname, 'Fixtures/react-native-headers-0.88.1');
const provenance = JSON.parse(await fs.readFile(resolve(fixture, 'provenance.json'), 'utf8'));
const sourcePath = process.env.HANLIN_EXPO_PREPARE_SOURCE || resolve(import.meta.dirname, '../prepare-ios-dependencies.mjs');

// Execute the actual nested production stage, without invoking unrelated native
// producers. Its filesystem operations, map projection and cleanup stay intact.
async function productionStage(artifactsRoot) {
  const source = await fs.readFile(sourcePath, 'utf8');
  const startMarker = '    async function stageModularFrameworks() {';
  const endMarker = '    await stageModularFrameworks();';
  const start = source.indexOf(startMarker);
  const end = source.indexOf(endMarker, start);
  assert.ok(start >= 0 && end > start, 'exact production stage must be present');
  const body = source.slice(start, end);
  const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
  const names = ['cp', 'mkdir', 'readFile', 'readdir', 'rm', 'writeFile'];
  const run = new AsyncFunction(...names, 'existsSync', 'resolve', 'basename', 'dirname',
    'artifactsRoot', 'lock', 'preserveOriginalReactNativeHeaderModulemaps',
    `${body}\nreturn stageModularFrameworks();`);
  await run(...names.map((name) => fs[name]), existsSync, resolve, basename, dirname,
    artifactsRoot, { artifacts: [{ name: 'ReactNativeHeaders', sha256: provenance.sha256 }] },
    preserveOriginalReactNativeHeaderModulemaps);
}

async function hashes(root, relative = '') {
  const result = {};
  for (const entry of (await fs.readdir(resolve(root, relative), { withFileTypes: true })).sort((a, b) => a.name.localeCompare(b.name))) {
    const path = relative ? `${relative}/${entry.name}` : entry.name;
    if (entry.isDirectory()) Object.assign(result, await hashes(root, path));
    else if (entry.isFile()) result[path] = sha256(await fs.readFile(resolve(root, path)));
  }
  return result;
}

test('original header projection survives its own cleanup and rejects damaged source before replacement', async () => {
  const archive = resolve(fixture, 'headers.tar.gz');
  assert.equal(sha256(await fs.readFile(archive)), provenance.sha256);
  const temporary = await fs.mkdtemp(resolve(tmpdir(), 'hanlin-original-header-map-'));
  const artifactsRoot = resolve(temporary, 'Artifacts');
  await fs.mkdir(artifactsRoot);
  try {
    execFileSync('tar', ['-xzf', archive, '-C', artifactsRoot]);
    const xcf = resolve(artifactsRoot, 'ReactNativeHeaders.xcframework');
    await pruneNonIOSSlicesFromXCFramework(xcf);
    const slice = 'ios-arm64_x86_64-simulator';
    const originalMap = await fs.readFile(resolve(xcf, slice, 'Headers/module.modulemap'), 'utf8');
    assert.equal(sha256(originalMap), provenance.modulemapSHA256);
    const appDelegate = originalMap.match(/module React_RCTAppDelegate\s*\{([^}]+)\}/);
    assert.ok(appDelegate, 'the original archive declares the module used by HanlinExpoSession');
    const originalHeaders = [...appDelegate[1].matchAll(/header\s+"([^"]+)"/g)].map((match) => match[1]);
    assert.equal(originalHeaders.length, 9);
    const frameworks = resolve(artifactsRoot, 'ModularFrameworks');
    const moduleRoot = resolve(frameworks, 'React_RCTAppDelegate.framework');
    const expectedMap = `framework module React_RCTAppDelegate {\n${originalHeaders.map((path) => `    header "${basename(path)}"`).join('\n')}\n    export *\n}\n`;
    let firstProjection;
    for (let pass = 1; pass <= 2; pass++) {
      await productionStage(artifactsRoot);
      assert.ok(existsSync(resolve(moduleRoot, 'Modules/module.modulemap')), `pass ${pass} must retain the real AppDelegate module`);
      assert.equal(await fs.readFile(resolve(moduleRoot, 'Modules/module.modulemap'), 'utf8'), expectedMap);
      for (const path of originalHeaders) {
        assert.deepEqual(await fs.readFile(resolve(moduleRoot, 'Headers', basename(path))),
          await fs.readFile(resolve(xcf, slice, 'Headers', path)), `original header ${path}`);
      }
      assert.equal(existsSync(resolve(xcf, slice, 'Headers/module.modulemap')), false,
        'duplicate-module cleanup remains active');
      if (pass === 1) firstProjection = await hashes(frameworks);
      else assert.deepEqual(await hashes(frameworks), firstProjection);
    }
    const recordPath = resolve(xcf, '.original-header-modulemaps.json');
    const validText = await fs.readFile(recordPath, 'utf8');
    const valid = JSON.parse(validText);
    assert.equal(valid.artifactSHA256, provenance.sha256);
    assert.deepEqual(Object.keys(valid.slices).sort(), ['ios-arm64', slice].sort());
    for (const saved of Object.values(valid.slices)) {
      assert.equal(saved.content, originalMap);
      assert.equal(saved.sha256, provenance.modulemapSHA256);
    }
    const projection = await hashes(frameworks);
    for (const damage of [
      (record) => { record.artifactSHA256 = 'wrong-artifact'; },
      (record) => { record.slices[slice].content += '\n'; },
      (record) => { delete record.slices[slice]; },
      (record) => { record.slices[slice].headersPath = 'wrong-headers'; },
    ]) {
      const broken = structuredClone(valid);
      damage(broken);
      await fs.writeFile(recordPath, JSON.stringify(broken));
      await assert.rejects(() => productionStage(artifactsRoot), /Missing or invalid original ReactNativeHeaders modulemap source/);
      assert.deepEqual(await hashes(frameworks), projection, 'invalid source cannot clear the last projection');
    }
    await fs.rm(recordPath);
    await assert.rejects(() => productionStage(artifactsRoot), /Missing or invalid original ReactNativeHeaders modulemap source/);
    assert.deepEqual(await hashes(frameworks), projection);
    // Fresh authenticated extraction takes precedence over absent/damaged backup.
    for (const id of Object.keys(valid.slices)) {
      await fs.writeFile(resolve(xcf, id, 'Headers/module.modulemap'), originalMap);
    }
    await fs.writeFile(recordPath, '{invalid json');
    await productionStage(artifactsRoot);
    assert.equal(await fs.readFile(recordPath, 'utf8'), validText);
    assert.deepEqual(await hashes(frameworks), projection);
    console.log(JSON.stringify({ originalArchiveSHA256: provenance.sha256,
      originalModulemapSHA256: provenance.modulemapSHA256, projectedFiles: Object.keys(projection).length,
      appDelegateHeaders: originalHeaders.length, repeatedPasses: 2, rejectedSourceMutations: 5 }));
  } finally {
    await fs.rm(temporary, { recursive: true, force: true });
  }
});
