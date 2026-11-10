import { promises as fs } from 'node:fs';
import path from 'node:path';
import Arborist from '@npmcli/arborist';
import pacote from 'pacote';
import semver from 'semver';
import { inspectArchiveSafety, inspectManifest, mergeCompatibilityReports } from './package-compatibility.mjs';
import { planLifecycle, planLifecycleTree, verifyLifecyclePlan } from './lifecycle-planner.mjs';
import { currentGlobalState, prepareGlobalTransaction, saveGlobalTransaction, loadGlobalTransaction,
  transactionRoot, publishGlobalTransaction, discardGlobalTransaction } from './global-package-state.mjs';

const NODE_VERSION = '24.5.0';

export async function previewGlobalPackage({ root, name, version, registry }) {
  const resolved = await resolve(name, version, path.join(root, 'cache', 'npm'),registry);
  const findings = inspectManifest(resolved.manifest, NODE_VERSION);
  return details(resolved, findings, null);
}

export async function listGlobalPackages({ root }) {
  const directory=(await currentGlobalState(root)).directory;
  const manifest = await readManifest(directory);
  const lock = await readLock(directory);
  return Promise.all(Object.entries(manifest.dependencies ?? {}).map(async ([name, version]) => {
    const packageRoot = path.join(directory, 'node_modules', ...name.split('/'));
    const installed = JSON.parse(await fs.readFile(path.join(packageRoot, 'package.json'), 'utf8'));
    const lockKey = `node_modules/${name}`;
    return {
      name, version: installed.version, requestedVersion: version, summary: installed.description ?? null,
      nodeRequirement: installed.engines?.node ?? null, packageRoot, size: await directorySize(packageRoot),
      dependencies: Object.keys(installed.dependencies ?? {}), integrity: lock.packages?.[lockKey]?.integrity ?? null,
      findings: inspectManifest(installed, NODE_VERSION), lifecycle: planLifecycle(installed, lock.packages?.[lockKey]?.integrity ?? null,{context:'registry'}),
    };
  }));
}

export async function stageGlobalPackage({ root, name, version, registry }) {
  const cache = path.join(root, 'cache', 'npm');
  const resolved = await resolve(name, version, cache,registry);
  const transaction=await prepareGlobalTransaction(root);
  const staging=transaction.directory;
  try {
  const current = await readManifest(staging);
  const previousPackages=(await readLock(staging)).packages??{};
  const next = { name: 'hanlin-global-packages', private: true, version: '1.0.0', dependencies: { ...(current.dependencies ?? {}), [resolved.manifest.name]: resolved.manifest.version } };
  await fs.writeFile(path.join(staging, 'package.json'), JSON.stringify(next, null, 2));
  const arborist = new Arborist({ path: staging, cache, registry, ignoreScripts: true, audit: false, fund: false });
  const tree=await arborist.reify({ omit: ['dev'], ignoreScripts: true });
  const packageRoot = path.join(staging, 'node_modules', ...resolved.manifest.name.split('/'));
  const archive = await inspectArchiveSafety(packageRoot, { maximumFiles: 50_000 });
  const compatibility = mergeCompatibilityReports({
    manifestFindings: inspectManifest(resolved.manifest, NODE_VERSION),
    archive,
  });
  const lifecycle = await planLifecycleTree(tree,{identity:{...resolved.manifest,integrity:resolved.integrity},previousPackages});
  if (compatibility.verdict === 'unsupported') throw new Error(compatibility.findings.filter(item => item.severity === 'unsupported').map(item => item.message).join('; '));
  await saveGlobalTransaction(root,{...transaction,plan:lifecycle,selectedPackage:resolved.manifest.name});
  return {
    transactionID: transaction.transactionID,
    packageRoot:staging,
    package: details(resolved, compatibility.findings, lifecycle, packageRoot),
  };
  } catch(error) {await discardGlobalTransaction(root,transaction.transactionID);throw error;}
}

export async function commitGlobalPackage({ root, transactionID }) {
  const transaction=await loadGlobalTransaction(root,transactionID);
  await verifyLifecyclePlan(transactionRoot(root,transactionID),transaction.plan);
  return publishGlobalTransaction(root,transactionID);
}

export async function rollbackGlobalPackage({ root, transactionID }) {
  return discardGlobalTransaction(root,transactionID);
}

