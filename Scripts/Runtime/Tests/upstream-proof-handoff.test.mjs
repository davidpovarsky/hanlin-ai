import test from 'node:test';
import assert from 'node:assert/strict';
import {upstreamProofDeliveryRoute,authenticateUpstreamProducer,planUpstreamProofDispatch,awaitUpstreamProducer,
  UPSTREAM_PRODUCER_PATH,UPSTREAM_PROOF_PATH} from '../upstream-proof-handoff.mjs';

const repo='davidpovarsky/hanlin-ai',runID='44455722821';
const head='c80f620ba8ed28243922728e00acffcdd439cc12';
const base='d6e2e3f062633fe7a55c0f44b922c5b3321aaf4a';
const branch='codex/renovate/2f561a5c9c1c/semver-7.x';
const bot={id:41898282,login:'github-actions[bot]',type:'Bot'};
const owner={id:202663769,login:'davidpovarsky',type:'User'};
const original={id:Number(runID),run_attempt:1,workflow_id:423297153,path:UPSTREAM_PRODUCER_PATH,
  repository:{id:1295277723,full_name:repo},head_repository:{id:1295277723,full_name:repo},
  event:'workflow_dispatch',head_sha:head,head_branch:branch,created_at:'2026-11-19T04:04:04Z',
  actor:bot,status:'in_progress',conclusion:null};
const pr={number:15,state:'open',draft:false,head:{sha:head,ref:branch,repo:{full_name:repo}},
  base:{sha:base,ref:'codex/upstream-acceptance-base-20261119-v3',repo:{full_name:repo}}};
const env={GITHUB_REPOSITORY:repo,GITHUB_ACTIONS:'true',GITHUB_EVENT_NAME:'workflow_dispatch',
  UPDATE_OPERATION:'candidate',CANDIDATE_PR:'15',GITHUB_RUN_ID:runID,GITHUB_RUN_ATTEMPT:'1',
  GITHUB_SHA:head,GITHUB_ACTOR:bot.login,GITHUB_ACTOR_ID:String(bot.id),
  GITHUB_WORKFLOW_REF:repo+'/'+UPSTREAM_PRODUCER_PATH+'@refs/heads/'+branch,GITHUB_WORKFLOW_SHA:head};
const complete=(extra={})=>({...structuredClone(original),status:'completed',conclusion:'success',...extra});

function waiting(sequence,extra={}) {
  let clock=0,index=0;
  const timeouts=[];
  const promise=awaitUpstreamProducer({repository:repo,runID,eventName:'workflow_dispatch',expectedAttempt:'1',
    now:()=>clock,delay:async ms=>{clock+=ms;},readRun:async ({timeoutMs})=>{
      timeouts.push(timeoutMs);
      return structuredClone(sequence[Math.min(index++,sequence.length-1)]);
    },...extra});
  return {promise,timeouts,reads:()=>index};
}

