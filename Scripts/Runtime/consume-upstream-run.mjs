#!/usr/bin/env node
// Runs only trusted source; never checks out or executes candidate PR code.
import {execFileSync, spawnSync} from 'node:child_process';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {ACTIONS_APP_ID, PROOF_CHECK, isProtectedAcceptanceBase, candidateForRun, requireCandidateProof, mayEnableAutoMerge}
  from './upstream-run-consumer-policy.mjs';
import {selectUpstreamCheckLineage} from './upstream-check-lineage.mjs';

const [repository, runID, allowedBase, mode = 'inspect', allowAutoMerge = 'false',
  output = 'build/upstream-proof-consumer'] = process.argv.slice(2);
if (repository !== 'davidpovarsky/hanlin-ai' || !/^\d+$/.test(runID ?? '')
    || !isProtectedAcceptanceBase(allowedBase)
    || !['inspect', 'publish'].includes(mode) || !['false', 'true'].includes(allowAutoMerge))
  throw Error('Invalid bounded upstream consumer arguments');
if (mode === 'publish' && process.env.GITHUB_ACTIONS !== 'true')
  throw Error('Published proof checks require the GitHub Actions app identity');
if (mode === 'publish' && ![process.env.GITHUB_RUN_ID,process.env.GITHUB_RUN_ATTEMPT].every(value=>/^\d+$/.test(value??'')))
  throw Error('Published proof checks require an exact consumer run and attempt');
const directory = resolve(output);
await mkdir(directory, {recursive:true});
const journal = {schemaVersion:1, repository, runID, allowedBase, mode,
  evaluatedAt:new Date().toISOString(), status:'NOT_ACCEPTED', actions:[], mergePerformed:false, proofVerified:false};
