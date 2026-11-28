// Resolve only original upstream/proof check history through authenticated GitHub
// run-attempt and job identities. Other contexts remain untouched and fail closed.
const SOURCE_NAMES = new Set(['Hanlin upstream acceptance','upstream-validation / Hanlin upstream acceptance']);
const SOURCE_PATHS = new Set(['.github/workflows/check-runtime-dependency-updates.yml','.github/workflows/validate-app-split.yml']);
const PROOF_NAME='Hanlin upstream schema2 proof';
const APP_ID=15368;
const integer=value=>Number.isSafeInteger(value)&&value>0;

export function selectUpstreamCheckLineage({rawChecks,repository,head,proofRun,prNumber,api}) {
  if(!Array.isArray(rawChecks)||rawChecks.length>=100)throw Error('Incomplete check inventory');
  const cache=new Map();
  const attempt=(id,number)=>{
    const key=id+':'+number;
    if(!cache.has(key))cache.set(key,api('actions/runs/'+id+'/attempts/'+number));
    const run=cache.get(key);
    if(run.id!==id||run.run_attempt!==number||run.repository?.full_name!==repository
      ||run.head_repository?.full_name!==repository||!Number.isFinite(Date.parse(run.created_at)))
      throw Error('Unbound GitHub run-attempt identity');
    return run;
  };
  const owned=check=>check.app?.id===APP_ID&&check.app?.slug==='github-actions'&&check.head_sha===head;
  const sources=[];
  const proofs=[];
  for(const check of rawChecks) {
    if(!owned(check))continue;
    if(SOURCE_NAMES.has(check.name)) {
      const prefix='https://github.com/'+repository+'/actions/runs/';
      if(!check.details_url?.startsWith(prefix))throw Error('Unbound upstream check URL');
      const match=check.details_url.slice(prefix.length).match(/^(\d+)\/job\/(\d+)$/);
      if(!match)throw Error('Unbound upstream job URL');
      const runID=Number(match[1]),jobID=Number(match[2]);
      const job=api('actions/jobs/'+jobID);
      if(job.id!==jobID||job.run_id!==runID||!integer(job.run_attempt)||job.head_sha!==head
        ||job.name!==check.name||job.status!==check.status||job.conclusion!==check.conclusion||job.check_run_url!=='https://api.github.com/repos/'+repository+'/check-runs/'+check.id)
        throw Error('Upstream job/check binding mismatch');
      const run=attempt(runID,job.run_attempt);
      if(run.head_sha!==head||!SOURCE_PATHS.has(run.path)||run.event!=='workflow_dispatch'
        ||run.check_suite_id!==check.check_suite?.id)throw Error('Upstream source workflow binding mismatch');
      sources.push({check,run,attempt:job.run_attempt});
    } else if(check.name===PROOF_NAME) {
      const identity=check.external_id?.match(/^upstream:(\d+):(\d+):(\d+):(\d+):(\d+)$/);
      if(!identity)throw Error('Unbound independent proof identity');
      const [producerID,producerAttempt,number,consumerID,consumerAttempt]=identity.slice(1).map(Number);
      const consumerURL='https://github.com/'+repository+'/actions/runs/'+consumerID;
      const checkURL='https://github.com/'+repository+'/runs/'+check.id;
      // The authenticated Checks API may return its own canonical check page
      // after publication. That URL identifies the check, not the consumer run.
      // Keep the exact external-id tuple and authenticated run-attempt checks below.
      const canonicalCheckURL=integer(check.id)&&check.details_url===checkURL
        &&check.html_url===checkURL
        &&check.url==='https://api.github.com/repos/'+repository+'/check-runs/'+check.id;
      if(number!==prNumber||(check.details_url!==consumerURL&&!canonicalCheckURL))
        throw Error('Independent proof candidate/consumer mismatch');
      const producer=attempt(producerID,producerAttempt),consumer=attempt(consumerID,consumerAttempt);
      if(producer.head_sha!==head||!SOURCE_PATHS.has(producer.path)||producer.event!=='workflow_dispatch'
        ||consumer.path!=='.github/workflows/upstream-candidate-proof.yml'||consumer.head_branch!=='main'
        ||!['workflow_run','workflow_dispatch'].includes(consumer.event))
        throw Error('Independent proof source/consumer workflow mismatch');
      proofs.push({check,run:consumer,attempt:consumerAttempt,producerID,producerAttempt,
        urlForm:canonicalCheckURL?'GITHUB_CHECK_RUN_URL':'CONSUMER_RUN_URL'});
    }
  }
  const latest=(entries,label)=>{
    if(!entries.length)return null;
    const compare=(a,b)=>{
      if(a.run.id===b.run.id)return a.attempt-b.attempt;
      return Date.parse(a.run.created_at)-Date.parse(b.run.created_at);
    };
    let winner=entries[0];
    for(const item of entries.slice(1))if(compare(item,winner)>0)winner=item;
    if(entries.filter(item=>compare(item,winner)===0).length!==1)
      throw Error('Ambiguous authenticated '+label+' attempt');
    return winner;
  };
  const source=latest(sources,'upstream producer');
  if(!source)throw Error('No authenticated canonical upstream producer');
  const proof=latest(proofs.filter(item=>item.producerID===source.run.id
    &&item.producerAttempt===source.attempt),'proof consumer');
  const removedIDs=new Set([...sources,...proofs].map(item=>item.check.id));
  const selectedChecks=rawChecks.filter(check=>!removedIDs.has(check.id));
  selectedChecks.push(source.check);
  if(proof)selectedChecks.push(proof.check);
  return {
    status:'VERIFIED_GITHUB_RUN_ATTEMPT_LINEAGE',
    producerMatchesProof:source.run.id===proofRun.id&&source.attempt===proofRun.run_attempt,
    producer:{runID:source.run.id,attempt:source.attempt,checkID:source.check.id,
      status:source.check.status,conclusion:source.check.conclusion},
    proof:proof?{consumerRunID:proof.run.id,consumerAttempt:proof.attempt,checkID:proof.check.id,
      status:proof.check.status,conclusion:proof.check.conclusion,urlForm:proof.urlForm}:null,
    supersededCheckIDs:[...removedIDs].filter(id=>id!==source.check.id&&id!==proof?.check.id),
    authenticatedAttempts:[...cache.values()].map(run=>({id:run.id,attempt:run.run_attempt,path:run.path,
      head:run.head_sha,createdAt:run.created_at,status:run.status,conclusion:run.conclusion})),
    selectedChecks
  };
}
