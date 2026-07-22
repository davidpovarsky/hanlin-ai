import { promises as fs } from 'node:fs';
import path from 'node:path';
import Arborist from '@npmcli/arborist';
import pacote from 'pacote';
import semver from 'semver';
import ssri from 'ssri';
import {
  analyzePackage,
  determineModuleKind,
  inspectManifest,
  listEntryPoints,
  resolveEntryPoint,
} from './package-compatibility.mjs';
import { runMCPRuntimeProbe } from './runtime-probe.mjs';

const NODE_VERSION = '24.5.0';

export async function previewPackage(source, options = {}) {
  const cachePath = path.join(options.root, 'cache', 'npm');
  const resolved = await resolveSource(source, { ...options, cache: cachePath });
  const manifest = resolved.manifest;
  const entryPoints = listEntryPoints(manifest);
  const findings = inspectManifest(manifest);
  if (entryPoints.length === 0) findings.push({ severity: 'unsupported', message: 'No unambiguous entry point was found.' });
  const compatibility = {
    verdict: findings.some(item => item.severity === 'unsupported') ? 'unsupported' : 'compatibleWithWarnings',
    findings: findings.length ? findings : [{ severity: 'warning', message: 'Manifest preview passed; package scan and runtime probe remain.' }],
    runtimeProbePassed: false,
  };
  return {
    packageName: manifest.name,
    version: manifest.version,
    summary: manifest.description ?? null,
    nodeRequirement: manifest.engines?.node ?? null,
    entryPoints,
    dependencyCount: Object.keys(manifest.dependencies ?? {}).length,
    compatibility,
  };
}

