#!/usr/bin/env node
// Evidence accounting only. Never runs Host tests, mutates a runtime or changes permissions.
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { writeFile,mkdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { verifiedLocalMacReceiptAccounting } from './local-mac-host-accounting.mjs';
export { accountLocalMacHostExecution, localMacHostLog, LOCAL_MAC_HOST_COUNTS } from './local-mac-host-accounting.mjs';
export const digest = value => createHash('sha256').update(value).digest('hex');
export const EXPECTED_HOST_COUNTS = Object.freeze({tests:153,pass:152,fail:0,skipped:1});
const stages=['native-origin','host'];
export const HOST_REUSE_LINE='Reusing verified current RuntimeHostResources.zip and its completed Host/JITless checks.';
const sha256=value=>/^[a-f0-9]{64}$/.test(value??'');
const same = (a,b) => JSON.stringify(a) === JSON.stringify(b);
const validRun = run => /^[1-9][0-9]*$/.test(run?.runId??'') && /^[1-9][0-9]*$/.test(run?.attempt??'') && /^[a-f0-9]{40}$/.test(run?.head??'')
  && /^[\w.-]+\/[\w.-]+$/.test(run?.repository??'') && typeof run?.job === 'string' && run.job.length>0;
export function freshHostLog(log,archiveSHA256) {
  const counts={};
  for(const match of log.matchAll(/^ℹ (tests|pass|fail|skipped) (\d+)\s*$/gm)) {
    if(Object.hasOwn(counts,match[1]))return null; // Multiple/ambiguous suites cannot qualify.
    counts[match[1]]=Number(match[2]);
  }
  const prepared=[...log.matchAll(/^Prepared RuntimeHostResources\.zip \(([a-f0-9]{64})\)\.\s*$/gm)];
  const probes=log.split(/\r?\n/).flatMap(line=>{try{return [JSON.parse(line)];}catch{return [];}})
    .filter(value=>value?.passed===true && value.fetchImplementation && value.webAssemblyAvailable===false && Array.isArray(value.contracts));
  if(!same(counts,EXPECTED_HOST_COUNTS) || prepared.length!==1 || prepared[0][1]!==archiveSHA256 || probes.length!==1
      || !log.includes('> node --test Tests/*.test.mjs'))return null;
  return {counts,packedJitlessProbe:probes[0],logSHA256:digest(log)};
}
export function accountHostExecution({run,archiveSHA256,sourceInputsHash,nodeFingerprint,hostMetadata,entries=[]}) {
  const reasons=[];
  if(!validRun(run))reasons.push('MISSING_CURRENT_RUN_IDENTITY');
  if(!sha256(archiveSHA256)||!sha256(sourceInputsHash))reasons.push('MISSING_ARCHIVE_OR_SOURCE_FINGERPRINT');
  if(hostMetadata?.archiveSha256!==archiveSHA256 || hostMetadata?.sourceInputsHash!==sourceInputsHash
      || hostMetadata?.tests!=='passed' || hostMetadata?.jitlessArchiveSmoke!=='passed' || hostMetadata?.nodeVersion!=='v24.5.0' || nodeFingerprint?.versions?.node!=='24.5.0')reasons.push('HOST_ARCHIVE_INPUT_OR_TOOLCHAIN_MISMATCH');
  const origins=[];
  const validCapture=entry=>stages.includes(entry.stage) && entry.capture?.schemaVersion===1
    && entry.capture.stage===entry.stage && same(entry.capture.run,run)
    && entry.capture.sourceInputsHash===sourceInputsHash && same(entry.capture.nodeFingerprint,nodeFingerprint)
    && typeof entry.capture.callerEnvironment?.repositoryCredentialsPresent==='boolean'
    && entry.capture.callerEnvironment.nonSecretInputHashes && ['npm','python','git','os'].every(key=>typeof entry.capture.toolchain?.[key]==='string' && entry.capture.toolchain[key].length>0);

  for(const entry of entries) {
    const capture=entry.capture;
    const valid=validCapture(entry);
    const fresh=freshHostLog(entry.log??'',archiveSHA256);
    if(valid && fresh)origins.push({status:'EXECUTED_PASS',stage:entry.stage,run,...fresh,
      archiveSHA256,sourceInputsHash,nodeFingerprint,callerEnvironment:capture.callerEnvironment,toolchain:capture.toolchain,
      captureSHA256:digest(JSON.stringify(capture))});
  }
  if(origins.length!==1)reasons.push('MISSING_OR_AMBIGUOUS_AUTHENTICATED_CURRENT_RUN_EXECUTION');
  const direct=entries.filter(entry=>entry.stage==='host');
  if(direct.length!==1 || !validCapture(direct[0]) || !(freshHostLog(direct[0].log??'',archiveSHA256)
      || direct[0].log?.trim()===HOST_REUSE_LINE)) {
    reasons.push('MISSING_OR_UNVERIFIED_DIRECT_HOST_STAGE');
  }
  const accepted=reasons.length===0;
  const origin=accepted?origins[0]:null;
  const reused=direct.length===1 && !freshHostLog(direct[0].log??'',archiveSHA256) && direct[0].log?.trim()===HOST_REUSE_LINE;
  // A cache boolean or reuse message alone never supplies an execution origin.
  return {schemaVersion:1,accepted,status:accepted?'EXECUTED_PASS':'UNKNOWN',reasons,origin,
    directHostStage:{status:accepted?(reused?'REUSED_VERIFIED_PASS':'EXECUTED_PASS'):'NOT_RUN',
      testsExecutedHere:accepted && !reused,source:origin?{run:origin.run,stage:origin.stage,logSHA256:origin.logSHA256}:null},
    repositoryCredentialFreeHostTests:{status:origin?.callerEnvironment?.repositoryCredentialsPresent===false?'EXECUTED_PASS':'NOT_RUN'},
    crossRunReuse:'NOT_ACCEPTED_WITHOUT_A_SEPARATE_AUTHENTICATED_ORIGIN_AND_COMPLETE_UNCHANGED_INPUT_CLOSURE'};
}
export function verifiedReceiptAccounting(receipt,entries,authentication) {
  if(receipt?.schemaVersion===3)return verifiedLocalMacReceiptAccounting(receipt,entries,authentication);
  const accounting=receipt?.hostAccounting;
  if(receipt?.schemaVersion!==2 || receipt.status!=='EXECUTED_PASS' || accounting?.accepted!==true
      || accounting.status!=='EXECUTED_PASS' || !validRun(accounting.origin?.run)
      || accounting.origin.run.head!==receipt.head || accounting.origin.run.repository!==receipt.repository
      || !Array.isArray(entries))return false;
  const recomputed=accountHostExecution({run:accounting.origin.run,archiveSHA256:receipt.hostMetadata?.archiveSha256,
    sourceInputsHash:receipt.hostMetadata?.sourceInputsHash,nodeFingerprint:accounting.origin.nodeFingerprint,
    hostMetadata:receipt.hostMetadata,entries});
  return recomputed.accepted && same(recomputed,accounting);
}
export function currentRun() {
  return {repository:process.env.GITHUB_REPOSITORY,runId:process.env.GITHUB_RUN_ID,attempt:process.env.GITHUB_RUN_ATTEMPT,head:process.env.GITHUB_SHA,job:process.env.GITHUB_JOB};
}
export function currentSourceInputs(nodeFingerprint) {
  const python=process.platform==='win32'?'py':'python3';
  const args=[...(process.platform==='win32'?['-3']:[]),'Scripts/Runtime/runtime_host_archive.py','fingerprint','--node-fingerprint',JSON.stringify(nodeFingerprint)];
  return execFileSync(python,args,{encoding:'utf8',stdio:['ignore','pipe','pipe']}).trim();
}
if(process.argv[1] && import.meta.url===pathToFileURL(resolve(process.argv[1])).href) {
  const [operation,stage]=process.argv.slice(2);
  if(operation!=='capture'||!stages.includes(stage))throw Error('Expected capture native-origin|host');
  const run=currentRun();if(!validRun(run))throw Error('Trusted current CI run identity is required');
  const nodeFingerprint={versions:process.versions,platform:process.platform,arch:process.arch};
  const hashes={};for(const key of ['PATH','NODE_OPTIONS','NODE_EXTRA_CA_CERTS','TZ','LANG','LC_ALL','RUNNER_TEMP','TMPDIR','HOME','NODE_PATH','HANLIN_RUN_LONG_JOBS','HANLIN_RUNTIME_TEST_FIXTURES','HANLIN_HOST_GRAMMAR_COMPILER_ROOT']) {
    hashes[key]=process.env[key]===undefined?null:digest(process.env[key]);
  }
  const version=(cmd,args=[])=>execFileSync(cmd,args,{encoding:'utf8',stdio:['ignore','pipe','pipe']}).trim();
  const capture={schemaVersion:1,stage,run,nodeFingerprint,sourceInputsHash:currentSourceInputs(nodeFingerprint),
    capturedAt:new Date().toISOString(),callerEnvironment:{nonSecretInputHashes:hashes,
      repositoryCredentialsPresent:!!(process.env.GH_TOKEN||process.env.GITHUB_TOKEN||process.env.RENOVATE_TOKEN),
      hostChildEnvironment:'Derived by the fingerprinted prepare-runtime-host.sh; not a claim that the caller environment equals the child environment'},
    toolchain:{npm:version('npm',['--version']),python:version('python3',['--version']),git:version('git',['--version']),os:version('sw_vers')}};
  await mkdir('build/upstream-updates',{recursive:true});
  await writeFile(`build/upstream-updates/${stage}-context.json`,JSON.stringify(capture,null,2)+'\n');
}
