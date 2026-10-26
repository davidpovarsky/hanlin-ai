import { createHash } from 'node:crypto';
import { existsSync } from 'node:fs';
import { readFile, readdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptRoot = resolve(import.meta.dirname);
const repoRoot = resolve(scriptRoot, '..', '..');

const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');

export async function verifyArtifacts() {
  console.log('=== Hanlin Expo Native API Artifacts Audit ===');

  const pkgDir = resolve(repoRoot, 'Packages', 'HanlinExpoNativeAPI');
  const artifactsDir = resolve(pkgDir, 'Artifacts');

  // 1. Verify Libffi
  const libffiDir = resolve(artifactsDir, 'Libffi.xcframework');
  if (!existsSync(libffiDir)) {
    throw new Error('[HanlinExpoNativeAPI] Missing Libffi.xcframework');
  }
  const libffiPlist = resolve(libffiDir, 'Info.plist');
  if (!existsSync(libffiPlist)) {
    throw new Error('[HanlinExpoNativeAPI] Missing Info.plist in Libffi.xcframework');
  }
  console.log('[PASS] Libffi.xcframework exists and has Info.plist');

  // 2. Audit against duplicate React/Hermes binaries
  const entries = await readdir(artifactsDir);
  for (const ent of entries) {
    if (ent.includes('React') || ent.includes('hermes')) {
      throw new Error(`[HanlinExpoNativeAPI] Forbidden duplicate framework in HanlinExpoNativeAPI/Artifacts: ${ent}. NativeAPI must link host closure.`);
    }
  }
  console.log('[PASS] No duplicate React or Hermes binaries in HanlinExpoNativeAPI/Artifacts');

  // 3. Verify metadata files
  const metaDir = resolve(artifactsDir, 'metadata');
  const requiredNsmd = ['metadata.ios.arm64.nsmd', 'metadata.ios-sim.arm64.nsmd', 'metadata.ios-sim.x86_64.nsmd'];
  for (const f of requiredNsmd) {
    const p = resolve(metaDir, f);
    if (!existsSync(p)) {
      throw new Error(`[HanlinExpoNativeAPI] Missing metadata file: ${f}`);
    }
  }
  console.log('[PASS] All metadata .nsmd files present');

  console.log('[HanlinExpoNativeAPI] Artifacts verification PASSED.');
}

const isMain = process.argv[1] && resolve(fileURLToPath(import.meta.url)) === resolve(process.argv[1]);
if (isMain) {
  verifyArtifacts().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
