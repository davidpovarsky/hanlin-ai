#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import process from 'node:process';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { selectHostPackageVersion } from './select-host-package-version.mjs';
import { runtimeDependencyHash } from './compute-runtime-dependency-hash.mjs';

const token = process.env.GITHUB_TOKEN ?? process.env.GH_TOKEN;

export async function planHostUpdates(hostPackage, nodeVersion, metadataFor, satisfies, options = {}) {
  const names = options.only ? [options.only] : Object.keys(hostPackage.dependencies);
  const updates = [];
  for (const name of names) {
    if (!Object.hasOwn(hostPackage.dependencies, name)) throw new Error(`Unknown direct Host package: ${name}`);
    const metadata = await metadataFor(name);
    const version = options.version ?? selectHostPackageVersion(name, metadata, nodeVersion, satisfies);
    const entry = metadata.versions?.[version];
    if (!/^\d+\.\d+\.\d+$/.test(version) || !entry?.dist?.integrity || typeof entry.license !== 'string') {
      throw new Error(`Missing stable pin/integrity/license for ${name}@${version}.`);
    }
    if (entry.engines?.node && !satisfies(nodeVersion, entry.engines.node)) {
      throw new Error(`${name}@${version} requires Node ${entry.engines.node}; embedded Node is ${nodeVersion}.`);
    }
    const previous = hostPackage.dependencies[name];
    const major = previous.split('.')[0] !== version.split('.')[0];
    updates.push({ name, previous, version, changed: previous !== version, major,
      review: major ? 'MANUAL_MAJOR' : 'FOCUSED_VALIDATION_REQUIRED', integrity: entry.dist.integrity,
      tarball: entry.dist.tarball, license: entry.license, upstreamCommit: entry.gitHead ?? null,
      nodeEngine: entry.engines?.node ?? null });
  }
  return updates;
}

