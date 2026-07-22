import { promises as fs } from 'node:fs';
import path from 'node:path';
import semver from 'semver';

const lifecycleNames = ['preinstall', 'install', 'postinstall', 'prepare', 'prepublish'];
const sourceExtensions = new Set(['.js', '.cjs', '.mjs', '.ts', '.cts', '.mts']);

export function inspectManifest(manifest, nodeVersion = '24.5.0') {
  const findings = [];
  const requirement = manifest.engines?.node;
  if (requirement && !semver.satisfies(nodeVersion, requirement, { includePrerelease: true })) {
    findings.push(unsupported(
      `Requires Node ${requirement}; embedded runtime is ${nodeVersion}.`,
      { code: 'manifest_node_engine', phase: 'manifest' },
    ));
  }
  if (Array.isArray(manifest.os) && manifest.os.length > 0 && !allows(manifest.os, 'darwin')) {
    findings.push(unsupported(
      `Package OS constraint does not allow darwin: ${manifest.os.join(', ')}`,
      { code: 'manifest_os', phase: 'manifest' },
    ));
  }
  if (Array.isArray(manifest.cpu) && manifest.cpu.length > 0 && !allows(manifest.cpu, 'arm64')) {
    findings.push(unsupported(
      `Package CPU constraint does not allow arm64: ${manifest.cpu.join(', ')}`,
      { code: 'manifest_cpu', phase: 'manifest' },
    ));
  }
  for (const name of lifecycleNames) {
    if (manifest.scripts?.[name]) {
      findings.push(warning(
        `Lifecycle script '${name}' is installed with scripts disabled and would require an approved structured execution plan if its output were needed.`,
        { code: 'lifecycle_approval_required', phase: 'manifest', specifier: name },
      ));
    }
  }
  return findings;
}

export async function inspectArchiveSafety(packageRoot, options = {}) {
  const requestedRoot = path.resolve(packageRoot);
  const maximumFiles = options.maximumFiles ?? 25_000;
  const maximumFileBytes = options.maximumFileBytes ?? 256 * 1024 * 1024;
  const findings = [];
  const inventory = { nativeAddons: [], nativeBuildManifests: [], typeScriptSources: 0 };
  let fileCount = 0;

  const rootStat = await fs.lstat(requestedRoot);
  if (!rootStat.isDirectory() || rootStat.isSymbolicLink()) {
    return {
      findings: [unsupported('Package root must be a real directory.', { code: 'archive_layout_invalid', phase: 'archive' })],
      treeFileCount: 0,
      inventory,
    };
  }
  const root = await fs.realpath(requestedRoot);
  const stack = [root];

  while (stack.length) {
    const directory = stack.pop();
    for (const entry of await fs.readdir(directory, { withFileTypes: true })) {
      const absolute = path.resolve(directory, entry.name);
      const relative = relativePath(root, absolute);
      if (!isInside(root, absolute)) {
        findings.push(unsupported(`Archive path escapes the package root: ${relative}`, {
          code: 'archive_path_escape', path: relative, phase: 'archive',
        }));
        continue;
      }
      fileCount += 1;
      if (fileCount > maximumFiles) {
        findings.push(unsupported(`Package contains more than ${maximumFiles} files.`, {
          code: 'archive_file_limit', phase: 'archive',
        }));
        return { findings, treeFileCount: fileCount, inventory };
      }
      if (entry.isSymbolicLink()) {
        const target = await fs.readlink(absolute);
        const resolved = path.resolve(path.dirname(absolute), target);
        if (!isInside(root, resolved)) {
          findings.push(unsupported(`Unsafe symbolic link: ${relative}`, {
            code: 'archive_unsafe_symlink', path: relative, phase: 'archive',
          }));
        }
        continue;
      }
      if (entry.isDirectory()) {
        const realDirectory = await fs.realpath(absolute);
        if (!isInside(root, realDirectory)) {
          findings.push(unsupported(`Directory resolves outside the package root: ${relative}`, {
            code: 'archive_path_escape', path: relative, phase: 'archive',
          }));
        } else {
          stack.push(absolute);
        }
        continue;
      }
      if (!entry.isFile()) {
        findings.push(unsupported(`Unsupported archive entry type: ${relative}`, {
          code: 'archive_layout_invalid', path: relative, phase: 'archive',
        }));
        continue;
      }

      const stat = await fs.stat(absolute);
      if (stat.size > maximumFileBytes) {
        findings.push(unsupported(`Archive file is unexpectedly large: ${relative}`, {
          code: 'archive_file_too_large', path: relative, phase: 'archive',
        }));
      }
      const lower = entry.name.toLowerCase();
      if (lower.endsWith('.node')) inventory.nativeAddons.push(relative);
      if (lower === 'binding.gyp') inventory.nativeBuildManifests.push(relative);
      if (lower.endsWith('.ts') && !lower.endsWith('.d.ts')) inventory.typeScriptSources += 1;
      if (lower === 'package.json' && stat.size <= 2 * 1024 * 1024) {
        try {
          const nestedManifest = JSON.parse(await fs.readFile(absolute, 'utf8'));
          if (!nestedManifest || typeof nestedManifest !== 'object' || Array.isArray(nestedManifest)) throw new Error('not an object');
        } catch {
          findings.push(unsupported(`Invalid package manifest: ${relative}`, {
            code: 'archive_invalid_manifest', path: relative, phase: 'archive',
          }));
        }
      }
    }
  }

  const unusedArtifacts = [...inventory.nativeAddons, ...inventory.nativeBuildManifests];
  if (unusedArtifacts.length) {
    const first = unusedArtifacts[0];
    findings.push(info(
      `Package contains native build material at ${first}; it is inventory only unless the selected entry point loads it.`,
      { code: 'unreachable_blocked_reference', path: first, reachable: false, phase: 'archive' },
    ));
  }
  return { findings, treeFileCount: fileCount, inventory };
}

