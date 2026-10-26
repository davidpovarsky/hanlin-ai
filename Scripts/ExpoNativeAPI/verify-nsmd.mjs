import { createHash } from 'node:crypto';
import { existsSync } from 'node:fs';
import { open, readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptRoot = resolve(import.meta.dirname);
const repoRoot = resolve(scriptRoot, '..', '..');

const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');

export async function verifyNSMD(baseDir) {
  const metadataDir = baseDir || resolve(repoRoot, 'Packages', 'HanlinExpoNativeAPI', 'Artifacts', 'metadata');
  console.log(`[HanlinExpoNativeAPI] Verifying NativeScript metadata files in: ${metadataDir}`);

  const requiredSlices = [
    { file: 'metadata.ios.arm64.nsmd', sha256: '50aabcb10723560a74500001cc2d64a034c05a5c755de35127fcc7601a7909f3' },
    { file: 'metadata.ios-sim.arm64.nsmd', sha256: '33296faebf7f32db36d70304aef5fe27dfc1a283df6487c53d8a0a5931e4e73c' },
    { file: 'metadata.ios-sim.x86_64.nsmd', sha256: 'c811940bcb2202189473f52a2ccc368b34f3124a7d7f677e6702af61b0112d66' }
  ];

  for (const item of requiredSlices) {
    const fullPath = resolve(metadataDir, item.file);
    if (!existsSync(fullPath)) {
      throw new Error(`[HanlinExpoNativeAPI] Missing required metadata slice: ${item.file}`);
    }

    const fh = await open(fullPath, 'r');
    const headerBuf = Buffer.alloc(4);
    await fh.read(headerBuf, 0, 4, 0);
    await fh.close();

    const magic = headerBuf.toString('ascii');
    if (magic !== 'NSMD') {
      throw new Error(`[HanlinExpoNativeAPI] Invalid magic header in ${item.file}: expected 'NSMD', got '${magic}'`);
    }

    const content = await readFile(fullPath);
    const digest = sha256(content);
    if (digest !== item.sha256) {
      throw new Error(`[HanlinExpoNativeAPI] Checksum mismatch for ${item.file}: expected ${item.sha256}, got ${digest}`);
    }

    console.log(`[HanlinExpoNativeAPI] Verified ${item.file} (${content.length} bytes, SHA256: ${digest})`);
  }

  console.log('[HanlinExpoNativeAPI] All NativeScript metadata files verified successfully.');
}

const isMain = process.argv[1] && resolve(fileURLToPath(import.meta.url)) === resolve(process.argv[1]);
if (isMain) {
  verifyNSMD().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
