import { createHash } from 'node:crypto';
import { existsSync } from 'node:fs';
import { copyFile, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const scriptRoot = resolve(import.meta.dirname);
const repoRoot = resolve(scriptRoot, '..', '..');
const nodeModules = resolve(repoRoot, 'Scripts', 'Expo', 'node_modules');
const lockPath = resolve(scriptRoot, 'dependency-lock.json');

const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');

export async function generateCodegen(options = {}) {
  const defaultBaseDir = resolve(repoRoot, 'Packages', 'HanlinExpoNativeAPI', 'Sources');
  const nsTargetDir = options.nsOutputDir || resolve(defaultBaseDir, 'HanlinExpoNativeAPICore', 'generated');
  const wlTargetDir = options.wlOutputDir || resolve(defaultBaseDir, 'HanlinExpoWorklets', 'generated');

  console.log(`[HanlinExpoNativeAPI] Generating NativeScriptNativeApiSpec into: ${nsTargetDir}`);
  console.log(`[HanlinExpoNativeAPI] Generating rnworklets into: ${wlTargetDir}`);

  const lock = JSON.parse(await readFile(lockPath, 'utf8'));

  const combineCli = resolve(nodeModules, '@react-native', 'codegen', 'lib', 'cli', 'combine', 'combine-js-to-schema-cli.js');
  const generateCli = resolve(nodeModules, '@react-native', 'codegen', 'lib', 'cli', 'generators', 'generate-all.js');

  if (!existsSync(combineCli) || !existsSync(generateCli)) {
    throw new Error(`[HanlinExpoNativeAPI] @react-native/codegen CLI tools not found in ${nodeModules}`);
  }

  const scratchDir = resolve(scriptRoot, '.scratch', 'codegen');
  await rm(scratchDir, { recursive: true, force: true });
  await mkdir(scratchDir, { recursive: true });

  // 1. NativeScriptNativeApiSpec
  const nsSrc = resolve(nodeModules, '@nativescript', 'react-native', 'src');
  const nsFiles = [
    resolve(nsSrc, 'NativeScriptNativeApi.ts'),
    resolve(nsSrc, 'NativeScriptUIViewNativeComponent.ts')
  ];
  for (const f of nsFiles) {
    if (!existsSync(f)) throw new Error(`[HanlinExpoNativeAPI] Missing spec file: ${f}`);
  }

  const nsSchemaPath = resolve(scratchDir, 'ns-schema.json');
  execFileSync(process.execPath, [combineCli, nsSchemaPath, ...nsFiles], { stdio: 'inherit' });

  const nsSchemaBytes = await readFile(nsSchemaPath);
  const nsSchemaDigest = sha256(nsSchemaBytes);
  console.log(`[HanlinExpoNativeAPI] NativeScript codegen schema SHA256: ${nsSchemaDigest}`);

  if (lock.nativeApi.codegen.schemaDigest && lock.nativeApi.codegen.schemaDigest !== nsSchemaDigest) {
    throw new Error(`[HanlinExpoNativeAPI] Schema digest mismatch for NativeScriptNativeApiSpec: expected ${lock.nativeApi.codegen.schemaDigest}, got ${nsSchemaDigest}`);
  }

  const nsOutDir = resolve(nsTargetDir, 'NativeScriptNativeApiSpec');
  await rm(nsOutDir, { recursive: true, force: true });
  await mkdir(nsOutDir, { recursive: true });

  execFileSync(process.execPath, [
    generateCli,
    nsSchemaPath,
    'NativeScriptNativeApiSpec',
    nsOutDir,
    'org.nativescript.nativeapi',
    'true'
  ], { stdio: 'inherit' });

  // Exclude non-iOS files (Java/JNI) from iOS build closure
  await rm(resolve(nsOutDir, 'java'), { recursive: true, force: true });
  await rm(resolve(nsOutDir, 'jni'), { recursive: true, force: true });
  // Exclude unit test files (gtest)
  await rm(resolve(nsOutDir, 'Tests.cpp'), { force: true });

  // Stage Fabric component headers to include/react/renderer/components/NativeScriptNativeApiSpec
  const fabricIncludeDir = resolve(defaultBaseDir, 'HanlinExpoNativeAPICore', 'include', 'react', 'renderer', 'components', 'NativeScriptNativeApiSpec');
  await rm(fabricIncludeDir, { recursive: true, force: true });
  await mkdir(fabricIncludeDir, { recursive: true });
  const fabricHeaders = [
    'ComponentDescriptors.h',
    'EventEmitters.h',
    'Props.h',
    'RCTComponentViewHelpers.h',
    'ShadowNodes.h',
    'States.h'
  ];
  for (const h of fabricHeaders) {
    const srcH = resolve(nsOutDir, h);
    if (existsSync(srcH)) {
      await copyFile(srcH, resolve(fabricIncludeDir, h));
    }
  }

  // 2. rnworklets
  const wlSpec = resolve(nodeModules, 'react-native-worklets', 'src', 'specs', 'NativeWorkletsModule.ts');
  if (existsSync(wlSpec)) {
    const wlSchemaPath = resolve(scratchDir, 'wl-schema.json');
    execFileSync(process.execPath, [combineCli, wlSchemaPath, wlSpec], { stdio: 'inherit' });

    const wlOutDir = resolve(wlTargetDir, 'rnworklets');
    await rm(wlOutDir, { recursive: true, force: true });
    await mkdir(wlOutDir, { recursive: true });

    execFileSync(process.execPath, [
      generateCli,
      wlSchemaPath,
      'rnworklets',
      wlOutDir,
      'com.swmansion.worklets',
      'true'
    ], { stdio: 'inherit' });

    // Exclude non-iOS files (Java/JNI) from iOS build closure
    await rm(resolve(wlOutDir, 'java'), { recursive: true, force: true });
    await rm(resolve(wlOutDir, 'jni'), { recursive: true, force: true });
    // Exclude unit test files (gtest)
    await rm(resolve(wlOutDir, 'Tests.cpp'), { force: true });

    // rnworklets is module-only (no Fabric components); remove dummy component files that generate missing header references
    const dummyComponentFiles = [
      'ComponentDescriptors.cpp',
      'ComponentDescriptors.h',
      'EventEmitters.cpp',
      'EventEmitters.h',
      'Props.cpp',
      'Props.h',
      'RCTComponentViewHelpers.h',
      'ShadowNodes.cpp',
      'ShadowNodes.h',
      'States.cpp',
      'States.h'
    ];
    for (const f of dummyComponentFiles) {
      await rm(resolve(wlOutDir, f), { force: true });
    }
  }

  console.log('[HanlinExpoNativeAPI] Codegen artifacts generated successfully (iOS-only targets).');
}

const isMain = process.argv[1] && resolve(fileURLToPath(import.meta.url)) === resolve(process.argv[1]);
if (isMain) {
  generateCodegen().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
