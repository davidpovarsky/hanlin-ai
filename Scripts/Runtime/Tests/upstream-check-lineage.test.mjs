import test from 'node:test';
import assert from 'node:assert/strict';
import {selectUpstreamCheckLineage} from '../upstream-check-lineage.mjs';
import {evaluateUpdate} from '../dependency-update-policy.mjs';
const repository='davidpovarsky/hanlin-ai',head='a'.repeat(40),prNumber=7;
const sourceName='Hanlin upstream acceptance',proofName='Hanlin upstream schema2 proof';
const app={id:15368,slug:'github-actions'};
function fixture() {
  const entries=new Map(),checks=[];
  const run=(id,attempt=1,consumer=false,created='2026-11-19T01:00:00Z')=>{
    const value={id,run_attempt:attempt,repository:{full_name:repository},head_repository:{full_name:repository},
      head_sha:consumer?'c'.repeat(40):head,head_branch:consumer?'main':'codex/renovate/test/semver',
      path:consumer?'.github/workflows/upstream-candidate-proof.yml':'.github/workflows/check-runtime-dependency-updates.yml',
      event:consumer?'workflow_run':'workflow_dispatch',status:'completed',conclusion:'success',
      check_suite_id:id*10+attempt,created_at:created};
    entries.set('actions/runs/'+id+'/attempts/'+attempt,value);return value;
  };
  const source=(r,id,conclusion='success')=>{
    const check={id,name:sourceName,head_sha:head,app,status:'completed',conclusion,
      details_url:'https://github.com/'+repository+'/actions/runs/'+r.id+'/job/'+id,check_suite:{id:r.check_suite_id}};
    entries.set('actions/jobs/'+id,{id,run_id:r.id,run_attempt:r.run_attempt,head_sha:head,
      name:sourceName,status:check.status,conclusion:check.conclusion,
      check_run_url:'https://api.github.com/repos/'+repository+'/check-runs/'+id});
    checks.push(check);return check;
  };
  const proof=(producer,consumer,id,conclusion='success',status='completed')=>{
    const check={id,name:proofName,head_sha:head,app,status,conclusion,
      external_id:'upstream:'+producer.id+':'+producer.run_attempt+':'+prNumber+':'+consumer.id+':'+consumer.run_attempt,
      details_url:'https://github.com/'+repository+'/actions/runs/'+consumer.id};
    checks.push(check);return check;
  };
  const select=proofRun=>selectUpstreamCheckLineage({rawChecks:checks,repository,head,prNumber,proofRun,
    api:path=>{if(!entries.has(path))throw Error('Unexpected authenticated identity read: '+path);return entries.get(path);}});
  return {entries,checks,run,source,proof,select};
}
function policy(checks) {
  return evaluateUpdate({head,evidenceHead:head,updateType:'patch',impact:'runtime-host',
    checks:checks.map(x=>({name:x.name,head:x.head_sha,app:x.app.slug,appId:x.app.id,checkId:x.id,status:x.status,conclusion:x.conclusion})),
    required:[[sourceName,'upstream-validation / Hanlin upstream acceptance']],sourceIntegrity:true,
    licensesReviewed:true,rollback:true,consumerEvidenceVerified:true,autoMergeEnabled:false,
    protection:{required_status_checks:{strict:true,contexts:[],checks:[{context:sourceName,app_id:15368},{context:proofName,app_id:15368}]}},effectiveRules:[]});
}
test('actual policy bootstraps an in-progress independent proof without claiming merge eligibility',()=>{
  const f=fixture(),r=f.run(10),c=f.run(20,1,true,'2026-11-19T01:01:00Z');
  f.source(r,100);const p=f.proof(r,c,200,null,'in_progress');
  const pending=policy(f.select(r).selectedChecks);
  assert.equal(pending.validationPassed,true);assert.equal(pending.branchPolicy.eligible,false);
  p.status='completed';p.conclusion='success';
  const published=policy(f.select(r).selectedChecks);
  assert.equal(published.validationPassed,true);assert.equal(published.branchPolicy.eligible,true);
  assert.deepEqual(published.reasons,['AUTO_MERGE_DISABLED']);
});
test('authentic later producer attempt replaces older failure; raw history remains attributed',()=>{
  const f=fixture(),old=f.run(10),now=f.run(11,1,false,'2026-11-19T01:01:00Z');
  f.source(old,100,'failure');f.source(now,110);
  const c=f.run(20,1,true,'2026-11-19T01:02:00Z');f.proof(now,c,200);
  const selected=f.select(now);
  assert.equal(selected.producerMatchesProof,true);assert.deepEqual(selected.supersededCheckIDs,[100]);
  assert.equal(policy(selected.selectedChecks).validationPassed,true);
  assert.equal(policy(f.checks).validationPassed,false);
});
test('newest current-head failure is retained, never replaced by older green',()=>{
  const f=fixture(),old=f.run(10),now=f.run(11,1,false,'2026-11-19T01:01:00Z');
  f.source(old,100);f.source(now,110,'failure');
  const selected=f.select(now);
  assert.equal(selected.producer.conclusion,'failure');
  assert.equal(policy(selected.selectedChecks).validationPassed,false);
});
test('out-of-order old completion is superseded before proof publication',()=>{
  const f=fixture(),old=f.run(10),now=f.run(11,1,false,'2026-11-19T01:01:00Z');
  f.source(old,100,'failure');f.source(now,110);
  assert.equal(f.select(old).producerMatchesProof,false);
});
test('same workflow rerun uses exact current run_attempt and original job identity',()=>{
  const f=fixture(),old=f.run(10,1),now=f.run(10,2);
  f.source(old,100,'failure');f.source(now,101);
  const selected=f.select(now);
  assert.equal(selected.producer.attempt,2);assert.equal(selected.producer.checkID,101);
});
test('later consumer on the same producer can replace its previous failed proof',()=>{
  const f=fixture(),r=f.run(10),old=f.run(20,1,true,'2026-11-19T01:01:00Z'),now=f.run(21,1,true,'2026-11-19T01:02:00Z');
  f.source(r,100);f.proof(r,old,200,'failure');f.proof(r,now,210);
  const selected=f.select(r);
  assert.equal(selected.proof.checkID,210);assert.equal(policy(selected.selectedChecks).branchPolicy.eligible,true);
});
test('current producer excludes separately authenticated prior-producer proof history',()=>{
  const f=fixture(),old=f.run(10),now=f.run(11,1,false,'2026-11-19T01:02:00Z');
  f.source(old,100,'failure');f.source(now,110);
  f.proof(old,f.run(20,1,true,'2026-11-19T01:01:00Z'),200,'failure');
  f.proof(now,f.run(21,1,true,'2026-11-19T01:03:00Z'),210);
  assert.deepEqual(f.select(now).supersededCheckIDs,[100,200]);
});
test('unknown extra required failures remain unchanged and blocking',()=>{
  const f=fixture(),r=f.run(10);f.source(r,100);
  const extra={id:300,name:'Product acceptance',head_sha:head,app,status:'completed',conclusion:'failure'};
  f.checks.push(extra);
  const selected=f.select(r);
  assert.ok(selected.selectedChecks.includes(extra));
});
test('duplicates within one authentic attempt remain ambiguous',()=>{
  const f=fixture(),r=f.run(10);f.source(r,100);f.source(r,101);
  assert.throws(()=>f.select(r),/Ambiguous/);
});
test('unknown job binding and ambiguous run chronology fail closed',()=>{
  const f=fixture(),r=f.run(10);f.source(r,100);f.entries.get('actions/jobs/100').check_run_url='https://other.invalid/check';
  assert.throws(()=>f.select(r),/binding/);
  const g=fixture(),a=g.run(10),b=g.run(11);g.source(a,100);g.source(b,110);
  assert.throws(()=>g.select(b),/Ambiguous/);
});
test('a foreign workflow cannot self-claim the independent proof name',()=>{
  const f=fixture(),r=f.run(10),c=f.run(20,1,true);f.source(r,100);f.proof(r,c,200);
  c.path='.github/workflows/other.yml';
  assert.throws(()=>f.select(r),/workflow/);
});
test('proof without source/consumer/run-attempt identity cannot shadow a valid proof',()=>{
  const f=fixture(),r=f.run(10);f.source(r,100);
  f.checks.push({id:200,name:proofName,head_sha:head,app,status:'completed',conclusion:'success',external_id:'unknown'});
  assert.throws(()=>f.select(r),/identity/);
});
test('different-app source checks are not silently filtered out',()=>{
  const f=fixture(),r=f.run(10);f.source(r,100);
  const foreign={id:101,name:sourceName,head_sha:head,app:{id:1,slug:'foreign'},status:'completed',conclusion:'failure'};
  f.checks.push(foreign);const selected=f.select(r);
  assert.ok(selected.selectedChecks.includes(foreign));assert.equal(policy(selected.selectedChecks).validationPassed,false);
});
