import test from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const repoRoot = resolve(import.meta.dirname, '..', '..', '..');

test('Babel configuration has correct plugin order and strictGlobal', () => {
  const babelConfigPath = resolve(repoRoot, 'Scripts', 'Expo', 'babel.config.cjs');
  const babelModule = require(babelConfigPath);
  const config = typeof babelModule === 'function' ? babelModule({ cache: () => {} }) : babelModule;

  assert.ok(Array.isArray(config.plugins), 'config.plugins must be an array');
  const plugins = config.plugins;

  // 1. NativeScript plugin must appear
  const nsIdx = plugins.findIndex(
    (p) => p === '@nativescript/react-native/babel-plugin' || (Array.isArray(p) && p[0] === '@nativescript/react-native/babel-plugin')
  );
  assert.ok(nsIdx !== -1, "Must contain '@nativescript/react-native/babel-plugin'");

  // 2. Worklets plugin must appear with strictGlobal: true
  const wlIdx = plugins.findIndex(
    (p) => p === 'react-native-worklets/plugin' || (Array.isArray(p) && p[0] === 'react-native-worklets/plugin')
  );
  assert.ok(wlIdx !== -1, "Must contain 'react-native-worklets/plugin'");
  assert.ok(Array.isArray(plugins[wlIdx]), 'Worklets plugin must be configured with options');
  assert.equal(plugins[wlIdx][1]?.strictGlobal, true, 'Worklets plugin must have strictGlobal: true');

  // 3. NativeScript must be before Worklets, and Worklets should be last
  assert.ok(nsIdx < wlIdx, 'NativeScript Babel plugin must come before Worklets plugin');
  assert.equal(wlIdx, plugins.length - 1, 'Worklets plugin must be last in plugin list');
});