export async function inspectSelectedEntryPoint(packageRoot, manifest, options = {}) {
  if (!options.entryPoint) throw new TypeError('A selected entry point is required for execution-path compatibility analysis.');
  const requestedRoot = path.resolve(packageRoot);
  const entryPoint = path.resolve(options.entryPoint);
  const relative = relativePath(requestedRoot, entryPoint);
  const findings = [];
  if (!isInside(requestedRoot, entryPoint)) {
    findings.push(unsupported('Entry point escapes the package directory.', {
      code: 'entry_point_escape', path: relative, reachable: true, phase: 'entryPoint',
    }));
    return { findings, entryPoint: relative, moduleKind: options.moduleKind ?? null };
  }
  const root = await fs.realpath(requestedRoot);
  let stat;
  try {
    stat = await fs.stat(entryPoint);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
    findings.push(unsupported(`Selected entry point does not exist: ${relative}`, {
      code: 'entry_point_missing', path: relative, reachable: true, phase: 'entryPoint',
    }));
    return { findings, entryPoint: relative, moduleKind: options.moduleKind ?? null };
  }
  if (!stat.isFile()) {
    findings.push(unsupported(`Selected entry point is not a file: ${relative}`, {
      code: 'entry_point_missing', path: relative, reachable: true, phase: 'entryPoint',
    }));
    return { findings, entryPoint: relative, moduleKind: options.moduleKind ?? null };
  }
  const realEntry = await fs.realpath(entryPoint);
  if (!isInside(root, realEntry)) {
    findings.push(unsupported(`Selected entry point resolves outside the package directory: ${relative}`, {
      code: 'entry_point_escape', path: relative, reachable: true, phase: 'entryPoint',
    }));
    return { findings, entryPoint: relative, moduleKind: options.moduleKind ?? null };
  }

  const extension = path.extname(entryPoint).toLowerCase();
  const moduleKind = options.moduleKind ?? determineModuleKind(entryPoint, manifest);
  if (['.ts', '.cts', '.mts'].includes(extension)) {
    findings.push(info(`Selected TypeScript entry point requires focused compilation: ${relative}`, {
      code: 'compatible_after_typescript_compilation', path: relative, reachable: true, phase: 'entryPoint',
    }));
  }
  if (sourceExtensions.has(extension) && stat.size <= 2 * 1024 * 1024) {
    const source = await fs.readFile(entryPoint, 'utf8');
    const blocked = literalBlockedSpecifiers(source);
    for (const specifier of blocked) {
      findings.push(warning(
        `Selected source references ${specifier}; the runtime module policy will verify whether that access executes.`,
        { code: 'dynamic_resolution_unverified', path: relative, specifier, reachable: true, phase: 'entryPoint' },
      ));
    }
    if (hasNonliteralResolution(source)) {
      findings.push(warning(`Dynamic module resolution could not be verified statically in ${relative}.`, {
        code: 'dynamic_resolution_unverified', path: relative, reachable: true, phase: 'entryPoint',
      }));
    }
  }
  return { findings, entryPoint: relative, moduleKind };
}

