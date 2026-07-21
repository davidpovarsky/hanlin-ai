#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import process from 'node:process';

const lockPath = process.argv[2] ?? 'RuntimeDependencies.lock.json';
const packagePath = process.argv[3] ?? 'AI_HLY/Downstream/RuntimeCore/Node/Host/package.json';
const packageLockPath = process.argv[4] ?? 'AI_HLY/Downstream/RuntimeCore/Node/Host/package-lock.json';
const syncOnly = process.argv.includes('--sync-package-lock');
const token = process.env.GITHUB_TOKEN ?? process.env.GH_TOKEN;
const lock = JSON.parse(await readFile(lockPath, 'utf8'));
const hostPackage = JSON.parse(await readFile(packagePath, 'utf8'));
const originalDependencyHash = dependencyHash(lock);

if (!syncOnly) {
  const nodeTag = await latestTag('heylogin/nodejs-mobile', /^v24\.\d+\.\d+-mobile$/);
  const nodeVersion = nodeTag.replace(/^v/, '').replace(/-mobile$/, '');
  const nodeArchiveURL = `https://github.com/heylogin/nodejs-mobile/archive/refs/tags/${nodeTag}.tar.gz`;
  lock.node.tag = nodeTag;
  lock.node.commit = await tagCommit('heylogin/nodejs-mobile', nodeTag);
  lock.node.version = nodeVersion;
  lock.node.sourceArchive = await downloadable(nodeArchiveURL, false);
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

  for (const name of Object.keys(hostPackage.dependencies)) {
    const metadata = await npmMetadata(name);
    const version = metadata['dist-tags']?.latest;
    if (!version || !metadata.versions?.[version]) throw new Error(`npm did not return an exact latest version for ${name}.`);
    hostPackage.dependencies[name] = version;
  }
  await writeJSON(packagePath, hostPackage);
} else {
  const npmLock = JSON.parse(await readFile(packageLockPath, 'utf8'));
  for (const name of Object.keys(lock.nodeHostPackages)) {
    const resolved = npmLock.packages?.[`node_modules/${name}`];
    if (!resolved?.version || !resolved?.integrity) throw new Error(`package-lock is missing ${name}.`);
    lock.nodeHostPackages[name].version = resolved.version;
    lock.nodeHostPackages[name].integrity = resolved.integrity;
    if (resolved.license) lock.nodeHostPackages[name].license = resolved.license;
  }
  const typescript = npmLock.packages?.['node_modules/typescript'];
  if (!typescript?.version || !typescript?.integrity) throw new Error('package-lock is missing TypeScript.');
  lock.typescript.version = typescript.version;
  lock.typescript.integrity = typescript.integrity;
}

if (dependencyHash(lock) !== originalDependencyHash) {
  lock.runtimeBundle.verificationStatus = 'pending-runtime-build';
  lock.node.verificationStatus = 'pending-runtime-build';
}

await writeJSON(lockPath, lock);

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
  const response = await fetch(url, { headers: token ? { Authorization: `Bearer ${token}` } : {}, redirect: 'follow' });
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

function dependencyHash(value) {
  const copy = structuredClone(value);
  delete copy.runtimeBundle.sha256;
  delete copy.runtimeBundle.verificationStatus;
  delete copy.node.xcframeworkSha256;
  delete copy.node.verificationStatus;
  return createHash('sha256').update(JSON.stringify(copy)).digest('hex');
}

async function writeJSON(path, value) {
  await writeFile(path, `${JSON.stringify(value, null, 2)}\n`);
}