async function main() {
const args = process.argv.slice(2);
const positional = args.filter(arg => !arg.startsWith('--'));
const known = /^(?:--sync-package-lock|--include-native|--allow-major|--plan|--host-package=.+|--target-version=.+|--report=.+)$/;
for (const arg of args.filter(arg => arg.startsWith('--'))) if (!known.test(arg)) throw new Error(`Unknown updater option: ${arg}`);
const option = name => args.find(arg => arg.startsWith(name + '='))?.slice(name.length + 1);
const lockPath = positional[0] ?? 'RuntimeDependencies.lock.json';
const packagePath = positional[1] ?? 'AI_HLY/Downstream/RuntimeCore/Node/Host/package.json';
const packageLockPath = positional[2] ?? 'AI_HLY/Downstream/RuntimeCore/Node/Host/package-lock.json';
const syncOnly = args.includes('--sync-package-lock');
const planOnly = args.includes('--plan');
const includeNative = args.includes('--include-native');
if (option('--target-version') && !option('--host-package')) throw new Error('--target-version requires one --host-package.');
if (includeNative && option('--host-package')) throw new Error('Native and scoped Host updates must use separate candidates.');
const lock = JSON.parse(await readFile(lockPath, 'utf8'));
const hostPackage = JSON.parse(await readFile(packagePath, 'utf8'));
const originalDependencyHash = runtimeDependencyHash(lock);
const report = { schemaVersion: 1, operation: syncOnly ? 'sync' : planOnly ? 'plan' : 'apply',
  embeddedNode: lock.node.version, includeNative, baselineHash: originalDependencyHash, updates: [] };

if (!syncOnly) {
  const { satisfies } = createRequire(resolve(packagePath))('semver');
  report.updates = await planHostUpdates(hostPackage, lock.node.version, npmMetadata, satisfies,
    { only: option('--host-package'), version: option('--target-version') });
  if (planOnly) {
    if (includeNative) {
      const nodeTag = await latestTag('heylogin/nodejs-mobile', /^v24\.\d+\.\d+-mobile$/);
      const python = await latestRelease('beeware/Python-Apple-support', /^3\.14-b\d+$/);
      const iosSystem = await latestRelease('holzschu/ios_system', /^v\d+\.\d+\.\d+$/);
      report.nativeCandidates = await Promise.all([
        ['heylogin/nodejs-mobile', lock.node.tag, nodeTag],
        ['beeware/Python-Apple-support', lock.python.release, python.tag_name],
        ['holzschu/ios_system', lock.iosSystem.release, iosSystem.tag_name]
      ].map(async ([repository, previous, tag]) => ({repository, previous, tag,
        commit: await tagCommit(repository, tag), changed: previous !== tag, review: 'MANUAL_ABI_SOURCE_PATCH_REVIEW'})));
    }
    if (option('--report')) await writeJSON(option('--report'), report);
    process.stdout.write(JSON.stringify(report) + '\n');
    return;
  }
  if (!args.includes('--allow-major') && report.updates.some(update => update.changed && update.major)) {
    throw new Error('Major Host changes require explicit --allow-major and manual compatibility review.');
  }
  if (includeNative) {
  const nodeTag = await latestTag('heylogin/nodejs-mobile', /^v24\.\d+\.\d+-mobile$/);
  const nodeVersion = nodeTag.replace(/^v/, '').replace(/-mobile$/, '');
  lock.node.tag = nodeTag;
  const nodeCommit = await tagCommit('heylogin/nodejs-mobile', nodeTag);
  if (lock.node.sourcePatches?.length && lock.node.commit !== nodeCommit) {
    throw new Error('Native Node source changed: canonical patch rebase/ABI review is required before applying pins.');
  }
  lock.node.commit = nodeCommit;
  lock.node.version = nodeVersion;
  lock.node.sourceArchive = await downloadable(`https://github.com/heylogin/nodejs-mobile/archive/${nodeCommit}.tar.gz`, false);
  hostPackage.engines.node = nodeVersion;

  const pythonRelease = await latestRelease('beeware/Python-Apple-support', /^3\.14-b\d+$/);
  const pythonAsset = pythonRelease.assets.find(asset => /^Python-3\.14-iOS-support\.b\d+\.tar\.gz$/.test(asset.name));
  if (!pythonAsset) throw new Error(`Release ${pythonRelease.tag_name} has no Python 3.14 iOS support archive.`);
  const pythonVersion = pythonRelease.body?.match(/Python\s+(3\.14\.\d+)/)?.[1];
  if (!pythonVersion) throw new Error(`Release ${pythonRelease.tag_name} does not declare an exact Python 3.14 patch version.`);
  lock.python.release = pythonRelease.tag_name;
  lock.python.commit = await tagCommit('beeware/Python-Apple-support', pythonRelease.tag_name);
  lock.python.version = pythonVersion;
  lock.python.archive = await downloadable(pythonAsset.browser_download_url);

  const iosRelease = await latestRelease('holzschu/ios_system', /^v\d+\.\d+\.\d+$/);
  lock.iosSystem.release = iosRelease.tag_name;
  lock.iosSystem.commit = await tagCommit('holzschu/ios_system', iosRelease.tag_name);
  for (const component of lock.iosSystem.components) {
    const asset = iosRelease.assets.find(candidate => candidate.name === `${component.name}.xcframework.zip`);
    if (!asset) throw new Error(`Release ${iosRelease.tag_name} is missing ${component.name}.xcframework.zip.`);
    Object.assign(component, await downloadable(asset.browser_download_url));
  }
  }
  for (const update of report.updates) hostPackage.dependencies[update.name] = update.version;
  await writeJSON(packagePath, hostPackage);
} else {
  const npmLock = JSON.parse(await readFile(packageLockPath, 'utf8'));
  for (const name of Object.keys(lock.nodeHostPackages)) {
    const resolved = npmLock.packages?.[`node_modules/${name}`];
    if (!resolved?.version || !resolved?.integrity) throw new Error(`package-lock is missing ${name}.`);
    if (resolved.version !== hostPackage.dependencies[name] || npmLock.packages?.['']?.dependencies?.[name] !== hostPackage.dependencies[name]) {
      throw new Error(`Manifest/package-lock drift for ${name}; regenerate the exact lock first.`);
    }
    lock.nodeHostPackages[name].version = resolved.version;
    lock.nodeHostPackages[name].integrity = resolved.integrity;
    if (resolved.license) lock.nodeHostPackages[name].license = resolved.license;
  }
  const typescript = npmLock.packages?.['node_modules/typescript'];
  if (!typescript?.version || !typescript?.integrity) throw new Error('package-lock is missing TypeScript.');
  lock.typescript.version = typescript.version;
  lock.typescript.integrity = typescript.integrity;
}

// The canonical native identity explicitly excludes Host JS/TypeScript packages.
// Host-only updates rebuild/verify their own archive; they do not falsify an
// unchanged, separately authenticated Node/CPython binary's provenance.
if (includeNative && runtimeDependencyHash(lock) !== originalDependencyHash) {
  lock.runtimeBundle.verificationStatus = 'pending-runtime-build';
  lock.node.verificationStatus = 'pending-runtime-build';
}

await writeJSON(lockPath, lock);
report.candidateHash = runtimeDependencyHash(lock);
if (option('--report')) await writeJSON(option('--report'), report);
process.stdout.write(JSON.stringify(report) + '\n');
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) await main();