export async function installPackage({
  root,
  operationID,
  serverID,
  source,
  entryPointOverride,
  arguments: serverArguments = [],
  signal,
  emit,
}) {
  validateID(operationID);
  validateID(serverID);
  const stagingRoot = path.join(root, 'staging');
  const serversRoot = path.join(root, 'packages', 'mcp');
  const operationRoot = path.join(stagingRoot, operationID);
  const packageRoot = path.join(operationRoot, 'package');
  const finalRoot = path.join(serversRoot, serverID);
  const backupRoot = path.join(stagingRoot, `backup-${operationID}`);
  const cachePath = path.join(root, 'cache', 'npm');
  await fs.mkdir(stagingRoot, { recursive: true });
  await fs.mkdir(serversRoot, { recursive: true });
  await fs.rm(operationRoot, { recursive: true, force: true });
  await fs.rm(backupRoot, { recursive: true, force: true });
  await fs.mkdir(packageRoot, { recursive: true });

  try {
    checkCancelled(signal);
    emit('install', { operationID, phase: 'resolving', fraction: 0.05 });
    const resolved = await resolveSource(source, { signal, cache: cachePath });
    const manifest = resolved.manifest;
    const manifestFindings = inspectManifest(manifest);
    rejectUnsupported(manifestFindings);

    emit('install', { operationID, phase: 'downloading', fraction: 0.2 });
    await pacote.extract(resolved.spec, packageRoot, {
      integrity: resolved.integrity,
      cache: cachePath,
      signal,
    });

    checkCancelled(signal);
    emit('install', { operationID, phase: 'verifying', fraction: 0.35 });
    if (resolved.integrity) {
      const parsed = ssri.parse(resolved.integrity);
      if (!parsed || parsed.toString() !== resolved.integrity) throw new Error('Package integrity metadata is invalid.');
    }

    emit('install', { operationID, phase: 'extracting', fraction: 0.45 });
    const extractedManifest = JSON.parse(await fs.readFile(path.join(packageRoot, 'package.json'), 'utf8'));
    rejectUnsupported(inspectManifest(extractedManifest));

    emit('install', { operationID, phase: 'installingDependencies', fraction: 0.58 });
    const arborist = new Arborist({
      path: packageRoot,
      cache: cachePath,
      ignoreScripts: true,
      audit: false,
      fund: false,
    });
    await arborist.reify({ omit: ['dev', 'optional'], ignoreScripts: true, signal });

    checkCancelled(signal);
    const selected = resolveEntryPoint(extractedManifest, entryPointOverride);
    const absoluteEntry = path.resolve(packageRoot, selected.entryPoint);
    if (!isInside(packageRoot, absoluteEntry)) throw new Error('Entry point escapes the package directory.');
    await fs.access(absoluteEntry);
    const moduleKind = determineModuleKind(absoluteEntry, extractedManifest);
    const validatedServerArguments = validateArguments(serverArguments);

    emit('install', { operationID, phase: 'checkingCompatibility', fraction: 0.75 });
    const compatibility = await analyzePackage(packageRoot, extractedManifest, {
      entryPoint: absoluteEntry,
      moduleKind,
      runtimeProbe: () => runMCPRuntimeProbe({
        packageRoot,
        entryPoint: absoluteEntry,
        moduleKind,
        arguments: validatedServerArguments,
        workspace: path.join(operationRoot, 'probe-workspace'),
        timeoutMilliseconds: 30_000,
        maximumOutputBytes: 1_048_576,
      }),
    });
    rejectUnsupported(compatibility.findings);

    const now = new Date().toISOString();
    const installedSize = await directorySize(operationRoot);
    const entryPointOptions = listEntryPoints(extractedManifest).flatMap(entryPoint => {
      const absoluteOption = path.resolve(packageRoot, entryPoint);
      if (!isInside(packageRoot, absoluteOption)) return [];
      const matchingBin = typeof extractedManifest.bin === 'object'
        ? Object.entries(extractedManifest.bin).find(([, candidate]) => candidate === entryPoint)
        : null;
      const binName = matchingBin?.[0]
        ?? (typeof extractedManifest.bin === 'string' && extractedManifest.bin === entryPoint ? extractedManifest.name : null);
      return [{
        binName,
        entryPoint: absoluteOption.replace(operationRoot, finalRoot),
      }];
    });
    const descriptor = {
      id: serverID,
      slug: slug(extractedManifest.name),
      displayName: extractedManifest.name,
      packageName: extractedManifest.name,
      requestedVersion: source.version ?? null,
      resolvedVersion: extractedManifest.version,
      entryPoint: absoluteEntry.replace(operationRoot, finalRoot),
      binName: selected.binName,
      entryPointOptions,
      arguments: validatedServerArguments,
      environment: [],
      packageRoot: packageRoot.replace(operationRoot, finalRoot),
      integrity: resolved.integrity ?? null,
      installedAt: now,
      updatedAt: now,
      isGloballyEnabled: true,
      isEnabledForNewChats: true,
      autoStart: false,
      compatibility,
      installedSize,
      cachedToolCount: 0,
    };
    const installManifest = {
      packageName: descriptor.packageName,
      requestedVersion: descriptor.requestedVersion,
      resolvedVersion: descriptor.resolvedVersion,
      integrity: descriptor.integrity,
      entryPoint: descriptor.entryPoint,
      binName: descriptor.binName,
      installedAt: now,
      dependencyCount: Object.keys(extractedManifest.dependencies ?? {}).length,
    };
    await fs.writeFile(path.join(operationRoot, 'install-manifest.json'), JSON.stringify(installManifest, null, 2));
    await fs.writeFile(path.join(operationRoot, 'compatibility-report.json'), JSON.stringify(compatibility, null, 2));
    await fs.mkdir(path.join(operationRoot, 'logs'), { recursive: true });

    emit('install', { operationID, phase: 'registering', fraction: 0.9 });
    try { await fs.access(finalRoot); await fs.rename(finalRoot, backupRoot); } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
    await fs.rename(operationRoot, finalRoot);
    return descriptor;
  } catch (error) {
    await fs.rm(operationRoot, { recursive: true, force: true });
    try {
      await fs.access(backupRoot);
      try {
        await fs.access(finalRoot);
      } catch (finalError) {
        if (finalError.code !== 'ENOENT') throw finalError;
        await fs.rename(backupRoot, finalRoot);
      }
    } catch (restoreError) {
      if (restoreError.code !== 'ENOENT') throw new AggregateError([error, restoreError], 'Install failed and the prior package could not be restored.');
    }
    throw error;
  }
}

export async function commitInstall({ root, operationID, serverID }) {
  validateID(operationID);
  validateID(serverID);
  await fs.rm(path.join(root, 'staging', `backup-${operationID}`), { recursive: true, force: true });
}

