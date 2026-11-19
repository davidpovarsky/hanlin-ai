// Delivery policy for the existing upstream producer and proof consumer.
export const UPSTREAM_PRODUCER_PATH='.github/workflows/check-runtime-dependency-updates.yml';
export const UPSTREAM_PROOF_PATH='.github/workflows/upstream-candidate-proof.yml';
const repositoryName='davidpovarsky/hanlin-ai';
const repositoryID=1295277723;
const workflowID=423297153;
const positive=value=>Number.isSafeInteger(value)&&value>0;
const sha=value=>/^[a-f0-9]{40}$/.test(value??'');
import {isProtectedAcceptanceBase} from './upstream-run-consumer-policy.mjs';

export function upstreamProofDeliveryRoute(actor) {
  if (!actor || !positive(actor.id) || typeof actor.login!=='string' || !actor.login
      || !['User','Bot'].includes(actor.type)) throw Error('Unknown producer actor identity');
  const reserved=actor.id===41898282 || actor.login==='github-actions[bot]';
  if (reserved && !(actor.id===41898282 && actor.login==='github-actions[bot]' && actor.type==='Bot'))
    throw Error('Inconsistent GitHub Actions actor identity');
  return reserved?'EXPLICIT_DISPATCH':'WORKFLOW_RUN';
}

export function authenticateUpstreamProducer(run,{repository,runID}) {
  if (repository!==repositoryName || !/^[1-9]\d*$/.test(String(runID??''))
      || !positive(run?.id) || String(run.id)!==String(runID)
      || run.repository?.full_name!==repository || run.repository?.id!==repositoryID
      || run.head_repository?.full_name!==repository || run.head_repository?.id!==repositoryID
      || run.workflow_id!==workflowID || run.path!==UPSTREAM_PRODUCER_PATH
      || run.event!=='workflow_dispatch' || !sha(run.head_sha) || !positive(run.run_attempt)
      || typeof run.head_branch!=='string' || !run.head_branch || /[\r\n]/.test(run.head_branch)
      || !Number.isFinite(Date.parse(run.created_at)))
    throw Error('Unbound canonical producer identity');
  const route=upstreamProofDeliveryRoute(run.actor);
  return {id:run.id,attempt:run.run_attempt,repository,repositoryID,workflowID,path:run.path,event:run.event,
    head:run.head_sha,branch:run.head_branch,createdAt:run.created_at,
    actor:{id:run.actor.id,login:run.actor.login,type:run.actor.type},route};
}

export function planUpstreamProofDispatch({run,pr,environment}) {
  const repository=environment.GITHUB_REPOSITORY;
  const identity=authenticateUpstreamProducer(run,{repository,runID:environment.GITHUB_RUN_ID});
  if (environment.GITHUB_ACTIONS!=='true' || environment.GITHUB_EVENT_NAME!=='workflow_dispatch'
      || !['candidate','failure-demo'].includes(environment.UPDATE_OPERATION)
      || String(identity.attempt)!==environment.GITHUB_RUN_ATTEMPT || identity.head!==environment.GITHUB_SHA
      || identity.actor.login!==environment.GITHUB_ACTOR || String(identity.actor.id)!==environment.GITHUB_ACTOR_ID
      || environment.GITHUB_WORKFLOW_REF!==repository+'/'+UPSTREAM_PRODUCER_PATH+'@refs/heads/'+identity.branch
      || environment.GITHUB_WORKFLOW_SHA!==identity.head || run.status!=='in_progress' || run.conclusion!==null)
    throw Error('Proof dispatch does not match this exact running producer attempt');
  if (!positive(pr?.number) || String(pr.number)!==environment.CANDIDATE_PR || pr.state!=='open' || pr.draft!==false
      || pr.head?.repo?.full_name!==repository || pr.base?.repo?.full_name!==repository
      || pr.head?.sha!==identity.head || pr.head?.ref!==identity.branch || !identity.branch.startsWith('codex/renovate/')
      || !isProtectedAcceptanceBase(pr.base.ref) || !sha(pr.base.sha))
    throw Error('Proof dispatch does not match an open exact-head protected candidate');
  return {dispatch:identity.route==='EXPLICIT_DISPATCH',route:identity.route,identity,
    pullRequest:pr.number,base:pr.base.ref,baseSHA:pr.base.sha,workflow:UPSTREAM_PROOF_PATH,ref:'main',
    inputs:{proof_run:String(identity.id),proof_attempt:String(identity.attempt)}};
}

