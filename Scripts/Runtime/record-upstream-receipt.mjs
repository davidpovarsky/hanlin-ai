#!/usr/bin/env node
import { readFile,writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { accountHostExecution,currentRun,currentSourceInputs } from './upstream-host-accounting.mjs';
const context = JSON.parse(await readFile('build/upstream-updates/context.json','utf8'));
const host = JSON.parse(await readFile('build/runtime-host/host-metadata.json','utf8'));
const archive = await readFile('build/runtime-host/RuntimeHostResources.zip');
const hash = createHash('sha256').update(archive).digest('hex');
if (hash !== host.archiveSha256 || host.jitlessArchiveSmoke !== 'passed' || host.nodeVersion !== 'v24.5.0') {
  throw new Error('Actual packed Host archive/smoke/embedded Node proof missing');
}
const run=currentRun();
if(run.head!==context.head || run.repository!==context.repository)throw Error('Receipt/context/current-run identity mismatch');
const nodeFingerprint={versions:process.versions,platform:process.platform,arch:process.arch};
const entries=[];
for(const stage of ['native-origin','host']) {
  const log=await readFile(`build/upstream-updates/${stage}.log`,'utf8').catch(()=>null);
  const capture=await readFile(`build/upstream-updates/${stage}-context.json`,'utf8').then(JSON.parse).catch(()=>null);
  entries.push({stage,log,capture});
}
const currentInputHash=currentSourceInputs(nodeFingerprint);
const hostAccounting=accountHostExecution({run,archiveSHA256:hash,sourceInputsHash:currentInputHash,nodeFingerprint,hostMetadata:host,entries});
const receipt = {...context,schemaVersion:2,status:hostAccounting.status,hostAccounting,sourceIntegrity:true,licensesReviewed:true,
  verification:{platform:process.platform,node:process.version,hostArchiveSHA256:hash,currentSourceInputsHash:currentInputHash,metadataSourceInputsHash:host.sourceInputsHash,
    scope:'Current-run authenticated execution origin is in hostAccounting; direct Host-stage reuse is reported separately; no iOS UI/native binary rebuild claim'},
  hostMetadata:host};
await writeFile('build/upstream-updates/candidate-receipt.json',JSON.stringify(receipt,null,2)+'\n');
console.log(JSON.stringify({status:receipt.status,head:receipt.head,hostArchiveSHA256:hash}));

if(!hostAccounting.accepted)process.exitCode=1;
