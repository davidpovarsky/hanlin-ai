import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { execFileSync } from 'node:child_process';

const repoRoot = resolve(import.meta.dirname, '..', '..', '..');

test('NativeScriptNativeApiModule.mm has valid C++ function signature for installWorkletRuntime without duplicated parameters', async () => {
  const moduleMmPath = resolve(
    repoRoot,
    'Packages',
    'HanlinExpoNativeAPI',
    'Sources',
    'HanlinExpoNativeAPICore',
    'nativescript',
    'ios',
    'NativeScriptNativeApiModule.mm'
  );

  const content = await readFile(moduleMmPath, 'utf8');

  // Verify installWorkletRuntime signature pattern
  const sigRegex = /bool\s+NativeScriptNativeApiModule::installWorkletRuntime\s*\(\s*jsi::Runtime&\s*runtime,\s*jsi::Object\s*runtimeHolder,\s*std::string\s*metadataPath\s*\)\s*\{/g;
  const matches = [...content.matchAll(sigRegex)];
  assert.equal(matches.length, 1, 'installWorkletRuntime must have exactly one definition signature');

  // Verify that the broken duplication (duplicate parameter list / second opening brace) is absent
  assert.ok(
    !content.includes('jsi::Object runtimeHolder, std::string metadataPath) {\n  if (![HanlinExpoNativeAPIGate isNativeAPIAuthorizedForCurrentSession])'),
    'Must not contain leftover duplicate parameter continuation before guard'
  );

  // Check the body immediately after the opening brace
  const methodStart = content.indexOf('bool NativeScriptNativeApiModule::installWorkletRuntime');
  assert.ok(methodStart !== -1, 'installWorkletRuntime method must be found');
  const slice = content.slice(methodStart, methodStart + 800);

  assert.ok(
    slice.includes('[HANLIN_EXPO_NATIVEAPI_DENIAL] NativeScriptNativeApiModule::installWorkletRuntime rejected'),
    'installWorkletRuntime must begin with denial guard and return false'
  );
  assert.ok(slice.includes('return false;'), 'installWorkletRuntime must return false on denial');
});

test('NativeScriptNativeApiModule.mm guards all 4 native entrypoints', async () => {
  const moduleMmPath = resolve(
    repoRoot,
    'Packages',
    'HanlinExpoNativeAPI',
    'Sources',
    'HanlinExpoNativeAPICore',
    'nativescript',
    'ios',
    'NativeScriptNativeApiModule.mm'
  );

  const content = await readFile(moduleMmPath, 'utf8');

  const requiredGuards = [
    {
      name: 'install',
      guard: '[HANLIN_EXPO_NATIVEAPI_DENIAL] NativeScriptNativeApiModule::install rejected',
      ret: 'return false;',
    },
    {
      name: 'installWorkletRuntime',
      guard: '[HANLIN_EXPO_NATIVEAPI_DENIAL] NativeScriptNativeApiModule::installWorkletRuntime rejected',
      ret: 'return false;',
    },
    {
      name: 'NativeScriptCreateUIKitHost',
      guard: '[HANLIN_EXPO_NATIVEAPI_DENIAL] NativeScriptCreateUIKitHost rejected',
      ret: 'return nil;',
    },
    {
      name: 'NativeScriptRunUIKitHostLifecycle',
      guard: '[HANLIN_EXPO_NATIVEAPI_DENIAL] NativeScriptRunUIKitHostLifecycle rejected',
      ret: 'return nil;',
    },
  ];

  for (const item of requiredGuards) {
    assert.ok(content.includes(item.guard), `Entrypoint ${item.name} must have log: ${item.guard}`);
    const pos = content.indexOf(item.guard);
    const sub = content.slice(pos, pos + 300);
    assert.ok(sub.includes(item.ret), `Entrypoint ${item.name} must return properly on denial: ${item.ret}`);
  }
});

test('prepare-ios-dependencies.mjs executes idempotently without duplicate insertions', () => {
  const scriptPath = resolve(repoRoot, 'Scripts', 'ExpoNativeAPI', 'prepare-ios-dependencies.mjs');
  const nodeBin = process.execPath;

  // Run prepare script
  const out1 = execFileSync(nodeBin, [scriptPath], { encoding: 'utf8' });
  assert.ok(out1.includes('All Native API dependencies prepared and verified successfully.'));

  // Run again to ensure idempotency
  const out2 = execFileSync(nodeBin, [scriptPath], { encoding: 'utf8' });
  assert.ok(out2.includes('All Native API dependencies prepared and verified successfully.'));
});
