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
  rollback:{parent:'2'.repeat(40)},protection:{required_status_checks:{strict:true,contexts:['gate'],checks:[{context:'gate',app_id:15368}]}},effectiveRules:[],autoMergeEnabled:true,required:['gate'],
  checks:[{name:'gate',head,status:'completed',conclusion:'success',app:'github-actions',appId:15368}]});
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
  ['unprotected branch',s=>{s.protection=undefined},'BRANCH_NOT_PROTECTED'],
  ['merge not enabled',s=>{s.autoMergeEnabled=false},'AUTO_MERGE_DISABLED']
]) test(`merge refuses ${name}`,()=>{const s=valid();mutate(s);const result=evaluateUpdate(s);assert.equal(result.mergeEligible,false);assert.ok(result.reasons.includes(reason));});
test('a familiar lock filename cannot hide unknown source/native changes',()=>{
  assert.equal(dependencyImpact(['AI_HLY/Downstream/RuntimeCore/Node/Host/package.json']),'runtime-host');
  assert.equal(dependencyImpact(['Scripts/Runtime/DependencyUpdates/package-lock.json']),'tooling');
  assert.equal(dependencyImpact(['RuntimeDependencies.lock.json','Scripts/NativeScript/metadata_public_headers.py']),'native-or-unknown');
  assert.equal(dependencyImpact([]),'unknown');
});


const addRequired = (s, context, conclusion = 'success', status = 'completed') => {
  s.protection.required_status_checks.contexts.push(context);
  s.protection.required_status_checks.checks.push({context, app_id:77});
  s.checks.push({name:context,head,app:'other-trusted-ci',appId:77,status,conclusion});
};
test('merge correct protected set requires every exact server context on the same head',()=>{
  const s=valid();addRequired(s,'lint');
  const decision=evaluateUpdate(s);
  assert.equal(decision.validationPassed,true);assert.equal(decision.mergeEligible,true);
  assert.deepEqual(decision.branchPolicy.requiredGates.map(g=>g.context),['gate','lint']);
});
test('merge protected-but-wrong-gate cannot substitute lint for the upstream gate',()=>{
  const s=valid();s.protection.required_status_checks={strict:true,contexts:['lint']};
  s.checks.push({name:'lint',head,app:'github-actions',appId:15368,status:'completed',conclusion:'success'});
  const decision=evaluateUpdate(s);assert.equal(decision.validationPassed,true);
  assert.equal(decision.mergeEligible,false);assert.ok(decision.reasons.includes('UPSTREAM_GATE_NOT_REQUIRED:gate'));
});
for(const [label,conclusion,status] of [['failed','failure','completed'],['pending',null,'in_progress'],['skipped','skipped','completed']]) {
  test(`merge extra-required-${label} blocks even after upstream validation passes`,()=>{
    const s=valid();addRequired(s,'security',conclusion,status);const decision=evaluateUpdate(s);
    assert.equal(decision.validationPassed,true);assert.equal(decision.mergeEligible,false);
    assert.ok(decision.reasons.includes('SERVER_REQUIRED_GATE_NOT_PASS:security'));
  });
}
test('merge server context preserves the original raw prefixed check name',()=>{
  const s=valid();s.required=[['gate','upstream-validation / gate']];
  s.protection.required_status_checks={strict:true,contexts:['upstream-validation / gate'],checks:[{context:'upstream-validation / gate',app_id:15368}]};
  // Logical aliases may validate the producer; server enforcement must match literally.
  const missing=evaluateUpdate(s);assert.equal(missing.validationPassed,true);assert.equal(missing.mergeEligible,false);
  s.checks[0].name='upstream-validation / gate';assert.equal(evaluateUpdate(s).mergeEligible,true);
});
test('merge missing or ambiguous server configuration stays blocked',()=>{
  for(const required_status_checks of [null,{strict:true},{strict:true,contexts:[]},
    {strict:false,contexts:['gate']},{strict:true,contexts:['gate','gate']},
    {strict:true,checks:[{context:'gate',app_id:15368},{context:'gate',app_id:77}]},
    {strict:true,contexts:['gate'],checks:'unknown'}]) {
    const s=valid();s.protection={required_status_checks};
    const decision=evaluateUpdate(s);assert.equal(decision.validationPassed,true);assert.equal(decision.mergeEligible,false);
  }
});
test('merge app binding is enforced for additional required gates',()=>{
  const s=valid();addRequired(s,'security');s.checks.at(-1).appId=88;
  assert.equal(evaluateUpdate(s).mergeEligible,false);
});
test('merge checks-only server configuration is supported without losing app bindings',()=>{
  const s=valid();delete s.protection.required_status_checks.contexts;
  assert.equal(evaluateUpdate(s).mergeEligible,true);
});
test('merge legacy any-app context requires an unambiguous authenticated check run',()=>{
  const s=valid();s.protection.required_status_checks={strict:true,contexts:['gate']};
  assert.equal(evaluateUpdate(s).mergeEligible,true);
  s.checks.push({...s.checks[0],app:'other-app',appId:77});assert.equal(evaluateUpdate(s).mergeEligible,false);
});
test('merge required status-only or missing gate is unknown rather than silently omitted',()=>{
  const s=valid();s.protection.required_status_checks.contexts.push('legacy-ci');
  const decision=evaluateUpdate(s);assert.equal(decision.validationPassed,true);assert.equal(decision.mergeEligible,false);
  assert.ok(decision.reasons.includes('SERVER_REQUIRED_GATE_NOT_PASS:legacy-ci'));
});
test('merge extra required check cannot borrow another head result',()=>{
  const s=valid();addRequired(s,'security');s.checks.at(-1).head='3'.repeat(40);
  assert.equal(evaluateUpdate(s).mergeEligible,false);
});
test('merge unrelated failed checks do not replace the configured required set',()=>{
  const s=valid();s.checks.push({name:'optional',head,app:'github-actions',appId:15368,status:'completed',conclusion:'failure'});
  assert.equal(evaluateUpdate(s).mergeEligible,true);
});
test('merge unknown or additional effective branch rules require explicit review',()=>{
  for(const effectiveRules of [undefined,[{type:'required_status_checks',parameters:{required_status_checks:[{context:'security'}]}}]]) {
    const s=valid();s.effectiveRules=effectiveRules;const decision=evaluateUpdate(s);
    assert.equal(decision.validationPassed,true);assert.equal(decision.mergeEligible,false);
    assert.equal(decision.branchPolicy.configurationKnown,false);
  }
});
test('merge caller protectedBranch boolean cannot bypass absent server configuration',()=>{
  const s=valid();delete s.protection;s.protectedBranch=true;
  assert.equal(evaluateUpdate(s).mergeEligible,false);
});
