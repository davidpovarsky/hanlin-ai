import { createHash } from 'node:crypto';
import { existsSync } from 'node:fs';
import { open, readFile, stat } from 'node:fs/promises';
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
    if (babelText.includes('babel-preset-expo')) {
      check("Babel config disables default worklets transform (worklets: false)", babelText.includes('worklets: false'));
    } else {
      check("Babel config uses authoritative @react-native/babel-preset without duplicate worklet transform", babelText.includes('@react-native/babel-preset'));
    }
  }

  // 3. Check native package structure (multi-target Clang/Swift layout)
  const pkgDir = resolve(repoRoot, 'Packages', 'HanlinExpoNativeAPI');
  check('Packages/HanlinExpoNativeAPI/Package.swift exists', existsSync(resolve(pkgDir, 'Package.swift')));
  check('HanlinExpoNativeAPI Swift orchestration exists', existsSync(resolve(pkgDir, 'Sources', 'HanlinExpoNativeAPI', 'HanlinExpoNativeAPIManager.swift')));
  check('NativeScript sources staged in HanlinExpoNativeAPICore', existsSync(resolve(pkgDir, 'Sources', 'HanlinExpoNativeAPICore', 'nativescript', 'ios', 'NativeScriptNativeApiModule.mm')));
  check('Worklets sources staged in HanlinExpoWorklets', existsSync(resolve(pkgDir, 'Sources', 'HanlinExpoWorklets', 'Common', 'cpp', 'worklets')));
  check('Generated NativeScript codegen specs exist', existsSync(resolve(pkgDir, 'Sources', 'HanlinExpoNativeAPICore', 'generated', 'NativeScriptNativeApiSpec', 'NativeScriptNativeApiSpecJSI.h')));
  check('Generated rnworklets codegen specs exist', existsSync(resolve(pkgDir, 'Sources', 'HanlinExpoWorklets', 'generated', 'rnworklets', 'rnworkletsJSI.h')));
  check('HanlinExpoNativeAPIGate exists in HanlinExpoNativeAPICore', existsSync(resolve(pkgDir, 'Sources', 'HanlinExpoNativeAPICore', 'bridge', 'HanlinExpoNativeAPIGate.mm')));
  check('HanlinExpoDependencyProvider exists in HanlinExpoNativeAPICore', existsSync(resolve(pkgDir, 'Sources', 'HanlinExpoNativeAPICore', 'bridge', 'HanlinExpoDependencyProvider.mm')));

  // Check Libffi static library slices
  const libffiArm64 = resolve(pkgDir, 'Artifacts', 'Libffi.xcframework', 'ios-arm64', 'libffi.a');
  const libffiSim = resolve(pkgDir, 'Artifacts', 'Libffi.xcframework', 'ios-arm64_x86_64-simulator', 'libffi.a');
  check('Libffi arm64 static library exists', existsSync(libffiArm64));
  check('Libffi simulator static library exists', existsSync(libffiSim));

  // 4. Check metadata files in Artifacts and target Resources
  const metaDir = resolve(pkgDir, 'Artifacts', 'metadata');
  const resourceMetaDir = resolve(pkgDir, 'Sources', 'HanlinExpoNativeAPI', 'Resources', 'metadata');
  for (const m of ['metadata.ios.arm64.nsmd', 'metadata.ios-sim.arm64.nsmd', 'metadata.ios-sim.x86_64.nsmd']) {
    check(`Artifacts metadata file exists: ${m}`, existsSync(resolve(metaDir, m)));
    check(`Target Resource metadata file exists: ${m}`, existsSync(resolve(resourceMetaDir, m)));
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
