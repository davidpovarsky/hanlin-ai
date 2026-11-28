#!/usr/bin/env node
// Dispatch only the existing trusted-main consumer; never publish a check here.
import {execFileSync} from 'node:child_process';
import {mkdir,writeFile} from 'node:fs/promises';
import {dirname,resolve} from 'node:path';
import {planUpstreamProofDispatch,UPSTREAM_PROOF_PATH} from './upstream-proof-handoff.mjs';
import {ordinaryUpstreamEnvironment,PROTECTION_TOKEN_KEY} from './upstream-protection-access.mjs';

const [repository,number,output='build/upstream-updates/proof-handoff.json']=process.argv.slice(2);
if(repository!=='davidpovarsky/hanlin-ai'||!/^[1-9]\d*$/.test(number??'')
    || process.env.CANDIDATE_PR!==number || !/^[1-9]\d*$/.test(process.env.GITHUB_RUN_ID??'')
    || !/^[1-9]\d*$/.test(process.env.GITHUB_RUN_ATTEMPT??''))throw Error('Invalid bounded proof handoff arguments');
const file=resolve(output);
await mkdir(dirname(file),{recursive:true});
const environment=ordinaryUpstreamEnvironment();
const secrets=['GH_TOKEN','GITHUB_TOKEN','RENOVATE_TOKEN',PROTECTION_TOKEN_KEY].map(key=>process.env[key]).filter(Boolean);
const redact=value=>secrets.reduce((text,secret)=>text.replaceAll(secret,'[REDACTED]'),String(value??''));
const journal={schemaVersion:1,repository,producerRun:process.env.GITHUB_RUN_ID,
  producerAttempt:process.env.GITHUB_RUN_ATTEMPT,evaluatedAt:new Date().toISOString(),status:'NOT_DISPATCHED',actions:[]};
const api=(path,method='GET',body)=>{
  const args=['api','--hostname','github.com','repos/'+repository+'/'+path,'--method',method];
  if(body!==undefined)args.push('--input','-');
  const raw=execFileSync('gh',args,{env:environment,input:body===undefined?undefined:JSON.stringify(body),
    encoding:'utf8',stdio:['pipe','pipe','pipe'],timeout:15_000,maxBuffer:2_097_152});
  return raw.trim()?JSON.parse(raw):null;
};
try {
  const run=api('actions/runs/'+process.env.GITHUB_RUN_ID);
  const pr=api('pulls/'+number);
  const plan=planUpstreamProofDispatch({run,pr,environment:process.env});
  journal.plan=plan;
  if(plan.dispatch) {
    journal.status='DISPATCH_ATTEMPTED';
    journal.actions.push({kind:'dispatch-trusted-consumer',workflow:UPSTREAM_PROOF_PATH,ref:'main',inputs:plan.inputs});
    // One request only. An ambiguous transport failure is preserved, never retried.
    api('actions/workflows/'+encodeURIComponent(UPSTREAM_PROOF_PATH.split('/').at(-1))+'/dispatches',
      'POST',{ref:plan.ref,inputs:plan.inputs});
    journal.status='EXPLICIT_HANDOFF_ACCEPTED';
  } else {
    journal.status='WORKFLOW_RUN_DELIVERY_RETAINED';
  }
} catch(error) {
  journal.status='HANDOFF_REJECTED';journal.error=redact(error.message);process.exitCode=1;
} finally {
  await writeFile(file,JSON.stringify(journal,null,2)+'\n');
  console.log(JSON.stringify({status:journal.status,producerRun:journal.producerRun,receipt:file}));
}
