import { promises as fs } from 'node:fs';
import path from 'node:path';
import Arborist from '@npmcli/arborist';
import pacote from 'pacote';
import semver from 'semver';
import { analyzePackage, inspectManifest } from './package-compatibility.mjs';
import { planLifecycle } from './lifecycle-planner.mjs';

const NODE_VERSION = '24.5.0';

export async function previewGlobalPackage({ root, name, version }) {
  const resolved = await resolve(name, version, path.join(root, 'cache', 'npm'));
  const findings = inspectManifest(resolved.manifest, NODE_VERSION);
  return details(resolved, findings, null);
}

export async function listGlobalPackages({ root }) {
  const manifest = await readRootManifest(root);
  const lock = await readGlobalLock(root);
  return Promise.all(Object.entries(manifest.dependencies ?? {}).map(async ([name, version]) => {
    const packageRoot = path.join(globalRoot(root), 'node_modules', ...name.split('/'));
    const installed = JSON.parse(await fs.readFile(path.join(packageRoot, 'package.json'), 'utf8'));
    const lockKey = `node_modules/${name}`;
    return {
      name, version: installed.version, requestedVersion: version, summary: installed.description ?? null,
      nodeRequirement: installed.engines?.node ?? null, packageRoot, size: await directorySize(packageRoot),
      dependencies: Object.keys(installed.dependencies ?? {}), integrity: lock.packages?.[lockKey]?.integrity ?? null,
      findings: inspectManifest(installed, NODE_VERSION), lifecycle: planLifecycle(installed, lock.packages?.[lockKey]?.integrity ?? null),
    };
  }));
}

