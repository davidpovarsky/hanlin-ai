#!/usr/bin/env node
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';

const output = process.argv[2] ?? 'build/upstream-updates/inventory.json';
const tracked = execFileSync('git', ['ls-files', '-z'], { encoding: 'utf8' }).split('\0').filter(Boolean);
// Newly introduced updater tooling is also inventoried before its first commit.
for (const path of ['Scripts/Runtime/DependencyUpdates/package.json', 'Scripts/Runtime/DependencyUpdates/package-lock.json']) {
  if (!tracked.includes(path)) tracked.push(path);
}
const excluded = path => /(?:^|\/)(?:node_modules|Vendor|Reference|Prepared|Artifacts)(?:\/|$)/.test(path)
  || /\/Resources\/NativeScriptSharedRuntime\//.test(path) || /\/Tests\/(?:DownstreamFixtures|Fixtures)\//.test(path);
const manifests = [];
for (const path of tracked.filter(path => !excluded(path) && /(?:^|\/)(?:Package\.swift|Package\.resolved|package\.json|package-lock\.json|dependency-lock\.json)$/.test(path))) {
  const bytes = await readFile(path);
  const row = { path, sha256: createHash('sha256').update(bytes).digest('hex') };
  if (path.endsWith('Package.swift')) {
    row.kind = 'swift-manifest-source';
    // Source inventory only; Renovate/SwiftPM, not this scanner, owns resolution.
    row.remoteDeclarations = [...bytes.toString().matchAll(/\.package\([\s\S]*?url:\s*"([^"]+)"[\s\S]*?\)/g)].map(match => match[0]);
    row.binaryTargets = [...bytes.toString().matchAll(/\.binaryTarget\(/g)].length;
  } else {
    const data = JSON.parse(bytes);
    row.kind = path.endsWith('Package.resolved') ? 'swift-resolution' : path.endsWith('package-lock.json') ? 'npm-resolution' : 'npm-or-native-manifest';
    row.pins = data.pins ?? data.object?.pins;
    row.dependencies = data.dependencies;
    row.devDependencies = data.devDependencies;
    row.engines = data.engines;
    row.packageManager = data.packageManager;
    if (data.packages) row.resolvedPackages = Object.entries(data.packages).map(([location, value]) => ({ location,
      version: value.version, resolved: value.resolved, integrity: value.integrity, license: value.license, engines: value.engines }));
  }
  row.owner = path.startsWith('AI_HLY.xcodeproj/') ? 'INTEGRATOR_XCODE_SHARED_PROJECT_MANUAL'
    : /(?:Expo|NativeScript|ScriptingCompiler)/.test(path) ? 'COUPLED_RUNTIME_MANUAL'
    : path.includes('/Node/Host/') ? 'EXISTING_RUNTIME_UPDATER' : 'RENOVATE_WITH_FOCUSED_ACCEPTANCE';
  manifests.push(row);
}
const native = JSON.parse(await readFile('RuntimeDependencies.lock.json', 'utf8'));
const report = { schemaVersion: 1, sourceSHA: execFileSync('git', ['rev-parse', 'HEAD'], {encoding:'utf8'}).trim(),
  nodeTool: process.version, manifests, nativeLock: native,
  distinction: 'Automation Node is independent of the embedded ABI. An upstream release never changes an installed IPA.' };
await writeFile(output, JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({ path: output, manifests: manifests.length, sourceSHA: report.sourceSHA }));
