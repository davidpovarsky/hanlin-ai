import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { accountHostExecution,freshHostLog,verifiedReceiptAccounting,HOST_REUSE_LINE } from '../upstream-host-accounting.mjs';
const run={repository:'owner/repo',runId:'123',attempt:'1',head:'1'.repeat(40),job:'upstream'};
const archiveSHA256='a'.repeat(64),sourceInputsHash='b'.repeat(64);
const nodeFingerprint={versions:{node:'24.5.0',v8:'fixture-version'},platform:'darwin',arch:'arm64'};
const freshLog=`> node --test Tests/*.test.mjs\nℹ tests 150\nℹ pass 149\nℹ fail 0\nℹ skipped 1\n`+
 JSON.stringify({passed:true,fetchImplementation:'original-probe-fixture',webAssemblyAvailable:false,contracts:['fixture']})+`\nPrepared RuntimeHostResources.zip (${archiveSHA256}).\n`;
const capture=(stage,credentials=false)=>({schemaVersion:1,stage,run:{...run},sourceInputsHash,nodeFingerprint,
 callerEnvironment:{repositoryCredentialsPresent:credentials,nonSecretInputHashes:{}},toolchain:{npm:'version',python:'version',git:'version',os:'version'}});
const entry=(stage,log,credentials=false)=>({stage,log,capture:capture(stage,credentials)});
const input=entries=>({run,archiveSHA256,sourceInputsHash,nodeFingerprint,hostMetadata:{archiveSha256:archiveSHA256,sourceInputsHash,nodeVersion:'v24.5.0',tests:'passed',jitlessArchiveSmoke:'passed'},entries});
test('actual direct execution is attributed to the Host stage and current run',()=>{
 const s=input([entry('native-origin','native binary only'),entry('host',freshLog)]);const r=accountHostExecution(s);
 assert.equal(r.accepted,true);assert.equal(r.origin.stage,'host');assert.equal(r.origin.counts.pass,149);
 assert.equal(r.directHostStage.status,'EXECUTED_PASS');assert.equal(r.repositoryCredentialFreeHostTests.status,'EXECUTED_PASS');
});
test('verified same-run reuse identifies the native-origin execution separately',()=>{
 const s=input([entry('native-origin',freshLog,true),entry('host',HOST_REUSE_LINE)]);const r=accountHostExecution(s);
 assert.equal(r.accepted,true);assert.equal(r.origin.stage,'native-origin');assert.equal(r.origin.status,'EXECUTED_PASS');
 assert.equal(r.directHostStage.status,'REUSED_VERIFIED_PASS');assert.equal(r.directHostStage.testsExecutedHere,false);
 assert.equal(r.repositoryCredentialFreeHostTests.status,'NOT_RUN');
});
test('reuse and passed metadata booleans without a verified execution origin remain UNKNOWN',()=>{
 const r=accountHostExecution(input([entry('native-origin',HOST_REUSE_LINE),entry('host',HOST_REUSE_LINE)]));
 assert.equal(r.accepted,false);assert.equal(r.status,'UNKNOWN');assert.equal(r.directHostStage.status,'NOT_RUN');
});
for(const [label,mutate] of [
 ['missing capture',s=>{s.entries[0].capture=null}],
 ['other run',s=>{s.entries[0].capture.run.runId='999'}],
 ['other attempt',s=>{s.entries[0].capture.run.attempt='2'}],
 ['other source head',s=>{s.entries[0].capture.run.head='2'.repeat(40)}],
 ['changed source inputs',s=>{s.entries[0].capture.sourceInputsHash='c'.repeat(64)}],
 ['changed Node fingerprint',s=>{s.entries[0].capture.nodeFingerprint={versions:{node:'24.22.1'}}}],
 ['wrong archive',s=>{s.archiveSHA256='d'.repeat(64)}],
 ['missing environment',s=>{delete s.entries[0].capture.callerEnvironment}],
 ['missing source hash',s=>{delete s.sourceInputsHash}],
 ['missing direct capture',s=>{s.entries[1].capture=null}],
 ['wrong counts',s=>{s.entries[0].log=freshLog.replace('pass 149','pass 148')}],
 ['missing packed probe',s=>{s.entries[0].log=freshLog.replace('"passed":true','"passed":false')}]
])test(`origin ${label} cannot authorize consumer acceptance`,()=>{
 const s=input([entry('native-origin',freshLog,true),entry('host',HOST_REUSE_LINE)]);mutate(s);
 assert.equal(accountHostExecution(s).accepted,false);
});
test('ambiguous duplicate fresh origins cannot authorize the archive',()=>{
 assert.equal(accountHostExecution(input([entry('native-origin',freshLog),entry('host',freshLog)])).accepted,false);
});
test('receipt consumer recomputes accounting from raw proof rather than trusting its accepted boolean',()=>{
 const s=input([entry('native-origin',freshLog,true),entry('host',HOST_REUSE_LINE)]);
 const receipt={schemaVersion:2,status:'EXECUTED_PASS',head:run.head,repository:run.repository,hostMetadata:s.hostMetadata,hostAccounting:accountHostExecution(s)};
 assert.equal(verifiedReceiptAccounting(receipt,s.entries),true);
 const changed=structuredClone(receipt);changed.hostAccounting.origin.counts.pass=150;
 assert.equal(verifiedReceiptAccounting(changed,s.entries),false);
 assert.equal(verifiedReceiptAccounting(receipt,[entry('host',HOST_REUSE_LINE)]),false);
 assert.equal(verifiedReceiptAccounting({...receipt,schemaVersion:1},s.entries),false);
});
test('original authenticated green log really executed150/149/0/1 in native-origin',async()=>{
 const raw=await readFile(new URL('../../../docs/ci/evidence/upstream-20261115/candidate-original-native-origin.log',import.meta.url),'utf8');
 const result=freshHostLog(raw,'de786941c6340de0ab9c6771181051954cb5120beb5af75e789a8ce61bba4b5a');
 assert.equal(result.counts.pass,149);assert.equal(result.counts.skipped,1);
 const later=await readFile(new URL('../../../docs/ci/evidence/upstream-20261115/candidate-host.log',import.meta.url),'utf8');
 assert.equal(freshHostLog(later,'de786941c6340de0ab9c6771181051954cb5120beb5af75e789a8ce61bba4b5a'),null);
});