const tokens = ['GH_TOKEN','GITHUB_TOKEN','RENOVATE_TOKEN'].map(key=>process.env[key]).filter(Boolean);
const redact = value => tokens.reduce((text,token)=>text.replaceAll(token,'[REDACTED]'),String(value));
const save = async () => writeFile(resolve(directory,'consumer-receipt.json'),JSON.stringify(journal,null,2)+'\n');
const api = (suffix, method = 'GET', body) => {
  const args = ['api', 'repos/'+repository+(suffix?'/'+suffix:''), '--method', method];
  if (body !== undefined) args.push('--input','-');
  return JSON.parse(execFileSync('gh',args,{input:body===undefined?undefined:JSON.stringify(body),
    encoding:'utf8',stdio:['pipe','pipe','pipe'],timeout:60_000,maxBuffer:4_194_304}));
};
let proofCheck;
let pr;
const finishCheck = async (conclusion, summary) => {
  if (!proofCheck) return;
  const result = api('check-runs/'+proofCheck.id,'PATCH',{status:'completed',conclusion,
    completed_at:new Date().toISOString(),
    output:{title:conclusion==='success'?'Authenticated current-head schema2 proof':'Candidate proof rejected',
      summary:summary.slice(0,60000)}});
  journal.actions.push({kind:'complete-proof-check',checkID:result.id,head:result.head_sha,conclusion:result.conclusion});
};
const checker = async (label, run) => {
  const file = resolve(directory,label+'.json');
  const result = spawnSync(process.execPath,[fileURLToPath(new URL('./check-upstream-merge-gate.mjs',import.meta.url)),
    repository,String(pr.number),file,runID],{encoding:'utf8',timeout:240_000,maxBuffer:4_194_304});
  await writeFile(resolve(directory,label+'.log'),redact((result.stdout??'')+'\n'+(result.stderr??'')));
  if (result.error || ![0,1].includes(result.status)) throw Error('Canonical evidence checker did not complete');
  const report = JSON.parse(await readFile(file,'utf8'));
  requireCandidateProof(report,pr,run);
  return report;
};
try {
  const run = api('actions/runs/'+runID);
  await writeFile(resolve(directory,'original-run.json'),JSON.stringify(run,null,2)+'\n');
  if (run.path !== '.github/workflows/check-runtime-dependency-updates.yml'
      || run.event !== 'workflow_dispatch') {
    journal.status='NOT_APPLICABLE'; journal.reason='Not the canonical candidate dispatch path';
  } else {
    const head = encodeURIComponent(repository.split('/')[0]+':'+run.head_branch);
    const pulls = api('pulls?state=open&head='+head+'&base='+encodeURIComponent(allowedBase)+'&per_page=100');
    pr = candidateForRun(run,pulls,repository,allowedBase);
    if (!pr) {
      journal.status='NOT_APPLICABLE'; journal.reason='No open current-head PR on the explicitly protected acceptance base';
    } else {
      journal.pullRequest=pr.number; journal.head=pr.head.sha; journal.baseSHA=pr.base.sha;
      journal.producerAttempt=run.run_attempt;
      const inventory=api('commits/'+pr.head.sha+'/check-runs?filter=latest&per_page=100');
      if(inventory.total_count>=100)throw Error('Incomplete current-head check inventory');
      await writeFile(resolve(directory,'raw-check-inventory.json'),JSON.stringify(inventory,null,2)+'\n');
      const lineage=selectUpstreamCheckLineage({rawChecks:inventory.check_runs,repository,head:pr.head.sha,
        proofRun:run,prNumber:pr.number,api});
      const {selectedChecks,...lineageSummary}=lineage;
      journal.checkLineage=lineageSummary;
      if(!lineage.producerMatchesProof)throw Object.assign(Error('A newer authenticated producer supersedes this completion event'),{code:'SUPERSEDED_PRODUCER'});

      if (mode === 'publish') {
        proofCheck = api('check-runs','POST',{name:PROOF_CHECK,head_sha:pr.head.sha,status:'in_progress',
          external_id:'upstream:'+runID+':'+run.run_attempt+':'+pr.number+':'+process.env.GITHUB_RUN_ID+':'+process.env.GITHUB_RUN_ATTEMPT,
          details_url:'https://github.com/'+repository+'/actions/runs/'+process.env.GITHUB_RUN_ID,started_at:new Date().toISOString(),
          output:{title:'Authenticating original upstream evidence',summary:'Checking exact HEAD/base, source diff, artifact digest and schema2 raw execution evidence.'}});
        if (proofCheck.app?.id !== ACTIONS_APP_ID || proofCheck.app?.slug !== 'github-actions')
          throw Error('Proof check was not created by the expected GitHub Actions app');
        journal.actions.push({kind:'create-proof-check',checkID:proofCheck.id,head:proofCheck.head_sha,appID:proofCheck.app.id});
        await save();
      }
      if (run.conclusion !== 'success') throw Error('Original candidate workflow '+(run.conclusion ?? run.status));
      await checker('candidate-proof',run);
      const current = api('pulls/'+pr.number);
      if (current.head.sha !== pr.head.sha || current.base.sha !== pr.base.sha || current.state !== 'open')
        throw Error('PR changed during evidence authentication');
      await finishCheck('success','Run '+runID+' attempt '+run.run_attempt+'; HEAD '+pr.head.sha+'; base '+pr.base.sha+'. The canonical consumer authenticated the digest-verified schema2 receipt and original raw Host execution/reuse evidence. This is scoped Host patch/minor acceptance, not native product or deployment acceptance.');
      proofCheck=null; // A later activation failure must not rewrite valid evidence.
      journal.status='VERIFIED_SCHEMA2_PROOF'; journal.proofVerified=true;
      if (allowAutoMerge === 'true' && mode === 'publish') {
        const settings = api('');
        if (settings.allow_auto_merge !== true) throw Error('Repository automatic merge is not enabled');
        const complete = await checker('all-required-gates',run);
        const current = api('pulls/'+pr.number);
        if (current.head.sha !== pr.head.sha || current.base.sha !== pr.base.sha
            || !mayEnableAutoMerge(complete,current,run))
          throw Error('Every current-head server-required gate must pass before activation');
        // Strict server checks invalidate the proof if either the candidate or
        // its protected base changes after this final identity check.
        // The original gh implementation binds expectedHeadOid in either mode:
        // ready PRs merge immediately; otherwise it enables protected auto-merge.
        // No administrator bypass or branch deletion flag is supplied.
        const args=['pr','merge',String(pr.number),'--repo',repository,'--auto','--squash',
          '--match-head-commit',pr.head.sha];
        const result=spawnSync('gh',args,{encoding:'utf8',timeout:60_000,maxBuffer:1_048_576});
        await writeFile(resolve(directory,'protected-auto-merge.log'),redact((result.stdout??'')+'\n'+(result.stderr??'')));
        if(result.error||result.status!==0)throw Error('GitHub rejected protected automatic merge');
        journal.actions.push({kind:'request-protected-auto-merge',head:pr.head.sha,baseSHA:pr.base.sha,
          expectedHeadOid:pr.head.sha,arguments:args});
        const after = api('pulls/'+pr.number);
        journal.mergePerformed=after.merged===true;
        journal.mergeCommit=after.merge_commit_sha;
        journal.autoMergeRequestPresent=after.auto_merge!=null;
        journal.status=after.merged?'MERGED_VERIFIED_SAFE_UPDATE':after.auto_merge!=null?'AUTO_MERGE_ENABLED_WITH_ALL_REQUIRED_GATES':'AUTO_MERGE_REQUESTED_AWAITING_READBACK';
      }
    }
  }
} catch (error) {
  if(error.code==='SUPERSEDED_PRODUCER') {
    journal.status='SUPERSEDED_PRODUCER'; journal.reason=redact(error.message);
  } else {
    journal.status='REJECTED'; journal.error=redact(error.message);
    try { await finishCheck('failure',journal.error); } catch(checkError) { journal.checkPublicationError=redact(checkError.message); }
    process.exitCode=1;
  }
} finally {
  await save();
  console.log(JSON.stringify({status:journal.status,pullRequest:journal.pullRequest??null,
    head:journal.head??null,mergePerformed:journal.mergePerformed,receipt:resolve(directory,'consumer-receipt.json')}));
}
