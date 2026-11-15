import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { planHostUpdates } from '../update-runtime-dependencies.mjs';
import { runtimeDependencyHash } from '../compute-runtime-dependency-hash.mjs';
import { dependencyImpact,evaluateUpdate } from '../dependency-update-policy.mjs';

const semver = createRequire(new URL('../DependencyUpdates/package.json',import.meta.url))('semver');
const sri='sha512-'+Buffer.alloc(64,1).toString('base64');
const metadata = { 'dist-tags':{latest:'2.0.0'}, versions:{
  '1.0.1':{license:'ISC',dist:{integrity:sri,tarball:'https://registry.npmjs.org/example/-/example-1.0.1.tgz'},engines:{node:'>=20'}},
  '2.0.0':{license:'ISC',dist:{integrity:sri},engines:{node:'>=26'}} } };
test('real updater selects supported Host version without upgrading the embedded ABI',async()=>{
  const pkg={dependencies:{example:'1.0.0'}};
  const updates=await planHostUpdates(pkg,'24.5.0',async()=>metadata,semver.satisfies);
  assert.equal(updates[0].version,'1.0.1');assert.equal(updates[0].major,false);
  assert.deepEqual(pkg,{dependencies:{example:'1.0.0'}});
});
test('explicit incompatible target cannot bypass the original engine constraint',async()=>{
  await assert.rejects(planHostUpdates({dependencies:{example:'1.0.0'}},'24.5.0',async()=>metadata,semver.satisfies,
    {only:'example',version:'2.0.0'}),/requires Node/);
});
test('unknown package and missing upstream provenance fail before changing a manifest',async()=>{
  const pkg={dependencies:{example:'1.0.0'}};
  await assert.rejects(planHostUpdates(pkg,'24.5.0',async()=>metadata,semver.satisfies,{only:'unowned'}),/Unknown direct/);
  const broken=structuredClone(metadata);delete broken.versions['1.0.1'].dist.integrity;
  await assert.rejects(planHostUpdates(pkg,'24.5.0',async()=>broken,semver.satisfies),/integrity/);
  assert.equal(pkg.dependencies.example,'1.0.0');
});
test('major changes are proposals requiring review rather than a safe patch',async()=>{
  const updates=await planHostUpdates({dependencies:{example:'1.0.0'}},'26.1.0',async()=>metadata,semver.satisfies);
  assert.equal(updates[0].major,true);assert.equal(updates[0].review,'MANUAL_MAJOR');
});
test('canonical dependency hash preserves its existing output/provenance boundary',async()=>{
  const lock=JSON.parse(await readFile(new URL('../../../RuntimeDependencies.lock.json',import.meta.url),'utf8'));
  const baseline=runtimeDependencyHash(lock), changed=structuredClone(lock);
  changed.runtimeBundle.sourceCommit='a'.repeat(40);changed.runtimeBundle.sha256='b'.repeat(64);
  changed.runtimeBundle.nativeInputSHA256='c'.repeat(64);changed.node.verificationStatus='pending-runtime-build';
  assert.equal(runtimeDependencyHash(changed),baseline);
  changed.nodeHostPackages.semver.version='99.0.0';assert.notEqual(runtimeDependencyHash(changed),baseline);
});

const head='1'.repeat(40);
const valid=()=>({head,evidenceHead:head,updateType:'patch',impact:'runtime-host',sourceIntegrity:true,licensesReviewed:true,
  rollback:{parent:'2'.repeat(40)},protectedBranch:true,autoMergeEnabled:true,required:['gate'],
  checks:[{name:'gate',head,status:'completed',conclusion:'success',app:'github-actions'}]});
test('only complete, current, protected and explicitly enabled evidence can qualify',()=>{
  assert.equal(evaluateUpdate(valid()).mergeEligible,true);
});
for (const [name,mutate,reason] of [
  ['missing checks',s=>{s.checks=[]},'REQUIRED_GATE_NOT_PASS:gate'],
  ['failed CI',s=>{s.checks[0].conclusion='failure'},'REQUIRED_GATE_NOT_PASS:gate'],
  ['skipped CI',s=>{s.checks[0].conclusion='skipped'},'REQUIRED_GATE_NOT_PASS:gate'],
  ['pending CI',s=>{s.checks[0].status='in_progress'},'REQUIRED_GATE_NOT_PASS:gate'],
  ['wrong check source',s=>{s.checks[0].app='untrusted'},'REQUIRED_GATE_NOT_PASS:gate'],
  ['stale check head',s=>{s.checks[0].head='3'.repeat(40)},'REQUIRED_GATE_NOT_PASS:gate'],
  ['stale receipt',s=>{s.evidenceHead='3'.repeat(40)},'EVIDENCE_HEAD_MISMATCH'],
  ['unknown impact',s=>{s.impact='unknown'},'NATIVE_OR_UNKNOWN_IMPACT_REQUIRES_REVIEW'],
  ['native ABI',s=>{s.impact='native'},'NATIVE_OR_UNKNOWN_IMPACT_REQUIRES_REVIEW'],
  ['major',s=>{s.updateType='major'},'MANUAL_VERSION_REVIEW'],
  ['missing license',s=>{s.licensesReviewed=false},'MISSING_LICENSE_REVIEW'],
  ['missing checksum',s=>{s.sourceIntegrity=false},'MISSING_SOURCE_INTEGRITY'],
  ['no gates',s=>{s.required=[]},'NO_REQUIRED_GATES'],
  ['no rollback',s=>{s.rollback=null},'MISSING_ROLLBACK'],
  ['unprotected branch',s=>{s.protectedBranch=false},'BRANCH_NOT_PROTECTED'],
  ['merge not enabled',s=>{s.autoMergeEnabled=false},'AUTO_MERGE_DISABLED']
]) test(`merge refuses ${name}`,()=>{const s=valid();mutate(s);const result=evaluateUpdate(s);assert.equal(result.mergeEligible,false);assert.ok(result.reasons.includes(reason));});
test('a familiar lock filename cannot hide unknown source/native changes',()=>{
  assert.equal(dependencyImpact(['AI_HLY/Downstream/RuntimeCore/Node/Host/package.json']),'runtime-host');
  assert.equal(dependencyImpact(['Scripts/Runtime/DependencyUpdates/package-lock.json']),'tooling');
  assert.equal(dependencyImpact(['RuntimeDependencies.lock.json','Scripts/NativeScript/metadata_public_headers.py']),'native-or-unknown');
  assert.equal(dependencyImpact([]),'unknown');
});
