import { createHash } from 'node:crypto';
import { existsSync } from 'node:fs';
import { open, readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptRoot = resolve(import.meta.dirname);
const repoRoot = resolve(scriptRoot, '..', '..');

const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');

export async function preflight() {
  console.log('=== Hanlin Expo + NativeScript Native API Preflight Check ===');

  let passed = true;
  const check = (desc, condition) => {
    if (condition) {
      console.log(`[PASS] ${desc}`);
    } else {
      console.error(`[FAIL] ${desc}`);
      passed = false;
    }
  };

  // 1. Check lockfiles
  const expoLockPath = resolve(repoRoot, 'Scripts', 'Expo', 'dependency-lock.json');
  const nativeLockPath = resolve(scriptRoot, 'dependency-lock.json');
  check('Scripts/Expo/dependency-lock.json exists', existsSync(expoLockPath));
  check('Scripts/ExpoNativeAPI/dependency-lock.json exists', existsSync(nativeLockPath));

  const expoLock = JSON.parse(await readFile(expoLockPath, 'utf8'));
  const nativeLock = JSON.parse(await readFile(nativeLockPath, 'utf8'));

  check('React Native stable 0.88.0 in dependency-lock', expoLock.expo.reactNativeVersion === '0.88.0');
  check('Hermes 260318099.0.4 in dependency-lock', expoLock.expo.hermesVersion === '260318099.0.4');
  check('NativeScript RN 9.1.2 in dependency-lock', nativeLock.nativeApi.version === '9.1.2');
  check('Worklets 0.13.1 in dependency-lock', nativeLock.worklets.version === '0.13.1');

  // 2. Check Babel configuration
  const babelConfigPath = resolve(repoRoot, 'Scripts', 'Expo', 'babel.config.cjs');
  check('Scripts/Expo/babel.config.cjs exists', existsSync(babelConfigPath));
  if (existsSync(babelConfigPath)) {
    const babelText = await readFile(babelConfigPath, 'utf8');
    check("Babel config has '@nativescript/react-native/babel-plugin'", babelText.includes('@nativescript/react-native/babel-plugin'));
    check("Babel config has 'react-native-worklets/plugin' with strictGlobal: true", babelText.includes('strictGlobal: true'));
    check("Babel config disables default worklets transform (worklets: false)", babelText.includes('worklets: false'));
  }

  // 3. Check native package structure
  const pkgDir = resolve(repoRoot, 'Packages', 'HanlinExpoNativeAPI');
  check('Packages/HanlinExpoNativeAPI/Package.swift exists', existsSync(resolve(pkgDir, 'Package.swift')));
  check('NativeScript sources staged', existsSync(resolve(pkgDir, 'Sources', 'HanlinExpoNativeAPI', 'nativescript', 'ios', 'NativeScriptNativeApiModule.mm')));
  check('Worklets sources staged', existsSync(resolve(pkgDir, 'Sources', 'HanlinExpoNativeAPI', 'worklets', 'Common', 'cpp', 'worklets')));
  check('Generated codegen specs exist', existsSync(resolve(pkgDir, 'Sources', 'HanlinExpoNativeAPI', 'generated', 'NativeScriptNativeApiSpec', 'NativeScriptNativeApiSpecJSI.h')));
  check('HanlinExpoNativeAPIGate exists', existsSync(resolve(pkgDir, 'Sources', 'HanlinExpoNativeAPI', 'bridge', 'HanlinExpoNativeAPIGate.mm')));
  check('HanlinExpoDependencyProvider exists', existsSync(resolve(pkgDir, 'Sources', 'HanlinExpoNativeAPI', 'bridge', 'HanlinExpoDependencyProvider.mm')));

  // 4. Check metadata files
  const metaDir = resolve(pkgDir, 'Artifacts', 'metadata');
  for (const m of ['metadata.ios.arm64.nsmd', 'metadata.ios-sim.arm64.nsmd', 'metadata.ios-sim.x86_64.nsmd']) {
    check(`Metadata file exists: ${m}`, existsSync(resolve(metaDir, m)));
  }

  // 5. Check JS facade
  const facadeDir = resolve(repoRoot, 'Packages', 'HanlinExpoNativeAPIJS');
  check('Packages/HanlinExpoNativeAPIJS/package.json exists', existsSync(resolve(facadeDir, 'package.json')));
  check('Packages/HanlinExpoNativeAPIJS/src/index.ts exists', existsSync(resolve(facadeDir, 'src', 'index.ts')));

  if (!passed) {
    throw new Error('Preflight checks failed.');
  }

  console.log('[HanlinExpoNativeAPI] Preflight completed successfully. All components verified.');
}

const isMain = process.argv[1] && resolve(fileURLToPath(import.meta.url)) === resolve(process.argv[1]);
if (isMain) {
  preflight().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