export async function rollbackInstall({ root, operationID, serverID }) {
  validateID(operationID);
  validateID(serverID);
  const finalRoot = path.join(root, 'packages', 'mcp', serverID);
  const backupRoot = path.join(root, 'staging', `backup-${operationID}`);
  await fs.rm(finalRoot, { recursive: true, force: true });
  try {
    await fs.rename(backupRoot, finalRoot);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
}

export function verifyIntegrity(data, integrity) {
  if (!ssri.checkData(data, integrity)) throw new Error('Integrity mismatch.');
}

export function checkCancelled(signal) {
  if (signal?.aborted) throw signal.reason ?? new Error('Installation cancelled.');
}

async function resolveSource(source, options) {
  if (!source || !['npm', 'url', 'file'].includes(source.kind)) throw new Error('Unsupported package source.');
  if (source.kind === 'npm') {
    const packument = await pacote.packument(source.name, { cache: options.cache, signal: options.signal });
    let version;
    if (source.version) {
      version = packument['dist-tags']?.[source.version] ?? source.version;
      const candidate = packument.versions?.[version];
      if (!candidate) throw new Error(`Version '${source.version}' was not found.`);
      if (candidate.engines?.node && !semver.satisfies(NODE_VERSION, candidate.engines.node)) {
        throw new Error(`Requested version requires Node ${candidate.engines.node}; embedded runtime is ${NODE_VERSION}.`);
      }
    } else {
      version = Object.keys(packument.versions ?? {})
        .filter(value => semver.valid(value))
        .filter(value => {
          const requirement = packument.versions[value].engines?.node;
          return !requirement || semver.satisfies(NODE_VERSION, requirement);
        })
        .sort(semver.rcompare)[0];
      if (!version) throw new Error(`No version of ${source.name} supports Node ${NODE_VERSION}.`);
    }
    const manifest = packument.versions[version];
    return { manifest, spec: `${source.name}@${version}`, integrity: manifest.dist?.integrity };
  }
  const spec = source.kind === 'url' ? source.url : source.path;
  if (source.kind === 'url') {
    const url = new URL(spec);
    if (!['https:', 'http:'].includes(url.protocol) || !url.pathname.endsWith('.tgz')) throw new Error('Archive URL must be HTTP(S) and end in .tgz.');
  } else {
    await fs.access(spec);
  }
  const manifest = await pacote.manifest(spec, { cache: options.cache, signal: options.signal });
  return { manifest, spec, integrity: manifest._integrity ?? manifest.dist?.integrity };
}

function rejectUnsupported(findings) {
  const reasons = findings.filter(item => item.severity === 'unsupported').map(item => item.message);
  if (reasons.length) {
    const error = new Error(`Unsupported package: ${reasons.join('; ')}`);
    error.name = 'PackageCompatibilityError';
    error.code = findings.find(item => item.severity === 'unsupported')?.code ?? 'unsupported_package';
    error.findings = findings.filter(item => item.severity === 'unsupported');
    throw error;
  }
}

function validateID(value) {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) {
    throw new Error('Invalid UUID.');
  }
}

function isInside(root, candidate) {
  const relative = path.relative(path.resolve(root), path.resolve(candidate));
  return relative !== '..' && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative);
}

function slug(value) {
  const result = value.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
  return /^[a-z]/.test(result) ? result : `server_${result || 'mcp'}`;
}

function validateArguments(value) {
  if (!Array.isArray(value) || value.length > 128) throw new Error('Invalid server arguments.');
  return value.map(item => {
    const argument = String(item);
    if (/\0|\r|\n/.test(argument)) throw new Error('Invalid server argument.');
    return argument;
  });
}

async function directorySize(root) {
  let total = 0;
  const stack = [root];
  while (stack.length) {
    const current = stack.pop();
    for (const entry of await fs.readdir(current, { withFileTypes: true })) {
      const absolute = path.join(current, entry.name);
      if (entry.isDirectory()) stack.push(absolute);
      else if (entry.isFile()) total += (await fs.stat(absolute)).size;
    }
  }
  return total;
}
