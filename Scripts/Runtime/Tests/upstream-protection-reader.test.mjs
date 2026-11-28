import test from 'node:test';
import assert from 'node:assert/strict';
import {projectProtection,readUpstreamProtection} from '../upstream-protection-reader.mjs';
import {evaluateBranchRequirements} from '../dependency-update-policy.mjs';
const scope={repository:'davidpovarsky/hanlin-ai',base:'codex/upstream-acceptance-base-20261119-v3',baseSHA:'b'.repeat(40)};
const contexts=['Hanlin upstream acceptance','Hanlin upstream schema2 proof'];
const response=()=>({data:{repository:{nameWithOwner:scope.repository,ref:{name:scope.base,
  target:{oid:scope.baseSHA},branchProtectionRule:{id:'BPR_test',pattern:scope.base,isAdminEnforced:true,
    requiresStatusChecks:true,requiresStrictStatusChecks:true,requiredStatusCheckContexts:[...contexts],
    requiredStatusChecks:contexts.map(context=>({context,app:{databaseId:15368,slug:'github-actions'}}))}}}}});
const denial=status=>Object.assign(Error('API denied'),{stdout:JSON.stringify({status:String(status)}),stderr:'gh: denied (HTTP '+status+')'});
const policy=(protection,effectiveRules)=>evaluateBranchRequirements({head:'a'.repeat(40),protection,effectiveRules,
  checks:contexts.map((name,i)=>({name,appId:15368,app:'github-actions',head:'a'.repeat(40),status:'completed',conclusion:'success',checkId:i+1})),required:[contexts[0]]});
