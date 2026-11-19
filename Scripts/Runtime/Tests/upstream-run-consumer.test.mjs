import test from 'node:test';
import assert from 'node:assert/strict';
import {PROOF_CHECK,ACTIONS_APP_ID,isProtectedAcceptanceBase,candidateForRun,requireCandidateProof,mayEnableAutoMerge}
  from '../upstream-run-consumer-policy.mjs';
const repository='davidpovarsky/hanlin-ai';
const allowedBase='codex/upstream-acceptance-base-20261119';
const head='a'.repeat(40),base='b'.repeat(40);
const run={repository:{full_name:repository},head_repository:{full_name:repository},
  path:'.github/workflows/check-runtime-dependency-updates.yml',event:'workflow_dispatch',
  status:'completed',conclusion:'success',head_sha:head,head_branch:'codex/renovate/unique/semver-7.x'};
const pr={number:1,state:'open',draft:false,
  base:{ref:allowedBase,sha:base,repo:{full_name:repository}},
  head:{ref:run.head_branch,sha:head,repo:{full_name:repository}}};
const report={pullRequest:1,repository,head,baseSHA:base,validationPassed:true,
  consumerAccounting:{receiptSchemaVersion:2,status:'EXECUTED_PASS'},
  requiredChecks:{strict:true,checks:[
    {context:'Hanlin upstream acceptance',app_id:ACTIONS_APP_ID},
    {context:PROOF_CHECK,app_id:ACTIONS_APP_ID}]},
  branchPolicy:{configurationKnown:true,eligible:true},reasons:['AUTO_MERGE_DISABLED']};
test('one exact protected-base current-head candidate is selected',()=>{
  assert.equal(candidateForRun(run,[pr],repository,allowedBase),pr);
  assert.equal(requireCandidateProof(report,pr,run),true);
  assert.equal(mayEnableAutoMerge(report,pr,run),true);
});
test('generic base-branch audit cannot select a candidate',()=>{
  assert.equal(candidateForRun({...run,head_branch:allowedBase},[pr],repository,allowedBase),null);
});
test('a moved candidate does not inherit the old run',()=>{
  const newer=structuredClone(pr);newer.head.sha='c'.repeat(40);
  assert.equal(candidateForRun(run,[newer],repository,allowedBase),null);
});
test('foreign repository run is rejected',()=>{
  assert.throws(()=>candidateForRun({...run,head_repository:{full_name:'other/repo'}},[pr],repository,allowedBase));
});
test('non-dispatch and noncanonical run paths are rejected',()=>{
  for(const delta of [{event:'pull_request'}, {path:'.github/workflows/other.yml'}, {status:'in_progress'}])
    assert.throws(()=>candidateForRun({...run,...delta},[pr],repository,allowedBase));
});
test('ambiguous and incomplete pull inventories are rejected',()=>{
  assert.throws(()=>candidateForRun(run,[pr,pr],repository,allowedBase));
  assert.throws(()=>candidateForRun(run,Array(100).fill(pr),repository,allowedBase));
});
test('draft and unowned candidate branches cannot become eligible',()=>{
  assert.throws(()=>candidateForRun(run,[{...pr,draft:true}],repository,allowedBase));
  const h='feature/unknown';const other=structuredClone(pr);other.head.ref=h;
  assert.throws(()=>candidateForRun({...run,head_branch:h},[other],repository,allowedBase));
});
test('failed or skipped source run cannot use an otherwise positive receipt',()=>{
  for(const conclusion of ['failure','skipped','cancelled','timed_out'])
    assert.throws(()=>requireCandidateProof(report,pr,{...run,conclusion}));
});
test('green audit without schema2 native-origin accounting is rejected',()=>{
  const audit=structuredClone(report);audit.consumerAccounting={status:'UNKNOWN',receiptSchemaVersion:null};
  assert.throws(()=>requireCandidateProof(audit,pr,run));
});
test('legacy schema1 proof is never upgraded',()=>{
  const legacy=structuredClone(report);legacy.consumerAccounting.receiptSchemaVersion=1;
  assert.throws(()=>requireCandidateProof(legacy,pr,run));
});
test('base and source receipt drift are rejected',()=>{
  for(const delta of [{head:'d'.repeat(40)}, {baseSHA:'d'.repeat(40)}, {pullRequest:2}, {repository:'other/repo'}])
    assert.throws(()=>requireCandidateProof({...report,...delta},pr,run));
});
test('unknown or failed source validation cannot qualify',()=>{
  for(const delta of [{validationPassed:false}, {validationPassed:null}, {consumerAccounting:{receiptSchemaVersion:2,status:'UNKNOWN'}}])
    assert.throws(()=>requireCandidateProof({...report,...delta},pr,run));
});
test('strict source and proof app bindings are both required',()=>{
  for(const mutate of [
    x=>x.requiredChecks.strict=false,
    x=>x.requiredChecks.checks[0].app_id=1,
    x=>x.requiredChecks.checks[1].app_id=-1,
    x=>x.requiredChecks.checks=x.requiredChecks.checks.slice(0,1),
    x=>x.requiredChecks.checks.push({...x.requiredChecks.checks[1]}),
    x=>x.branchPolicy.configurationKnown=false]) {
    const x=structuredClone(report);mutate(x);assert.throws(()=>requireCandidateProof(x,pr,run));
  }
});
test('an additional required failed gate prevents automatic merge',()=>{
  const x=structuredClone(report);x.branchPolicy.eligible=false;
  x.reasons.push('SERVER_REQUIRED_GATE_NOT_PASS:Existing product gate');
  assert.equal(requireCandidateProof(x,pr,run),true);
  assert.equal(mayEnableAutoMerge(x,pr,run),false);
});
test('pending, stale, skipped and ambiguous server gates prevent automatic merge',()=>{
  for(const reason of ['SERVER_REQUIRED_GATE_NOT_PASS:pending','SERVER_REQUIRED_GATE_NOT_PASS:stale',
    'SERVER_REQUIRED_GATE_NOT_PASS:skipped','ADDITIONAL_BRANCH_RULES_REQUIRE_REVIEW']) {
    const x=structuredClone(report);x.reasons.push(reason);
    assert.equal(mayEnableAutoMerge(x,pr,run),false);
  }
});
test('only activation-disabled can remain after all gates pass',()=>{
  assert.equal(mayEnableAutoMerge({...report,reasons:[]},pr,run),true);
  assert.equal(mayEnableAutoMerge({...report,reasons:['MANUAL_VERSION_REVIEW']},pr,run),false);
});
test('closed or draft proposals cannot activate automatic merge',()=>{
  assert.equal(mayEnableAutoMerge(report,{...pr,state:'closed'},run),false);
  assert.equal(mayEnableAutoMerge(report,{...pr,draft:true},run),false);
});