export async function stageGlobalPackage({ root, name, version }) {
  const cache = path.join(root, 'cache', 'npm');
  const resolved = await resolve(name, version, cache);
  const operation = `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  const staging = transactionRoot(root, operation);
  await fs.rm(staging, { recursive: true, force: true });
  await fs.mkdir(staging, { recursive: true });
  const current = await readRootManifest(root);
  const next = { name: 'hanlin-global-packages', private: true, version: '1.0.0', dependencies: { ...(current.dependencies ?? {}), [resolved.manifest.name]: resolved.manifest.version } };
  await fs.writeFile(path.join(staging, 'package.json'), JSON.stringify(next, null, 2));
  const arborist = new Arborist({ path: staging, cache, ignoreScripts: true, audit: false, fund: false });
  await arborist.reify({ omit: ['dev', 'optional'], ignoreScripts: true });
  const packageRoot = path.join(staging, 'node_modules', ...resolved.manifest.name.split('/'));
  const compatibility = await analyzePackage(packageRoot, resolved.manifest, { maximumFiles: 50_000 });
  const lifecycle = planLifecycle(resolved.manifest, resolved.integrity);
  if (compatibility.verdict === 'unsupported') throw new Error(compatibility.findings.filter(item => item.severity === 'unsupported').map(item => item.message).join('; '));
  return {
    transactionID: operation,
    packageRoot,
    package: details(resolved, compatibility.findings, lifecycle, packageRoot),
  };
}

export async function commitGlobalPackage({ root, transactionID }) {
  const staging = transactionRoot(root, transactionID);
  const destination = globalRoot(root);
  const backup = path.join(root, 'staging', `node-global-backup-${transactionID}`);
  await fs.access(path.join(staging, 'package.json'));
  await fs.rm(backup, { recursive: true, force: true });
  try { await fs.rename(destination, backup); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  try {
    await fs.rename(staging, destination);
    await fs.rm(backup, { recursive: true, force: true });
  } catch (error) {
    await fs.rm(destination, { recursive: true, force: true });
    try { await fs.rename(backup, destination); } catch {}
    throw error;
  }
  return { committed: true };
}

export async function rollbackGlobalPackage({ root, transactionID }) {
  await fs.rm(transactionRoot(root, transactionID), { recursive: true, force: true });
  return { rolledBack: true };
}

export async function installGlobalPackage({ root, name, version }) {
  const transaction = await stageGlobalPackage({ root, name, version });
  if (transaction.package.lifecycle?.requiresApproval || transaction.package.lifecycle?.rejected?.length) {
    await rollbackGlobalPackage({ root, transactionID: transaction.transactionID });
    throw new Error('This package declares lifecycle actions and must be installed through the approval broker.');
  }
  await commitGlobalPackage({ root, transactionID: transaction.transactionID });
  return (await listGlobalPackages({ root })).find(item => item.name === transaction.package.name) ?? transaction.package;
}

export async function uninstallGlobalPackage({ root, name }) {
  const current = await readRootManifest(root);
  const dependencies = { ...(current.dependencies ?? {}) };
  delete dependencies[name];
  const operation = `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  const staging = path.join(root, 'staging', `node-global-${operation}`);
  const destination = globalRoot(root);
  const backup = path.join(root, 'staging', `node-global-backup-${operation}`);
  await fs.mkdir(staging, { recursive: true });
  await fs.writeFile(path.join(staging, 'package.json'), JSON.stringify({ name: 'hanlin-global-packages', private: true, version: '1.0.0', dependencies }, null, 2));
  const arborist = new Arborist({ path: staging, cache: path.join(root, 'cache', 'npm'), ignoreScripts: true, audit: false, fund: false });
  await arborist.reify({ omit: ['dev', 'optional'], ignoreScripts: true });
  try { await fs.rename(destination, backup); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  try { await fs.rename(staging, destination); await fs.rm(backup, { recursive: true, force: true }); }
  catch (error) { try { await fs.rename(backup, destination); } catch {} throw error; }
  return { removed: name };
}

async function resolve(name, requested, cache) {
  if (!/^(@[a-z0-9._-]+\/)?[a-z0-9][a-z0-9._-]*$/i.test(name)) throw new Error('Invalid npm package name.');
  const packument = await pacote.packument(name, { cache });
  let version = requested ? (packument['dist-tags']?.[requested] ?? requested) : packument['dist-tags']?.latest;
  if (!packument.versions?.[version]) throw new Error(`Version '${requested}' was not found.`);
  const requirement = packument.versions[version].engines?.node;
  if (requirement && !semver.satisfies(NODE_VERSION, requirement)) throw new Error(`Requires Node ${requirement}; embedded runtime is ${NODE_VERSION}.`);
  const manifest = packument.versions[version];
  return { manifest, integrity: manifest.dist?.integrity ?? null };
}

async function readRootManifest(root) {
  try { return JSON.parse(await fs.readFile(path.join(globalRoot(root), 'package.json'), 'utf8')); }
  catch (error) { if (error.code === 'ENOENT') return { dependencies: {} }; throw error; }
}
async function readGlobalLock(root) {
  try { return JSON.parse(await fs.readFile(path.join(globalRoot(root), 'package-lock.json'), 'utf8')); }
  catch (error) { if (error.code === 'ENOENT') return { packages: {} }; throw error; }
}
function globalRoot(root) { return path.join(root, 'packages', 'node-global'); }
function transactionRoot(root, transactionID) {
  if (!/^[a-z0-9-]{8,80}$/i.test(transactionID)) throw new Error('Invalid global package transaction ID.');
  return path.join(root, 'clients', 'tools', `npm-lifecycle-${transactionID}`);
}
function details(resolved, findings, lifecycle, packageRoot = null) { return { name: resolved.manifest.name, version: resolved.manifest.version, summary: resolved.manifest.description ?? null, nodeRequirement: resolved.manifest.engines?.node ?? null, dependencies: Object.keys(resolved.manifest.dependencies ?? {}), integrity: resolved.integrity, findings, lifecycle, packageRoot }; }
async function directorySize(root) { let total = 0; const stack = [root]; while (stack.length) { const current = stack.pop(); for (const entry of await fs.readdir(current, { withFileTypes: true })) { const absolute = path.join(current, entry.name); if (entry.isDirectory()) stack.push(absolute); else if (entry.isFile()) total += (await fs.stat(absolute)).size; } } return total; }