test('REST success is preserved without invoking an alternative API',()=>{
  const protection={required_status_checks:{strict:true,checks:[]}};
  const result=readUpstreamProtection({...scope,rest:path=>{assert.equal(path,'branches/codex%2Fupstream-acceptance-base-20261119-v3/protection');return protection;},graphql:()=>assert.fail('unexpected GraphQL')});
  assert.equal(result.protection,protection);assert.equal(result.observation.api,'AUTHENTICATED_REST_CLASSIC_PROTECTION');
});
test('only authenticated REST403 triggers exact-ref GraphQL, with explicit provenance',()=>{
  const result=readUpstreamProtection({...scope,rest:()=>{throw denial(403)},graphql:body=>{
    assert.deepEqual(body.variables,{owner:'davidpovarsky',name:'hanlin-ai',ref:'refs/heads/'+scope.base});return response();}});
  assert.equal(result.observation.restStatus,403);assert.equal(result.observation.baseSHA,scope.baseSHA);
  assert.equal(result.protection.enforce_admins.enabled,true);
  assert.deepEqual(result.protection.required_status_checks,{strict:true,contexts,checks:contexts.map(context=>({context,app_id:15368}))});
});
test('REST404 remains unprotected, without an alternate success',()=>{
  assert.equal(readUpstreamProtection({...scope,rest:()=>{throw denial(404)},graphql:()=>assert.fail('unexpected')}).protection,undefined);
});
test('network, server, and unknown REST errors are not reclassified as access denial',()=>{
  for(const error of [denial(500),Error('timeout 403 characters'),{stderr:'403'}])
    assert.throws(()=>readUpstreamProtection({...scope,rest:()=>{throw error},graphql:()=>assert.fail('unexpected')}));
});
test('an unavailable GraphQL read preserves HTTP403 as primary and fails closed',()=>{
  assert.throws(()=>readUpstreamProtection({...scope,rest:()=>{throw denial(403)},graphql:()=>{throw Error('GraphQL denied')}}),/REST protection HTTP403.*GraphQL denied/);
});
test('public or unrelated repositories and unlisted/wildcard bases cannot use fallback',()=>{
  for(const change of [{repository:'other/repo'},{base:'main'},{base:scope.base+'-extra'},{base:'codex/*'},{baseSHA:'bad'}])
    assert.throws(()=>projectProtection(response(),{...scope,...change}));
});
test('partial GraphQL errors are rejected even when data appears positive',()=>{
  for(const errors of [[{message:'denied'}],null,'error']) assert.throws(()=>projectProtection({...response(),errors},scope));
});
test('repository, exact ref, and resolved base commit are all bound to the PR',()=>{
  for(const mutate of [x=>x.data.repository.nameWithOwner='other/repo',x=>x.data.repository.ref.name='main',x=>x.data.repository.ref.target.oid='c'.repeat(40),x=>x.data.repository.ref.target=null]) {
    const x=response();mutate(x);assert.throws(()=>projectProtection(x,scope),/does not match/);
  }
});
test('missing classic rule and wildcard rule are never used as exact protection',()=>{
  for(const mutate of [x=>x.data.repository.ref.branchProtectionRule=null,x=>x.data.repository.ref.branchProtectionRule.pattern='codex/*',x=>x.data.repository.ref.branchProtectionRule.id='']) {
    const x=response();mutate(x);assert.throws(()=>projectProtection(x,scope));
  }
});
test('unknown boolean and incomplete or duplicate required declarations are rejected',()=>{
  for(const mutate of [r=>delete r.isAdminEnforced,r=>r.requiresStrictStatusChecks='true',r=>r.requiresStatusChecks=null,
    r=>delete r.requiredStatusCheckContexts,r=>r.requiredStatusCheckContexts.push(contexts[0]),
    r=>r.requiredStatusChecks=null,r=>r.requiredStatusChecks.push(r.requiredStatusChecks[0]),
    r=>delete r.requiredStatusChecks[0].app,r=>r.requiredStatusChecks[0].app.databaseId='15368']) {
    const x=response();mutate(x.data.repository.ref.branchProtectionRule);assert.throws(()=>projectProtection(x,scope));
  }
});
test('false protection properties are preserved as false rather than synthesized',()=>{
  const x=response();const rule=x.data.repository.ref.branchProtectionRule;
  rule.isAdminEnforced=false;rule.requiresStrictStatusChecks=false;
  const result=projectProtection(x,scope);assert.equal(result.protection.enforce_admins.enabled,false);
  assert.equal(policy(result.protection,[]).configurationKnown,false);
  rule.requiresStatusChecks=false;assert.equal(projectProtection(x,scope).protection.required_status_checks,null);
});
test('complete additional and legacy unbound checks remain required',()=>{
  const x=response();const rule=x.data.repository.ref.branchProtectionRule;
  rule.requiredStatusCheckContexts.push('extra');rule.requiredStatusChecks.push({context:'extra',app:null});
  const protection=projectProtection(x,scope).protection;
  assert.equal(protection.required_status_checks.checks.at(-1).app_id,null);
  assert.equal(policy(protection,[]).eligible,false);
  assert.ok(policy(protection,[]).reasons.includes('SERVER_REQUIRED_GATE_NOT_PASS:extra'));
});
test('GraphQL classic success never supplies missing or additional effective rules',()=>{
  const protection=projectProtection(response(),scope).protection;
  assert.equal(policy(protection,[]).eligible,true);
  assert.equal(policy(protection,undefined).configurationKnown,false);
  assert.equal(policy(protection,[{type:'required_status_checks'}]).configurationKnown,false);
});
test('wrong app binding remains a failed exact server gate',()=>{
  const x=response();x.data.repository.ref.branchProtectionRule.requiredStatusChecks[0].app.databaseId=77;
  assert.equal(policy(projectProtection(x,scope).protection,[]).eligible,false);
});
test('older explicit bases require their own exact ref, rule, and base SHA',()=>{
  for(const base of ['codex/upstream-acceptance-base-20261119','codex/upstream-acceptance-base-20261119-v2']) {
    const x=response();x.data.repository.ref.name=base;x.data.repository.ref.branchProtectionRule.pattern=base;
    assert.equal(projectProtection(x,{...scope,base}).observation.base,base);
    assert.throws(()=>projectProtection(x,scope));
  }
});


test('missing context declarations cannot hide a configured binding',()=>{
  const x=response();x.data.repository.ref.branchProtectionRule.requiredStatusCheckContexts.pop();
  assert.throws(()=>projectProtection(x,scope),/declarations disagree/);
});
test('orphan context without a binding is not treated as an unbound app requirement',()=>{
  const x=response();x.data.repository.ref.branchProtectionRule.requiredStatusChecks.pop();
  assert.throws(()=>projectProtection(x,scope),/declarations disagree/);
});
test('equal context counts with different membership are rejected',()=>{
  const x=response();x.data.repository.ref.branchProtectionRule.requiredStatusCheckContexts[0]='other-gate';
  assert.throws(()=>projectProtection(x,scope),/declarations disagree/);
});
test('order-independent complete context and binding declarations are accepted',()=>{
  const x=response();x.data.repository.ref.branchProtectionRule.requiredStatusCheckContexts.reverse();
  const result=projectProtection(x,scope);
  assert.deepEqual(result.protection.required_status_checks.contexts,[...contexts].reverse());
  assert.deepEqual(result.protection.required_status_checks.checks.map(row=>row.context),contexts);
  assert.equal(policy(result.protection,[]).eligible,true);
});
