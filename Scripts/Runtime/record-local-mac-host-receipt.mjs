#!/usr/bin/env node
// Explicit original-producer verification; no CI identity, test, build, sync or publication is synthesized.
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { createReadStream } from 'node:fs';
import { lstat, readFile, writeFile } from 'node:fs/promises';
import { dirname, isAbsolute, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { isDeepStrictEqual } from 'node:util';
import { accountLocalMacHostExecution } from './local-mac-host-accounting.mjs';

async function readBounded(path, limit) {
  const info = await lstat(path);
  if (!info.isFile() || info.size > limit) throw Error('Missing, nonregular or oversized local producer proof');
  const bytes = await readFile(path);
  if (bytes.length > limit) throw Error('Local producer proof changed while reading');
  return bytes.toString('utf8');
}
async function hashFile(path) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest('hex');
}
function sourcePath(root, relative) {
  if (typeof relative !== 'string' || isAbsolute(relative) || relative.includes('\\')
      || relative.split('/').some(part => !part || part === '.' || part === '..')) throw Error('Invalid native source input path');
  return resolve(root, relative);
}

export async function recordLocalMacHostReceipt(configPath, preparationSHA256) {
  if (!/^[a-f0-9]{64}$/.test(preparationSHA256 ?? '')) throw Error('An independently authenticated original preparation SHA-256 is required');
  const config = JSON.parse(await readBounded(configPath, 65_536));
  const base = dirname(resolve(configPath));
  const path = key => {
    if (typeof config[key] !== 'string' || !config[key]) throw Error('Missing local producer path: ' + key);
    return resolve(base, config[key]);
  };
  const proof = {
    preparation: await readBounded(path('preparation'), 131_072),
    controller: await readBounded(path('controller'), 262_144),
    log: await readBounded(path('log'), 1_048_576),
    nativeCatalog: await readBounded(path('nativeCatalog'), 262_144),
    nativeInventory: await readBounded(path('nativeInventory'), 16_777_216),
  };
  if (createHash('sha256').update(proof.preparation).digest('hex') !== preparationSHA256)
    throw Error('Original preparation receipt does not match the independent trusted digest');
  const preparation = JSON.parse(proof.preparation);
  const catalog = JSON.parse(proof.nativeCatalog);
  const root = path('root');
  const archive = path('archive');
  const hostMetadata = JSON.parse(await readBounded(path('metadata'), 65_536));
  const nodeFingerprint = { versions: process.versions, platform: process.platform, arch: process.arch };
  if (process.platform !== 'darwin' || process.arch !== 'arm64' || process.versions.node !== '24.5.0')
    throw Error('Original producer verification requires the recorded Mac arm64 Node24.5.0 toolchain');
  const run = (command, args) => execFileSync(command, args, { cwd: root, encoding: 'utf8', timeout: 60_000,
    maxBuffer: 2_097_152, env: { ...process.env, PATH: dirname(process.execPath) + ':' + (process.env.PATH ?? ''), PYTHONDONTWRITEBYTECODE: '1' }, stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  if (!/^[a-f0-9]{40}$/.test(preparation.source ?? '')) throw Error('Missing original source identity');
  const sourceCheckout = run('git', ['rev-parse', 'HEAD']);
  run('git', ['cat-file', '-e', `${preparation.source}^{commit}`]);
  const nativeInputSHA256 = {};
  for (const relative of Object.keys(catalog.inputSHA256 ?? {}).sort())
    nativeInputSHA256[relative] = await hashFile(sourcePath(root, relative));
  const archiveSHA256 = await hashFile(archive);
  const validator = resolve(root, 'Scripts/Runtime/runtime_host_archive.py');
  const python = config.python ?? 'python3';
  if (typeof python !== 'string' || !python) throw Error('Invalid Python executable');
  const fingerprint = () => run(python, [validator, 'fingerprint', '--source-root',
    resolve(root, 'AI_HLY/Downstream/RuntimeCore/Node/Host'), '--node-fingerprint', JSON.stringify(nodeFingerprint)]);
  const sourceInputsHash = fingerprint();
  const hostAccounting = accountLocalMacHostExecution({ repository: config.repository, head: preparation.source,
    archiveSHA256, sourceInputsHash, nodeFingerprint, hostMetadata, nativeInputSHA256, proof,
    authentication: { preparationSHA256 } });
  if (!hostAccounting.accepted) throw Error('Local Mac origin rejected: ' + hostAccounting.reasons.join(', '));
  // Run the original lock, license, patched-dependency, complete SDK and module-byte validator.
  run(python, [validator, 'validate', archive, '--source-root', resolve(root, 'AI_HLY/Downstream/RuntimeCore/Node/Host')]);
  if (fingerprint() !== sourceInputsHash || await hashFile(archive) !== archiveSHA256
      || run('git', ['rev-parse', 'HEAD']) !== sourceCheckout
      || !isDeepStrictEqual(JSON.parse(await readBounded(path('metadata'), 65_536)), hostMetadata))
    throw Error('Original source, archive, checkout or metadata changed during verification');
  for (const [relative, hash] of Object.entries(nativeInputSHA256))
    if (await hashFile(sourcePath(root, relative)) !== hash) throw Error('Native source inputs changed during verification');
  const receipt = { schemaVersion: 3, provider: 'local-mac', repository: config.repository,
    head: preparation.source, status: 'EXECUTED_PASS', hostMetadata, hostAccounting,
    verification: { verifiedAt: new Date().toISOString(), sourceCheckout, nodeFingerprint, nativeInputSHA256,
      canonicalArchiveValidatorSHA256: await hashFile(validator), sourceInputsHash, archiveSHA256,
      scope: 'Original local Mac producer only; no fresh test execution, derivative acceptance, GitHub check or native build is asserted.' } };
  // Original evidence and any existing receipt are immutable; select a new output explicitly.
  await writeFile(path('output'), JSON.stringify(receipt, null, 2) + '\n', { flag: 'wx' });
  return receipt;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [configPath, preparationSHA256] = process.argv.slice(2);
  if (!configPath || process.argv.length !== 4) throw Error('Expected config.json independently-authenticated-preparation-sha256');
  const receipt = await recordLocalMacHostReceipt(configPath, preparationSHA256);
  console.log(JSON.stringify({ status: receipt.status, provider: receipt.provider, head: receipt.head,
    archiveSHA256: receipt.hostMetadata.archiveSha256, counts: receipt.hostAccounting.origin.counts }));
}
