#!/usr/bin/env node
import { execFileSync } from 'node:child_process';
import { readFile, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dependencyImpact } from './dependency-update-policy.mjs';

const [repository, number] = process.argv.slice(2);
if (!/^[\w.-]+\/[\w.-]+$/.test(repository ?? '') || !/^\d+$/.test(number ?? '')) throw new Error('Expected repository and PR number');
const api = suffix => JSON.parse(execFileSync('gh',['api',`repos/${repository}/${suffix}`],{encoding:'utf8',stdio:['ignore','pipe','pipe']}));
const pr = api(`pulls/${number}`);
const head = execFileSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).trim();
if (pr.head.repo.full_name !== repository || head !== pr.head.sha) throw new Error('Only the actual same-repository candidate HEAD can be verified');
const files = api(`pulls/${number}/files?per_page=100`);
if (files.length === 100 || files.length !== pr.changed_files) throw new Error('Incomplete diff');
const changedPaths = files.map(file=>file.filename).sort();
if (dependencyImpact(changedPaths) !== 'runtime-host') throw new Error('This scoped Host lane cannot validate native, tooling, or unknown consumers');
const base = pr.base.sha;
execFileSync('git',['fetch','--no-tags','origin',base]);
const previous = JSON.parse(execFileSync('git',['show',`${base}:RuntimeDependencies.lock.json`],{encoding:'utf8'}));
const current = JSON.parse(await readFile('RuntimeDependencies.lock.json','utf8'));
for (const key of ['node','python','iosSystem','runtimeBundle']) {
  if (JSON.stringify(previous[key]) !== JSON.stringify(current[key])) throw new Error(`Native/artifact field ${key} changed: full ABI/source-to-binary validation is required`);
}
const pkg = JSON.parse(await readFile('AI_HLY/Downstream/RuntimeCore/Node/Host/package.json','utf8'));
const lock = JSON.parse(await readFile('AI_HLY/Downstream/RuntimeCore/Node/Host/package-lock.json','utf8'));
const priorLock = JSON.parse(execFileSync('git',['show',`${base}:AI_HLY/Downstream/RuntimeCore/Node/Host/package-lock.json`],{encoding:'utf8'}));
const semver = createRequire(new URL('./DependencyUpdates/package.json',import.meta.url))('semver');
const updates = [];
for (const [name,value] of Object.entries(current.nodeHostPackages)) {
  if (JSON.stringify(value) === JSON.stringify(previous.nodeHostPackages[name])) continue;
  const installed = lock.packages?.[`node_modules/${name}`];
  const metadata = await fetch(`https://registry.npmjs.org/${name.replace('/','%2f')}/${value.version}`, {signal:AbortSignal.timeout(60_000)});
  if (!metadata.ok) throw new Error(`Registry lookup failed: ${name}`);
  const upstream = await metadata.json();
  if (pkg.dependencies[name] !== value.version || installed?.version !== value.version || installed.integrity !== value.integrity
      || upstream.dist?.integrity !== value.integrity || upstream.license !== value.license
      || (upstream.engines?.node && !semver.satisfies(current.node.version,upstream.engines.node))) {
    throw new Error(`Source/lock/registry/engine/license drift: ${name}`);
  }
  if (value.license !== previous.nodeHostPackages[name]?.license) throw new Error(`License changed; manual review required: ${name}`);
  let sourceRepository = typeof upstream.repository === 'string' ? upstream.repository : upstream.repository?.url;
  const source = sourceRepository?.match(/github\.com[/:]([^/]+\/[^/#]+?)(?:\.git)?$/)?.[1];
  if (!source || !/^[a-f0-9]{40}$/.test(upstream.gitHead??'')) throw new Error(`Missing exact upstream Git provenance: ${name}`);
  const commit = JSON.parse(execFileSync('gh',['api',`repos/${source}/commits/${upstream.gitHead}`],{encoding:'utf8',stdio:['ignore','pipe','pipe']}));
  if (commit.sha !== upstream.gitHead) throw new Error(`Upstream commit mismatch: ${name}`);
  const updateType = semver.diff(previous.nodeHostPackages[name].version,value.version);
  if (!['patch','minor'].includes(updateType)) throw new Error(`Manual major/prerelease/retarget review required: ${name}`);
  updates.push({name,previous:previous.nodeHostPackages[name].version,version:value.version,updateType,
    integrity:value.integrity,license:value.license,licenseReview:'UNCHANGED_FROM_PARENT_LOCK',
    sourceRepository:source,upstreamCommit:upstream.gitHead,tarball:upstream.dist.tarball});
}
if (!updates.length) throw new Error('No verified direct Host dependency update');
if (JSON.stringify(previous.typescript) !== JSON.stringify(current.typescript)) throw new Error('Compiler updates require their own consumer acceptance');
const changedDirect = new Set(updates.map(item=>`node_modules/${item.name}`));
for (const path of new Set([...Object.keys(priorLock.packages),...Object.keys(lock.packages)])) {
  if (!path || changedDirect.has(path)) continue;
  const identity = value => value && JSON.stringify({version:value.version,resolved:value.resolved,integrity:value.integrity,license:value.license});
  if (identity(priorLock.packages[path]) !== identity(lock.packages[path])) throw new Error(`Unscoped transitive graph change requires review: ${path}`);
}
const context = {schemaVersion:1,repository,pullRequest:Number(number),head,base,changedPaths,impact:'runtime-host',
  updateType:updates.some(item=>item.updateType==='minor')?'minor':'patch',updates,
  nativeArtifact:'Unchanged exact native identity must also pass the existing authenticated consumer before Host tests',
  rollback:{commit:head,parent:base,strategy:'Revert the isolated dependency candidate; preserve original binary pins and regenerate the original Host archive'}};
await writeFile('build/upstream-updates/context.json',JSON.stringify(context,null,2)+'\n');
console.log(JSON.stringify(context));
