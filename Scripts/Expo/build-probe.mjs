import { cp, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { resolve, relative, isAbsolute } from 'node:path';
import { execFileSync } from 'node:child_process';
import { deterministicZip } from '../Widgets/deterministic-zip.mjs';

const scriptRoot = resolve(import.meta.dirname);
const repositoryRoot = resolve(scriptRoot, '..', '..');
const probeSrcRoot = resolve(repositoryRoot, 'Fixtures', 'ExpoSwiftUIProbe');
const uiTestFixturesRoot = resolve(repositoryRoot, 'AI_HLYUITests', 'Fixtures');
const ownedBuildRoot = resolve(scriptRoot, '.build-probe');

async function resetBuildDirectory(directory) {
  const suffix = relative(ownedBuildRoot, directory);
  if (!suffix || suffix.startsWith('..') || isAbsolute(suffix)) throw new Error('Unsafe Expo fixture build directory');
  await rm(directory, {recursive: true, force: true});
  await mkdir(directory, {recursive: true});
}

async function writeArchive(directory, destination) {
  const files = {};
  for (const item of await readdir(directory, {withFileTypes: true})) {
    if (!item.isFile()) throw new Error('Expo fixture archives accept regular top-level files only');
    // Source maps remain alongside build outputs; the runtime archive contains
    // the executable/manifest/resources consumed by the existing importer.
    if (!item.name.endsWith('.map')) files[item.name] = await readFile(resolve(directory, item.name));
  }
  await writeFile(destination, deterministicZip(files));
}

function bundleWithOriginalMetro(entryFile, bundleOut) {
  const metroConfig = resolve(scriptRoot, 'metro.config.cjs');
  execFileSync(process.execPath, [resolve(scriptRoot, 'node_modules/@react-native-community/cli/build/bin.js'),
    'bundle', '--entry-file', entryFile, '--platform', 'ios', '--dev', 'false', '--bundle-output', bundleOut,
    '--sourcemap-output', bundleOut + '.map', '--config', metroConfig, '--max-workers', '2'],
    {cwd: scriptRoot, stdio: 'inherit'});
}

async function buildVariant(variant) {
  console.log(`[HanlinExpo] Building Expo SwiftUI Probe Variant ${variant} with Metro...`);
  const buildDir = resolve(scriptRoot, '.build-probe', `variant-${variant}`);
  await resetBuildDirectory(buildDir);

  const entryFile = resolve(probeSrcRoot, variant === 'A' ? 'variant-a.ts' : 'variant-b.ts');
  const bundleOut = resolve(buildDir, 'bundle.js');
  const metroConfig = resolve(scriptRoot, 'metro.config.cjs');

  bundleWithOriginalMetro(entryFile, bundleOut);

  // Copy manifest and package.json
  const packageJSON = JSON.parse(await readFile(resolve(probeSrcRoot, 'package.json'), 'utf8'));
  const scriptJSON = JSON.parse(await readFile(resolve(probeSrcRoot, 'script.json'), 'utf8'));

  scriptJSON.name = `Expo SwiftUI Probe ${variant}`;
  scriptJSON.description = `Dynamic Expo MiniApp Variant ${variant} rendering Apple SwiftUI.`;

  await writeFile(resolve(buildDir, 'package.json'), `${JSON.stringify(packageJSON, null, 2)}\n`);
  await writeFile(resolve(buildDir, 'script.json'), `${JSON.stringify(scriptJSON, null, 2)}\n`);
  await cp(resolve(probeSrcRoot, 'widget.tsx'), resolve(buildDir, 'widget.tsx'));

  // Create .hanlinExpo zip archive with deterministic forward slashes
  const targetZip = resolve(probeSrcRoot, `ExpoSwiftUIProbe${variant}.hanlinExpo`);
  await rm(targetZip, { force: true });

  await writeArchive(buildDir, targetZip);

  console.log(`[HanlinExpo] Created probe package: ${targetZip}`);
  return targetZip;
}

async function buildMalformed() {
  console.log('[HanlinExpo] Building Malformed Expo Probe...');
  const buildDir = resolve(scriptRoot, '.build-probe', 'malformed');
  await resetBuildDirectory(buildDir);

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
  await writeArchive(buildDir, targetZip);
  await cp(targetZip, resolve(uiTestFixturesRoot, 'ExpoSwiftUIMalformed.hanlinExpo'));
  console.log(`[HanlinExpo] Staged malformed probe package: ${targetZip}`);
}

async function buildOriginalWidgetsProbe(variant) {
  const source = resolve(repositoryRoot, 'Fixtures/ExpoWidgetsProbe');
  const buildDir = resolve(ownedBuildRoot, 'original-widgets-' + variant);
  await resetBuildDirectory(buildDir);
  bundleWithOriginalMetro(resolve(source, variant === 'A' ? 'variant-a.ts' : 'variant-b.ts'), resolve(buildDir, 'bundle.js'));
  const packageJSON = JSON.parse(await readFile(resolve(source, 'package.json'), 'utf8'));
  const scriptJSON = JSON.parse(await readFile(resolve(source, 'script.json'), 'utf8'));
  packageJSON.name = 'expo-widgets-probe-' + variant.toLowerCase();
  scriptJSON.name = 'Original Expo Widgets Probe ' + variant;
  await writeFile(resolve(buildDir, 'package.json'), JSON.stringify(packageJSON, null, 2) + '\n');
  await writeFile(resolve(buildDir, 'script.json'), JSON.stringify(scriptJSON, null, 2) + '\n');
  const target = resolve(source, 'ExpoWidgetsProbe' + variant + '.hanlinExpo');
  await writeArchive(buildDir, target);
  await mkdir(uiTestFixturesRoot, {recursive:true});
  await cp(target, resolve(uiTestFixturesRoot, 'ExpoWidgetsProbe' + variant + '.hanlinExpo'));
  console.log('[HanlinExpo] Original public Widgets API probe staged: ' + target);
}

async function main() {
  console.log('[HanlinExpo] Running semantic TypeScript project check before Metro...');
  if (!process.argv.includes('--widgets-only')) execFileSync(process.execPath, [resolve(scriptRoot, 'check-ui-type-contract.mjs')], {cwd: scriptRoot, stdio: 'inherit'});
  execFileSync(process.execPath, [resolve(scriptRoot, 'check-ui-type-contract.mjs'), '--widgets'], {cwd: scriptRoot, stdio: 'inherit'});
  await buildOriginalWidgetsProbe('A');
  await buildOriginalWidgetsProbe('B');
  if (process.argv.includes('--widgets-only')) return;
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

main()
  .then(() => {
    process.exit(0);
  })
  .catch((err) => {
    console.error('[HanlinExpo] Failed to build probe:', err);
    process.exit(1);
  });