export async function installGlobalPackage({ root, name, version }) {
  const transaction = await stageGlobalPackage({ root, name, version });
  if (transaction.package.lifecycle?.actions?.length || transaction.package.lifecycle?.rejected?.length) {
    await rollbackGlobalPackage({ root, transactionID: transaction.transactionID });
    throw new Error('This package requires the native lifecycle executor; use staged installation.');
  }
  await commitGlobalPackage({ root, transactionID: transaction.transactionID });
  return (await listGlobalPackages({ root })).find(item => item.name === transaction.package.name) ?? transaction.package;
}

export async function stageUninstallGlobalPackage({ root, name }) {
  const transaction=await prepareGlobalTransaction(root);
  const staging=transaction.directory;
  try {
  const current = await readManifest(staging);
  const previousPackages=(await readLock(staging)).packages??{};
  const dependencies = { ...(current.dependencies ?? {}) };
  delete dependencies[name];
  await fs.writeFile(path.join(staging, 'package.json'), JSON.stringify({ name: 'hanlin-global-packages', private: true, version: '1.0.0', dependencies }, null, 2));
  const arborist = new Arborist({ path: staging, cache: path.join(root, 'cache', 'npm'), ignoreScripts: true, audit: false, fund: false });
  const tree=await arborist.reify({ omit: ['dev'], ignoreScripts: true });
  const lifecycle=await planLifecycleTree(tree,{identity:{name:'hanlin-global-packages',version:'1.0.0'},previousPackages});
  await saveGlobalTransaction(root,{...transaction,plan:lifecycle});
  return {transactionID:transaction.transactionID,packageRoot:staging,lifecycle};
  }catch(error){await discardGlobalTransaction(root,transaction.transactionID);throw error;}
}

export async function uninstallGlobalPackage({root,name}) {
  const transaction=await stageUninstallGlobalPackage({root,name});
  if(transaction.lifecycle.actions.length||!transaction.lifecycle.executable){
    await rollbackGlobalPackage({root,transactionID:transaction.transactionID});
    throw new Error('Updated dependencies require the native lifecycle executor; use staged removal.');
  }
  await commitGlobalPackage({root,transactionID:transaction.transactionID});
  return {removed:name};
}

async function resolve(name, requested, cache,registry) {
  if (!/^(@[a-z0-9._-]+\/)?[a-z0-9][a-z0-9._-]*$/i.test(name)) throw new Error('Invalid npm package name.');
  const packument = await pacote.packument(name, { cache,registry });
  let version = requested ? (packument['dist-tags']?.[requested] ?? requested) : packument['dist-tags']?.latest;
  if (!packument.versions?.[version] && semver.validRange(version)) version=semver.maxSatisfying(Object.keys(packument.versions??{}),version);
  if (!packument.versions?.[version]) throw new Error(`Version '${requested}' was not found.`);
  const requirement = packument.versions[version].engines?.node;
  if (requirement && !semver.satisfies(NODE_VERSION, requirement)) throw new Error(`Requires Node ${requirement}; embedded runtime is ${NODE_VERSION}.`);
  const manifest = packument.versions[version];
  return { manifest, integrity: manifest.dist?.integrity ?? null };
}

async function readManifest(directory) {
  try { return JSON.parse(await fs.readFile(path.join(directory, 'package.json'), 'utf8')); }
  catch (error) { if (error.code === 'ENOENT') return { dependencies: {} }; throw error; }
}
async function readLock(directory) {
  try { return JSON.parse(await fs.readFile(path.join(directory, 'package-lock.json'), 'utf8')); }
  catch (error) { if (error.code === 'ENOENT') return { packages: {} }; throw error; }
}
function details(resolved, findings, lifecycle, packageRoot = null) { return { name: resolved.manifest.name, version: resolved.manifest.version, summary: resolved.manifest.description ?? null, nodeRequirement: resolved.manifest.engines?.node ?? null, dependencies: Object.keys(resolved.manifest.dependencies ?? {}), integrity: resolved.integrity, findings, lifecycle, packageRoot }; }
async function directorySize(root) { let total = 0; const stack = [root]; while (stack.length) { const current = stack.pop(); for (const entry of await fs.readdir(current, { withFileTypes: true })) { const absolute = path.join(current, entry.name); if (entry.isDirectory()) stack.push(absolute); else if (entry.isFile()) total += (await fs.stat(absolute)).size; } } return total; }