test('only the three explicitly protected acceptance bases are recognized',()=>{
  for(const base of ['codex/upstream-acceptance-base-20261119',
    'codex/upstream-acceptance-base-20261119-v2','codex/upstream-acceptance-base-20261119-v3'])
    assert.equal(isProtectedAcceptanceBase(base),true);
  for(const base of [undefined,null,'','main','codex/hanlin-product-completion-20261117',
    'codex/upstream-acceptance-base-20261119-v4','codex/upstream-acceptance-base-20261119-v2/extra',
    'codex/upstream-acceptance-base-20261119-v2 ','refs/heads/codex/upstream-acceptance-base-20261119-v2',
    'codex/upstream-acceptance-base-20261119-v3/extra','codex/upstream-acceptance-base-20261119-v3 ',
    'refs/heads/codex/upstream-acceptance-base-20261119-v3'])
    assert.equal(isProtectedAcceptanceBase(base),false);
});

test('v2 selects only its own exact candidate and never inherits the original base',()=>{
  const v2='codex/upstream-acceptance-base-20261119-v2';
  const candidate=structuredClone(pr);candidate.base.ref=v2;
  assert.equal(candidateForRun(run,[candidate],repository,v2),candidate);
  assert.equal(candidateForRun(run,[candidate],repository,allowedBase),null);
  assert.equal(candidateForRun(run,[pr],repository,v2),null);
  assert.equal(candidateForRun(run,[pr],repository,allowedBase),pr);
});

test('a matching PR cannot authorize a main or unlisted target',()=>{
  for(const target of ['main','codex/hanlin-product-completion-20261117',
    'codex/upstream-acceptance-base-20261119-v4']) {
    const candidate=structuredClone(pr);candidate.base.ref=target;
    assert.throws(()=>candidateForRun(run,[candidate],repository,target),
      /Unrecognized protected acceptance base/);
  }
});

test('v3 selects only its own exact candidate and cannot inherit either older base',()=>{
  const v3='codex/upstream-acceptance-base-20261119-v3';
  const candidate=structuredClone(pr);candidate.base.ref=v3;
  assert.equal(candidateForRun(run,[candidate],repository,v3),candidate);
  for(const older of [allowedBase,'codex/upstream-acceptance-base-20261119-v2']) {
    const previous=structuredClone(pr);previous.base.ref=older;
    assert.equal(candidateForRun(run,[candidate],repository,older),null);
    assert.equal(candidateForRun(run,[previous],repository,v3),null);
    assert.equal(candidateForRun(run,[previous],repository,older),previous);
  }
});
