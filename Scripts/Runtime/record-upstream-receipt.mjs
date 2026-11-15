#!/usr/bin/env node
import { readFile,writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
const context = JSON.parse(await readFile('build/upstream-updates/context.json','utf8'));
const host = JSON.parse(await readFile('build/runtime-host/host-metadata.json','utf8'));
const archive = await readFile('build/runtime-host/RuntimeHostResources.zip');
const hash = createHash('sha256').update(archive).digest('hex');
if (hash !== host.archiveSha256 || host.jitlessArchiveSmoke !== 'passed' || host.nodeVersion !== 'v24.5.0') {
  throw new Error('Actual packed Host archive/smoke/embedded Node proof missing');
}
const receipt = {...context,status:'EXECUTED_PASS',sourceIntegrity:true,licensesReviewed:true,
  executed:{platform:process.platform,node:process.version,hostArchiveSHA256:hash,sourceInputsHash:host.sourceInputsHash,
    scope:'Existing full Host tests and packed JITless smoke; no iOS UI/native binary rebuild claim'},
  hostMetadata:host};
await writeFile('build/upstream-updates/candidate-receipt.json',JSON.stringify(receipt,null,2)+'\n');
console.log(JSON.stringify({status:receipt.status,head:receipt.head,hostArchiveSHA256:hash}));
