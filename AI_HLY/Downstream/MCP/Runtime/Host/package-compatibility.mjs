import { promises as fs } from 'node:fs';
import path from 'node:path';
import semver from 'semver';

const blockedModules = [
  ['child_process', 'child_process is unavailable in the embedded runtime'],
  ['cluster', 'cluster is unsupported in an iOS app'],
];
const externalExecutables = ['docker', 'python', 'python3', 'git', 'ffmpeg'];
const lifecycleNames = ['preinstall', 'install', 'postinstall', 'prepare', 'prepublish'];

export function inspectManifest(manifest, nodeVersion = '18.20.4') {
  const findings = [];
  const requirement = manifest.engines?.node;
  if (requirement && !semver.satisfies(nodeVersion, requirement, { includePrerelease: true })) {
    findings.push(unsupported(`Requires Node ${requirement}; embedded runtime is ${nodeVersion}.`));
  }
  if (Array.isArray(manifest.os) && manifest.os.length > 0 && !allows(manifest.os, 'darwin')) {
    findings.push(unsupported(`Package OS constraint does not allow darwin: ${manifest.os.join(', ')}`));
  }
  if (Array.isArray(manifest.cpu) && manifest.cpu.length > 0 && !allows(manifest.cpu, 'arm64')) {
    findings.push(unsupported(`Package CPU constraint does not allow arm64: ${manifest.cpu.join(', ')}`));
  }
  for (const name of lifecycleNames) {
    if (manifest.scripts?.[name]) findings.push(unsupported(`Lifecycle script '${name}' is required.`));
  }
  return findings;
}

export async function analyzePackage(packageRoot, manifest, options = {}) {
  const maximumFiles = options.maximumFiles ?? 25_000;
  const findings = inspectManifest(manifest);
  let fileCount = 0;
  const stack = [packageRoot];
  while (stack.length) {
    const directory = stack.pop();
    for (const entry of await fs.readdir(directory, { withFileTypes: true })) {
      const absolute = path.join(directory, entry.name);
      const relative = path.relative(packageRoot, absolute).replaceAll(path.sep, '/');
      if (++fileCount > maximumFiles) {
        findings.push(unsupported(`Package contains more than ${maximumFiles} files.`));
        return report(findings);
      }
      if (entry.isSymbolicLink()) {
        const target = await fs.readlink(absolute);
        const resolved = path.resolve(path.dirname(absolute), target);
        if (!isInside(packageRoot, resolved)) findings.push(unsupported(`Unsafe symbolic link: ${relative}`));
        continue;
      }
      if (entry.isDirectory()) {
        stack.push(absolute);
        continue;
      }
      const lower = entry.name.toLowerCase();
      if (lower.endsWith('.node')) findings.push(unsupported(`Native addon found: ${relative}`));
      if (lower === 'binding.gyp') findings.push(unsupported(`Native build manifest found: ${relative}`));
      if (lower.endsWith('.ts') && !lower.endsWith('.d.ts')) {
        findings.push(unsupported(`Uncompiled TypeScript found: ${relative}`));
      }
      if (/\.(?:js|cjs|mjs|json)$/i.test(lower)) {
        const stat = await fs.stat(absolute);
        if (stat.size <= 2 * 1024 * 1024) {
          const source = await fs.readFile(absolute, 'utf8');
          for (const [moduleName, message] of blockedModules) {
            if (new RegExp(`(?:from\\s+|require\\s*\\(\\s*)['\"](?:node:)?${moduleName}['\"]`).test(source)) {
              findings.push(unsupported(`${message}: ${relative}`));
            }
          }
          for (const executable of externalExecutables) {
            if (new RegExp(`(?:spawn|exec|execFile)\\s*\\([^)]*['\"]${executable}['\"]`, 'i').test(source)) {
              findings.push(unsupported(`External executable '${executable}' is required: ${relative}`));
            }
          }
          if (/process\.chdir\s*\(/.test(source)) {
            findings.push(warning(`Global cwd change detected: ${relative}`));
          }
          if (/\.wasm(?:['\"]|$)/i.test(source)) {
            findings.push(warning(`WASM asset referenced; runtime verification is required: ${relative}`));
          }
        }
      }
    }
  }
  return report(findings);
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

function allows(values, current) {
  const positives = values.filter(value => !value.startsWith('!'));
  if (values.includes(`!${current}`)) return false;
  return positives.length === 0 || positives.includes(current);
}

function isInside(root, candidate) {
  const relative = path.relative(path.resolve(root), path.resolve(candidate));
  return relative !== '..' && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative);
}

function unsupported(message) { return { severity: 'unsupported', message }; }
function warning(message) { return { severity: 'warning', message }; }

function report(findings) {
  const unique = [...new Map(findings.map(item => [`${item.severity}:${item.message}`, item])).values()];
  const verdict = unique.some(item => item.severity === 'unsupported')
    ? 'unsupported'
    : unique.length ? 'compatibleWithWarnings' : 'compatibleWithWarnings';
  if (unique.length === 0) unique.push(warning('Static preflight passed; runtime probe is still required.'));
  return { verdict, findings: unique, runtimeProbePassed: false };
}