export async function analyzePackage(packageRoot, manifest, options = {}) {
  if (!options.entryPoint) throw new TypeError('analyzePackage requires an explicit selected entry point.');
  const manifestFindings = inspectManifest(manifest, options.nodeVersion);
  const archive = await inspectArchiveSafety(packageRoot, options);
  const selected = await inspectSelectedEntryPoint(packageRoot, manifest, options);
  let runtimeProbe = null;
  if (typeof options.runtimeProbe === 'function'
      && ![...manifestFindings, ...archive.findings, ...selected.findings].some(item => item.severity === 'unsupported')) {
    runtimeProbe = await options.runtimeProbe();
  }
  return mergeCompatibilityReports({
    manifestFindings,
    archive,
    selected,
    runtimeProbe,
  });
}

export function mergeCompatibilityReports({ manifestFindings = [], archive = {}, selected = {}, runtimeProbe = null }) {
  const findings = [...manifestFindings, ...(archive.findings ?? []), ...(selected.findings ?? [])];
  if (runtimeProbe) {
    findings.push(...runtimeProbeFindings(runtimeProbe));
  }
  const unique = uniqueFindings(findings);
  const verdict = unique.some(item => item.severity === 'unsupported')
    ? 'unsupported'
    : unique.some(item => item.severity === 'warning') ? 'compatibleWithWarnings' : 'compatible';
  return {
    verdict,
    findings: unique,
    runtimeProbePassed: Boolean(runtimeProbe?.passed),
    entryPoint: selected.entryPoint ?? null,
    treeFileCount: archive.treeFileCount ?? null,
    reachableModuleCount: runtimeProbe?.reachableModuleCount ?? 0,
    resolvedModuleCount: runtimeProbe?.resolvedModuleCount ?? 0,
    dynamicUnresolvedCount: runtimeProbe?.dynamicUnresolvedCount ?? 0,
    runtimeProbeDuration: runtimeProbe?.durationMilliseconds ?? null,
    requiresConfiguration: Boolean(runtimeProbe?.requiresConfiguration),
    blockedAccesses: runtimeProbe?.blockedAccesses ?? [],
    moduleEdges: runtimeProbe?.moduleEdges ?? [],
    runtimeProbeToolCount: runtimeProbe?.toolCount ?? null,
  };
}

export function resolveEntryPoint(manifest, override) {
  if (override) {
    if (manifest.bin && typeof manifest.bin === 'object' && typeof manifest.bin[override] === 'string') {
      return { entryPoint: manifest.bin[override], binName: override };
    }
    const matchingBin = typeof manifest.bin === 'object'
      ? Object.entries(manifest.bin).find(([, entryPoint]) => entryPoint === override)
      : null;
    return { entryPoint: override, binName: matchingBin?.[0] ?? null };
  }
  if (typeof manifest.bin === 'string') return { entryPoint: manifest.bin, binName: manifest.name };
  if (manifest.bin && typeof manifest.bin === 'object') {
    const entries = Object.entries(manifest.bin);
    if (entries.length === 1) return { binName: entries[0][0], entryPoint: entries[0][1] };
    if (entries.length > 1) throw new Error(`Multiple bin entries require an explicit selection: ${entries.map(([name]) => name).join(', ')}`);
  }
  const exported = manifest.exports?.['.'] ?? manifest.exports;
  if (typeof exported === 'string') return { entryPoint: exported, binName: null };
  if (exported && typeof exported === 'object') {
    for (const key of ['import', 'require', 'default']) {
      if (typeof exported[key] === 'string') return { entryPoint: exported[key], binName: null };
    }
  }
  if (typeof manifest.main === 'string') return { entryPoint: manifest.main, binName: null };
  throw new Error('No executable entry point was found in bin, exports, or main.');
}

export function listEntryPoints(manifest) {
  const candidates = [];
  if (typeof manifest.bin === 'string') candidates.push(manifest.bin);
  if (manifest.bin && typeof manifest.bin === 'object') candidates.push(...Object.values(manifest.bin));
  const exported = manifest.exports?.['.'] ?? manifest.exports;
  if (typeof exported === 'string') candidates.push(exported);
  if (exported && typeof exported === 'object') {
    for (const key of ['import', 'require', 'default']) {
      if (typeof exported[key] === 'string') candidates.push(exported[key]);
    }
  }
  if (typeof manifest.main === 'string') candidates.push(manifest.main);
  return [...new Set(candidates)];
}

