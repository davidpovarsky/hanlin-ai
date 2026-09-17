import { cp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { execSync } from 'node:child_process';

const scriptRoot = resolve(import.meta.dirname);
const repositoryRoot = resolve(scriptRoot, '..', '..');
const probeSrcRoot = resolve(repositoryRoot, 'Fixtures', 'ExpoSwiftUIProbe');
const uiTestFixturesRoot = resolve(repositoryRoot, 'AI_HLYUITests', 'Fixtures');

async function buildVariant(variant) {
  console.log(`[HanlinExpo] Building Expo SwiftUI Probe Variant ${variant} with Metro...`);
  const buildDir = resolve(scriptRoot, '.build-probe', `variant-${variant}`);
  await rm(buildDir, { recursive: true, force: true });
  await mkdir(buildDir, { recursive: true });

  const entryFile = resolve(probeSrcRoot, variant === 'A' ? 'variant-a.ts' : 'variant-b.ts');
  const bundleOut = resolve(buildDir, 'bundle.js');
  const metroConfig = resolve(scriptRoot, 'metro.config.cjs');

  // Bundle with Metro into complete, self-contained CommonJS React Native bundle
  const metroCmd = `npx react-native bundle --entry-file "${entryFile}" --platform ios --dev false --bundle-output "${bundleOut}" --config "${metroConfig}" --reset-cache`;
  execSync(metroCmd, { cwd: scriptRoot, stdio: 'inherit' });

  // Copy manifest and package.json
  const packageJSON = JSON.parse(await readFile(resolve(probeSrcRoot, 'package.json'), 'utf8'));
  const scriptJSON = JSON.parse(await readFile(resolve(probeSrcRoot, 'script.json'), 'utf8'));

  scriptJSON.name = `Expo SwiftUI Probe ${variant}`;
  scriptJSON.description = `Dynamic Expo MiniApp Variant ${variant} rendering Apple SwiftUI.`;

  await writeFile(resolve(buildDir, 'package.json'), `${JSON.stringify(packageJSON, null, 2)}\n`);
  await writeFile(resolve(buildDir, 'script.json'), `${JSON.stringify(scriptJSON, null, 2)}\n`);

  // Create .hanlinExpo zip archive with deterministic forward slashes
  const targetZip = resolve(probeSrcRoot, `ExpoSwiftUIProbe${variant}.hanlinExpo`);
  await rm(targetZip, { force: true });

  const pythonBin = process.platform === 'win32' ? 'python' : 'python3';
  const pyCmd = `${pythonBin} -c "import zipfile, os, sys; zf = zipfile.ZipFile(sys.argv[1], 'w', zipfile.ZIP_DEFLATED); [zf.write(os.path.join(r, f), os.path.relpath(os.path.join(r, f), sys.argv[2]).replace('\\\\\\\\', '/')) for r, d, files in os.walk(sys.argv[2]) for f in files]; zf.close()" "${targetZip}" "${buildDir}"`;
  execSync(pyCmd);

  console.log(`[HanlinExpo] Created probe package: ${targetZip}`);
  return targetZip;
}

async function buildMalformed() {
  console.log('[HanlinExpo] Building Malformed Expo Probe...');
  const buildDir = resolve(scriptRoot, '.build-probe', 'malformed');
  await rm(buildDir, { recursive: true, force: true });
  await mkdir(buildDir, { recursive: true });

  // Malformed package: entry points to nonexistent file
  const scriptJSON = {
    name: 'Expo SwiftUI Malformed',
    version: '1.0.0',
    description: 'Malformed Expo package missing required bundle.',
    runInApp: true,
    hanlinRuntime: 'hanlin-expo',
    entry: 'nonexistent-bundle.js'
  };
  await writeFile(resolve(buildDir, 'script.json'), `${JSON.stringify(scriptJSON, null, 2)}\n`);

  const targetZip = resolve(probeSrcRoot, 'ExpoSwiftUIMalformed.hanlinExpo');
  await rm(targetZip, { force: true });
  const pythonBin = process.platform === 'win32' ? 'python' : 'python3';
  const pyCmd = `${pythonBin} -c "import zipfile, os, sys; zf = zipfile.ZipFile(sys.argv[1], 'w', zipfile.ZIP_DEFLATED); [zf.write(os.path.join(r, f), os.path.relpath(os.path.join(r, f), sys.argv[2]).replace('\\\\\\\\', '/')) for r, d, files in os.walk(sys.argv[2]) for f in files]; zf.close()" "${targetZip}" "${buildDir}"`;
  execSync(pyCmd);
  await cp(targetZip, resolve(uiTestFixturesRoot, 'ExpoSwiftUIMalformed.hanlinExpo'));
  console.log(`[HanlinExpo] Staged malformed probe package: ${targetZip}`);
}

async function main() {
  const zipA = await buildVariant('A');
  const zipB = await buildVariant('B');
  await buildMalformed();

  // Also create default ExpoSwiftUIProbe.hanlinExpo as Variant A
  const defaultZip = resolve(probeSrcRoot, 'ExpoSwiftUIProbe.hanlinExpo');
  await cp(zipA, defaultZip);
  console.log(`[HanlinExpo] Default probe package staged at: ${defaultZip}`);

  // Stage into AI_HLYUITests/Fixtures for automated test execution
  await mkdir(uiTestFixturesRoot, { recursive: true });
  await cp(zipA, resolve(uiTestFixturesRoot, 'ExpoSwiftUIProbeA.hanlinExpo'));
  await cp(zipB, resolve(uiTestFixturesRoot, 'ExpoSwiftUIProbeB.hanlinExpo'));
  await cp(defaultZip, resolve(uiTestFixturesRoot, 'ExpoSwiftUIProbe.hanlinExpo'));
  console.log(`[HanlinExpo] Test fixtures staged into: ${uiTestFixturesRoot}`);
}

main().catch((err) => {
  console.error('[HanlinExpo] Failed to build probe:', err);
  process.exit(1);
});
