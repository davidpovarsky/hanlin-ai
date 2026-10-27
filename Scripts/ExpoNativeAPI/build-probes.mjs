import { cp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { execFileSync, execSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const scriptRoot = resolve(import.meta.dirname);
const repoRoot = resolve(scriptRoot, '..', '..');
const probeSrcRoot = resolve(repoRoot, 'Fixtures', 'ExpoNativeAPIProbe');
const uiTestFixturesRoot = resolve(repoRoot, 'AI_HLYUITests', 'Fixtures');
const expoScriptRoot = resolve(repoRoot, 'Scripts', 'Expo');

const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');

async function createZip(sourceDir, targetZip) {
  await rm(targetZip, { force: true });
  const pythonBin = process.platform === 'win32' ? 'python' : 'python3';
  const pyCode = `
import zipfile, os, sys
target_zip = sys.argv[1]
source_dir = sys.argv[2]
entries = []
for root, dirs, files in os.walk(source_dir):
    for f in files:
        full = os.path.join(root, f)
        rel = os.path.relpath(full, source_dir).replace('\\\\', '/')
        entries.append((rel, full))
entries.sort(key=lambda x: x[0])
with zipfile.ZipFile(target_zip, 'w', compression=zipfile.ZIP_DEFLATED) as zf:
    for rel, full in entries:
        zinfo = zipfile.ZipInfo(rel)
        zinfo.date_time = (2026, 1, 1, 0, 0, 0)
        zinfo.external_attr = 0o644 << 16
        with open(full, 'rb') as fp:
            zf.writestr(zinfo, fp.read())
`;
  execFileSync(pythonBin, ['-c', pyCode, targetZip, sourceDir], { stdio: 'inherit' });
}

async function bundleWithMetro(entryFile, outputFile) {
  const metroConfig = resolve(expoScriptRoot, 'metro.config.cjs');
  const metroCmd = `npx react-native bundle --entry-file "${entryFile}" --platform ios --dev false --bundle-output "${outputFile}" --config "${metroConfig}" --reset-cache`;
  execSync(metroCmd, { cwd: expoScriptRoot, stdio: 'inherit' });
}

export async function buildProbes() {
  console.log('[HanlinExpoNativeAPI] Building deterministic Native API probe packages...');
  await mkdir(uiTestFixturesRoot, { recursive: true });

  const buildScratch = resolve(scriptRoot, '.scratch', 'probes');
  await rm(buildScratch, { recursive: true, force: true });
  await mkdir(buildScratch, { recursive: true });

  const packageJSON = JSON.parse(await readFile(resolve(probeSrcRoot, 'package.json'), 'utf8'));
  const scriptJSON = JSON.parse(await readFile(resolve(probeSrcRoot, 'script.json'), 'utf8'));

  // 1. Build Variant A
  console.log('[HanlinExpoNativeAPI] Bundling Variant A...');
  const dirA = resolve(buildScratch, 'variant-a');
  await mkdir(dirA, { recursive: true });
  const bundleA = resolve(dirA, 'bundle.js');
  await bundleWithMetro(resolve(probeSrcRoot, 'variant-a.ts'), bundleA);

  const scriptA = { ...scriptJSON, name: 'Hanlin Expo Native API Probe A', description: 'Variant A: Real UIKit UILabel + UISwitch inside SwiftUI' };
  await writeFile(resolve(dirA, 'package.json'), JSON.stringify(packageJSON, null, 2), 'utf8');
  await writeFile(resolve(dirA, 'script.json'), JSON.stringify(scriptA, null, 2), 'utf8');

  const zipA = resolve(probeSrcRoot, 'ExpoNativeAPIProbeA.hanlinExpo');
  await createZip(dirA, zipA);
  await cp(zipA, resolve(uiTestFixturesRoot, 'ExpoNativeAPIProbeA.hanlinExpo'));
  console.log(`[HanlinExpoNativeAPI] Staged: ${zipA} (SHA256: ${sha256(await readFile(zipA))})`);

  // 2. Build Variant B
  console.log('[HanlinExpoNativeAPI] Bundling Variant B...');
  const dirB = resolve(buildScratch, 'variant-b');
  await mkdir(dirB, { recursive: true });
  const bundleB = resolve(dirB, 'bundle.js');
  await bundleWithMetro(resolve(probeSrcRoot, 'variant-b.ts'), bundleB);

  const scriptB = { ...scriptJSON, name: 'Hanlin Expo Native API Probe B', description: 'Variant B: Dynamic UIKit State Propagation Demo' };
  await writeFile(resolve(dirB, 'package.json'), JSON.stringify(packageJSON, null, 2), 'utf8');
  await writeFile(resolve(dirB, 'script.json'), JSON.stringify(scriptB, null, 2), 'utf8');

  const zipB = resolve(probeSrcRoot, 'ExpoNativeAPIProbeB.hanlinExpo');
  await createZip(dirB, zipB);
  await cp(zipB, resolve(uiTestFixturesRoot, 'ExpoNativeAPIProbeB.hanlinExpo'));
  console.log(`[HanlinExpoNativeAPI] Staged: ${zipB} (SHA256: ${sha256(await readFile(zipB))})`);

  // 3. Build Missing Grant Negative Probe (uses bundle A but capabilities: [])
  console.log('[HanlinExpoNativeAPI] Building Missing Grant negative probe...');
  const dirMissingGrant = resolve(buildScratch, 'missing-grant');
  await mkdir(dirMissingGrant, { recursive: true });
  await cp(bundleA, resolve(dirMissingGrant, 'bundle.js'));

  const scriptMissingGrant = {
    ...scriptJSON,
    name: 'Hanlin Expo Native API Probe (Missing Grant)',
    capabilities: [] // Explicitly missing ios-native-api!
  };
  await writeFile(resolve(dirMissingGrant, 'package.json'), JSON.stringify(packageJSON, null, 2), 'utf8');
  await writeFile(resolve(dirMissingGrant, 'script.json'), JSON.stringify(scriptMissingGrant, null, 2), 'utf8');

  const zipMissingGrant = resolve(probeSrcRoot, 'ExpoNativeAPIProbeMissingGrant.hanlinExpo');
  await createZip(dirMissingGrant, zipMissingGrant);
  await cp(zipMissingGrant, resolve(uiTestFixturesRoot, 'ExpoNativeAPIProbeMissingGrant.hanlinExpo'));
  console.log(`[HanlinExpoNativeAPI] Staged: ${zipMissingGrant} (SHA256: ${sha256(await readFile(zipMissingGrant))})`);

  // 4. Build Incompatible Version Negative Probe
  console.log('[HanlinExpoNativeAPI] Building Incompatible Version negative probe...');
  const dirIncompatible = resolve(buildScratch, 'incompatible');
  await mkdir(dirIncompatible, { recursive: true });
  await cp(bundleA, resolve(dirIncompatible, 'bundle.js'));

  const pkgIncompatible = {
    ...packageJSON,
    hanlinExpo: {
      ...packageJSON.hanlinExpo,
      plugins: {
        ...packageJSON.hanlinExpo.plugins,
        '@nativescript/react-native': '8.0.0' // Unsupported incompatible version!
      }
    }
  };
  await writeFile(resolve(dirIncompatible, 'package.json'), JSON.stringify(pkgIncompatible, null, 2), 'utf8');
  await writeFile(resolve(dirIncompatible, 'script.json'), JSON.stringify(scriptJSON, null, 2), 'utf8');

  const zipIncompatible = resolve(probeSrcRoot, 'ExpoNativeAPIProbeIncompatible.hanlinExpo');
  await createZip(dirIncompatible, zipIncompatible);
  await cp(zipIncompatible, resolve(uiTestFixturesRoot, 'ExpoNativeAPIProbeIncompatible.hanlinExpo'));
  console.log(`[HanlinExpoNativeAPI] Staged: ${zipIncompatible} (SHA256: ${sha256(await readFile(zipIncompatible))})`);

  // 5. Build Malformed Negative Probe
  console.log('[HanlinExpoNativeAPI] Building Malformed negative probe...');
  const dirMalformed = resolve(buildScratch, 'malformed');
  await mkdir(dirMalformed, { recursive: true });
  const scriptMalformed = {
    name: 'Hanlin Expo Native API Malformed',
    version: '1.0.0',
    runInApp: true,
    hanlinRuntime: 'hanlin-expo',
    entry: 'nonexistent-bundle.js'
  };
  await writeFile(resolve(dirMalformed, 'script.json'), JSON.stringify(scriptMalformed, null, 2), 'utf8');

  const zipMalformed = resolve(probeSrcRoot, 'ExpoNativeAPIMalformed.hanlinExpo');
  await createZip(dirMalformed, zipMalformed);
  await cp(zipMalformed, resolve(uiTestFixturesRoot, 'ExpoNativeAPIMalformed.hanlinExpo'));
  console.log(`[HanlinExpoNativeAPI] Staged: ${zipMalformed} (SHA256: ${sha256(await readFile(zipMalformed))})`);

  console.log('[HanlinExpoNativeAPI] All test probe packages created and staged successfully.');
}

const isMain = process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url));
if (isMain) {
  buildProbes().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