export function determineModuleKind(entryPoint, manifest) {
  const extension = path.extname(entryPoint).toLowerCase();
  if (extension === '.cjs' || extension === '.cts') return 'commonjs';
  if (extension === '.mjs' || extension === '.mts') return 'esm';
  return manifest.type === 'module' ? 'esm' : 'commonjs';
}

function runtimeProbeFindings(probe) {
  const findings = [];
  for (const access of probe.blockedAccesses ?? []) {
    const code = access.code ?? 'reachable_blocked_builtin';
    const parent = access.parentPath ?? '<selected entry point>';
    if (code === 'reachable_native_addon') {
      findings.push(unsupported(`The selected entry point loaded native addon ${access.resolvedPath ?? access.specifier} from ${parent}.`, {
        code, path: access.resolvedPath, specifier: access.specifier, parentPath: access.parentPath,
        reachable: true, phase: 'runtimeProbe', importChain: access.importChain,
      }));
    } else if (code === 'reachable_external_executable') {
      findings.push(unsupported(`The selected entry point requested external process capability ${access.specifier} from ${parent}.`, {
        code, specifier: access.specifier, parentPath: access.parentPath,
        reachable: true, phase: 'runtimeProbe', importChain: access.importChain,
      }));
    } else {
      findings.push(unsupported(`The selected server entry point attempted to load ${access.specifier} from ${parent}.`, {
        code: 'reachable_blocked_builtin', specifier: access.specifier, parentPath: access.parentPath,
        reachable: true, phase: 'runtimeProbe', importChain: access.importChain,
      }));
    }
  }
  if (probe.dynamicUnresolvedCount > 0) {
    findings.push(warning(`Dynamic module resolution could not be verified in ${probe.dynamicUnresolvedCount} loaded module(s).`, {
      code: 'dynamic_resolution_unverified', reachable: true, phase: 'runtimeProbe',
    }));
  }
  if (probe.passed) {
    findings.push(info('The selected entry point passed the MCP runtime probe.', {
      code: 'runtime_probe_passed', reachable: true, phase: 'runtimeProbe',
    }));
  } else if (probe.requiresConfiguration) {
    findings.push(warning(`The server requires configuration before its runtime probe can complete: ${probe.message}`, {
      code: 'configuration_required', reachable: true, phase: 'runtimeProbe',
    }));
  } else if ((probe.blockedAccesses ?? []).length === 0) {
    findings.push(unsupported(`The selected entry point failed the MCP runtime probe: ${probe.message}`, {
      code: 'runtime_probe_failed', reachable: true, phase: 'runtimeProbe',
    }));
  }
  return findings;
}

function literalBlockedSpecifiers(source) {
  const result = [];
  const pattern = /(?:from\s*|import\s*\(\s*|require\s*\(\s*|getBuiltinModule\s*\(\s*)['"]((?:node:)?(?:child_process|cluster))['"]/g;
  for (const match of source.matchAll(pattern)) result.push(match[1]);
  if (/process\.binding\s*\(\s*['"]spawn_sync['"]\s*\)/.test(source)) result.push('spawn_sync');
  return [...new Set(result)];
}

function hasNonliteralResolution(source) {
  return /\b(?:import|require)\s*\(\s*(?!['"`])/.test(source);
}

function allows(values, current) {
  const positives = values.filter(value => !value.startsWith('!'));
  if (values.includes(`!${current}`)) return false;
  return positives.length === 0 || positives.includes(current);
}

function isInside(root, candidate) {
  const relative = path.relative(path.resolve(root), path.resolve(candidate));
  return relative !== '..' && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative);
}

function relativePath(root, candidate) {
  const relative = path.relative(path.resolve(root), path.resolve(candidate));
  return (relative || '.').replaceAll(path.sep, '/');
}

function unsupported(message, fields = {}) { return { severity: 'unsupported', message, ...optionalFields(fields) }; }
function warning(message, fields = {}) { return { severity: 'warning', message, ...optionalFields(fields) }; }
function info(message, fields = {}) { return { severity: 'info', message, ...optionalFields(fields) }; }

function optionalFields(fields) {
  return Object.fromEntries(Object.entries(fields).filter(([, value]) => value !== undefined && value !== null));
}

function uniqueFindings(findings) {
  return [...new Map(findings.map(item => [
    [item.severity, item.code, item.message, item.path, item.specifier, item.parentPath].join(':'),
    item,
  ])).values()];
}