test('exact Actions bot and other authenticated actors have mutually exclusive routes',()=>{
  assert.equal(upstreamProofDeliveryRoute(bot),'EXPLICIT_DISPATCH');
  assert.equal(upstreamProofDeliveryRoute(owner),'WORKFLOW_RUN');
  assert.equal(upstreamProofDeliveryRoute({id:77,login:'another-app[bot]',type:'Bot'}),'WORKFLOW_RUN');
});
test('partial or inconsistent Actions bot identities are rejected',()=>{
  for(const actor of [{...bot,id:55},{...bot,login:'owner'},{...bot,type:'User'},
    {...owner,id:0},{...owner,type:'Organization'},null])
    assert.throws(()=>upstreamProofDeliveryRoute(actor),/identity/);
});
test('producer authentication binds repository ids, original workflow and immutable run fields',()=>{
  assert.equal(authenticateUpstreamProducer(original,{repository:repo,runID}).head,head);
  for(const extra of [{id:99},{workflow_id:99},{path:UPSTREAM_PROOF_PATH},{event:'push'},
    {head_sha:'bad'},{run_attempt:0},{head_branch:''},{created_at:'bad'},
    {repository:{id:99,full_name:repo}},{head_repository:{id:1295277723,full_name:'foreign/repo'}}])
    assert.throws(()=>authenticateUpstreamProducer({...original,...extra},{repository:repo,runID}),/identity/);
});
test('candidate and intentional failure bot attempts each plan one existing-main consumer dispatch',()=>{
  for(const operation of ['candidate','failure-demo']) {
    const plan=planUpstreamProofDispatch({run:original,pr,environment:{...env,UPDATE_OPERATION:operation}});
    assert.equal(plan.dispatch,true);assert.equal(plan.workflow,UPSTREAM_PROOF_PATH);assert.equal(plan.ref,'main');
    assert.deepEqual(plan.inputs,{proof_run:runID,proof_attempt:'1'});
    assert.equal(plan.baseSHA,base);assert.equal(plan.identity.head,head);
  }
});
test('owner-started producer retains automatic workflow_run without an explicit dispatch',()=>{
  const run={...original,actor:owner};
  const plan=planUpstreamProofDispatch({run,pr,environment:{...env,GITHUB_ACTOR:owner.login,GITHUB_ACTOR_ID:String(owner.id)}});
  assert.equal(plan.dispatch,false);assert.equal(plan.route,'WORKFLOW_RUN');
});
test('moved, foreign, closed, draft and unapproved PRs cannot dispatch',()=>{
  const cases=[{...pr,state:'closed'},{...pr,draft:true},{...pr,number:16},
    {...pr,head:{...pr.head,sha:'a'.repeat(40)}},{...pr,head:{...pr.head,ref:'main'}},
    {...pr,base:{...pr.base,ref:'main'}},{...pr,base:{...pr.base,repo:{full_name:'foreign/repo'}}}];
  for(const candidate of cases)
    assert.throws(()=>planUpstreamProofDispatch({run:original,pr:candidate,environment:env}),/protected candidate/);
});
test('a dispatch cannot borrow another run attempt, operation, actor or workflow source',()=>{
  for(const extra of [{GITHUB_RUN_ID:'99'},{GITHUB_RUN_ATTEMPT:'2'},{UPDATE_OPERATION:'renovate'},
    {GITHUB_SHA:'a'.repeat(40)},{GITHUB_ACTOR:'another'},{GITHUB_ACTOR_ID:'1'},
    {GITHUB_EVENT_NAME:'workflow_run'},{GITHUB_WORKFLOW_REF:'another/workflow'},
    {GITHUB_WORKFLOW_SHA:'a'.repeat(40)},{GITHUB_ACTIONS:'false'}])
    assert.throws(()=>planUpstreamProofDispatch({run:original,pr,environment:{...env,...extra}}));
  assert.throws(()=>planUpstreamProofDispatch({run:complete(),pr,environment:env}),/running producer/);
});
test('attempt-bound explicit delivery waits for authenticated completion',async()=>{
  const {promise,timeouts}=waiting([original,{...original,status:'queued'},complete()]);
  const result=await promise;
  assert.equal(result.consume,true);assert.equal(result.run.conclusion,'success');
  assert.equal(result.observation.reads,3);assert.equal(result.observation.elapsedMs,6000);
  assert.deepEqual(timeouts,[10000,10000,10000]);
});
test('the actual awaited producer read gates delivery before it resolves',async()=>{
  let release,settled=false;
  const held=new Promise(resolve=>{release=resolve;});
  const promise=awaitUpstreamProducer({repository:repo,runID,eventName:'workflow_dispatch',expectedAttempt:'1',
    readRun:()=>held,now:()=>0}).then(value=>{settled=true;return value;});
  await Promise.resolve();assert.equal(settled,false);
  release(complete());
  assert.equal((await promise).consume,true);assert.equal(settled,true);
});
test('a completed manual recovery remains compatible without a new optional attempt',async()=>{
  const result=await waiting([complete()],{expectedAttempt:undefined}).promise;
  assert.equal(result.consume,true);assert.equal(result.observation.reads,1);
});
test('a completed negative producer remains negative and is never converted to successful proof',async()=>{
  const result=await waiting([complete({conclusion:'failure'})]).promise;
  assert.equal(result.consume,true);assert.equal(result.run.conclusion,'failure');
});
test('automatic owner completion consumes once while automatic bot completion publishes nothing',async()=>{
  const ownerResult=await waiting([complete({actor:owner})],{eventName:'workflow_run'}).promise;
  assert.equal(ownerResult.consume,true);
  const botResult=await waiting([complete()],{eventName:'workflow_run'}).promise;
  assert.equal(botResult.consume,false);assert.match(botResult.reason,/mutually exclusive/);
});
test('automatic delivery requires the original event attempt and does not wait for a rerun',async()=>{
  await assert.rejects(waiting([complete({actor:owner})],{eventName:'workflow_run',expectedAttempt:undefined}).promise,/exact producer attempt/);
  await assert.rejects(waiting([{...original,actor:owner}],{eventName:'workflow_run'}).promise,/Only an explicit/);
  await assert.rejects(waiting([complete({run_attempt:2})],{eventName:'workflow_run'}).promise,/attempt does not match/);
});
test('a pending legacy manual request cannot silently attach to an unbound producer attempt',async()=>{
  await assert.rejects(waiting([original],{expectedAttempt:undefined}).promise,/attempt-bound/);
});
test('source identity changes during wait fail closed even if the later run is green',async()=>{
  for(const changed of [{head_sha:'a'.repeat(40)},{run_attempt:2},{head_branch:'codex/renovate/other'},
    {actor:owner},{created_at:'2026-11-19T04:05:00Z'},{repository:{id:9,full_name:repo}},
    {path:UPSTREAM_PROOF_PATH},{workflow_id:99}])
    await assert.rejects(waiting([original,complete(changed)]).promise,/identity/);
});
test('the triggering or explicit expected attempt must match even on immediate completion',async()=>{
  await assert.rejects(waiting([complete()],{expectedAttempt:'2'}).promise,/attempt does not match/);
  for(const attempt of ['0','01','bad','9007199254740992'])
    await assert.rejects(waiting([complete()],{expectedAttempt:attempt}).promise,/Invalid expected/);
});
test('unknown states and incomplete completion conclusions remain rejected',async()=>{
  await assert.rejects(waiting([{...original,status:'mystery'}]).promise,/Unknown pending/);
  await assert.rejects(waiting([{...original,conclusion:'success'}]).promise,/Unknown pending/);
  await assert.rejects(waiting([complete({conclusion:null})]).promise,/no conclusion/);
});
test('read count and monotonic deadline both bound pending delivery',async()=>{
  const bounded=waiting([original],{maxReads:3,intervalMs:0});
  await assert.rejects(bounded.promise,error=>{
    assert.match(error.message,/bounded reads/);assert.equal(error.deliveryObservation.reads,3);return true;
  });
  assert.equal(bounded.reads(),3);
  const deadline=waiting([original],{budgetMs:5,intervalMs:5});
  await assert.rejects(deadline.promise,/deadline/);
  assert.deepEqual(deadline.timeouts,[5]);
});
test('a slow API cannot return a late green result beyond the completion deadline',async()=>{
  let clock=0;
  await assert.rejects(awaitUpstreamProducer({repository:repo,runID,eventName:'workflow_dispatch',expectedAttempt:'1',
    budgetMs:100,now:()=>clock,readRun:({timeoutMs})=>{
      assert.equal(timeoutMs,100);clock=101;return complete();
    }}),/read exceeded/);
});
test('unrelated original workflows remain non-applicable without polling or check publication',async()=>{
  const result=await waiting([{...original,path:'.github/workflows/other.yml'}]).promise;
  assert.equal(result.consume,false);assert.match(result.reason,/Not the canonical/);
});
test('local inspection does not acquire an unbounded pending-run wait',async()=>{
  assert.equal((await waiting([complete()],{eventName:'local-inspect',expectedAttempt:undefined}).promise).consume,true);
  await assert.rejects(waiting([original],{eventName:'local-inspect'}).promise,/Only an explicit/);
});
test('delivery limits and origin events cannot be broadened by callers',async()=>{
  for(const extra of [{budgetMs:Infinity},{budgetMs:90001},{maxReads:21},{intervalMs:5001},{eventName:'push'}])
    await assert.rejects(waiting([complete()],extra).promise,/Invalid bounded/);
});