export async function awaitUpstreamProducer({
  repository,runID,eventName,expectedAttempt,readRun,
  now=()=>performance.now(),delay=ms=>new Promise(resolve=>setTimeout(resolve,ms)),
  budgetMs=90_000,maxReads=20,intervalMs=3_000
}) {
  if (!['workflow_run','workflow_dispatch','local-inspect'].includes(eventName)
      || !Number.isFinite(budgetMs) || budgetMs<=0 || budgetMs>90_000
      || !positive(maxReads) || maxReads>20 || !Number.isFinite(intervalMs) || intervalMs<0 || intervalMs>5_000)
    throw Error('Invalid bounded proof-delivery context');
  const attempt=expectedAttempt===undefined||expectedAttempt===''?null:String(expectedAttempt);
  if (attempt!==null && (!/^[1-9]\d*$/.test(attempt)||!positive(Number(attempt))))
    throw Error('Invalid expected producer attempt');
  const started=now(),observations=[];
  let identity;
  const observation=()=>({eventName,expectedAttempt:attempt,identity:identity??null,
    reads:observations.length,elapsedMs:Math.max(0,now()-started),budgetMs,maxReads,observations:[...observations]});
  try {
    for(let index=0;index<maxReads;index++) {
      const remaining=budgetMs-(now()-started);
      if(remaining<=0)throw Error('Producer completion wait exceeded its deadline');
      const run=await readRun({timeoutMs:Math.max(1,Math.min(10_000,Math.floor(remaining)))});
      if(now()-started>=budgetMs)throw Error('Producer read exceeded the completion deadline');
      if(index===0 && (run?.path!==UPSTREAM_PRODUCER_PATH || run?.event!=='workflow_dispatch'))
        return {run,consume:false,reason:'Not the canonical candidate dispatch path',observation:observation()};
      const current=authenticateUpstreamProducer(run,{repository,runID});
      if(identity && JSON.stringify(current)!==JSON.stringify(identity))
        throw Error('Producer identity changed while waiting for completion');
      identity=current;
      observations.push({status:run.status,conclusion:run.conclusion,elapsedMs:Math.max(0,now()-started)});
      if(attempt!==null && String(identity.attempt)!==attempt)
        throw Error('Producer attempt does not match the triggering event or explicit handoff');
      if(eventName==='workflow_run') {
        if(attempt===null)throw Error('Automatic workflow_run proof requires its exact producer attempt');
        if(identity.route==='EXPLICIT_DISPATCH')
          return {run,consume:false,reason:'GitHub Actions producer uses the mutually exclusive explicit handoff',observation:observation()};
      }
      if(run.status==='completed') {
        if(typeof run.conclusion!=='string'||!run.conclusion)throw Error('Completed producer has no conclusion');
        return {run,consume:true,observation:observation()};
      }
      if(!['queued','in_progress','waiting','pending','requested'].includes(run.status) || run.conclusion!==null)
        throw Error('Unknown pending producer state');
      if(eventName!=='workflow_dispatch'||attempt===null)
        throw Error('Only an explicit attempt-bound handoff may wait for a pending producer');
      const remainingAfterRead=budgetMs-(now()-started);
      if(index+1>=maxReads || remainingAfterRead<=0)break;
      await delay(Math.min(intervalMs,remainingAfterRead));
    }
    throw Error('Producer completion wait exhausted its bounded reads');
  } catch(cause) {
    const error=Error(cause.message);
    error.deliveryObservation=observation();
    throw error;
  }
}