async function latestTag(repository, pattern) {
  const tags = await github(`/repos/${repository}/tags?per_page=100`);
  const candidates = tags.map(item => item.name).filter(name => pattern.test(name)).sort(compareVersions);
  if (!candidates.length) throw new Error(`No supported tag found for ${repository}.`);
  return candidates.at(-1);
}

async function latestRelease(repository, pattern) {
  const releases = await github(`/repos/${repository}/releases?per_page=100`);
  const candidates = releases.filter(item => !item.draft && !item.prerelease && pattern.test(item.tag_name));
  candidates.sort((left, right) => compareVersions(left.tag_name, right.tag_name));
  if (!candidates.length) throw new Error(`No supported stable release found for ${repository}.`);
  return candidates.at(-1);
}

async function tagCommit(repository, tag) {
  let object = (await github(`/repos/${repository}/git/ref/tags/${encodeURIComponent(tag)}`)).object;
  if (object.type === 'tag') object = await github(`/repos/${repository}/git/tags/${object.sha}`);
  if (object.object) object = object.object;
  if (object.type !== 'commit' || !/^[a-f0-9]{40}$/.test(object.sha)) throw new Error(`Could not resolve ${repository}@${tag} to a commit.`);
  return object.sha;
}

async function downloadable(url, includeSize = true) {
  // Upstream public asset downloads never receive the repository token.
  const response = await fetch(url, { redirect: 'follow' });
  if (!response.ok) throw new Error(`Download failed (${response.status}): ${url}`);
  const bytes = Buffer.from(await response.arrayBuffer());
  const result = { url, sha256: createHash('sha256').update(bytes).digest('hex') };
  if (includeSize) result.size = bytes.length;
  return result;
}

async function npmMetadata(name) {
  const response = await fetch(`https://registry.npmjs.org/${name.replace('/', '%2f')}`);
  if (!response.ok) throw new Error(`npm metadata failed for ${name}: ${response.status}`);
  return response.json();
}

async function github(path) {
  const headers = { Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28' };
  if (token) headers.Authorization = `Bearer ${token}`;
  const response = await fetch(`https://api.github.com${path}`, { headers });
  if (!response.ok) throw new Error(`GitHub API failed (${response.status}): ${path}`);
  return response.json();
}

function compareVersions(left, right) {
  const numbers = value => value.match(/\d+/g)?.map(Number) ?? [];
  const a = numbers(left), b = numbers(right);
  for (let index = 0; index < Math.max(a.length, b.length); index += 1) {
    const difference = (a[index] ?? 0) - (b[index] ?? 0);
    if (difference) return difference;
  }
  return left.localeCompare(right);
}

async function writeJSON(path, value) {
  await writeFile(path, `${JSON.stringify(value, null, 2)}\n`);
}
