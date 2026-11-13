import test from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createHash, randomUUID } from 'node:crypto';
import { ExecutionJobs } from '../execution-jobs.mjs';

async function fixture(t) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-jobs-'));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const jobs = new ExecutionJobs({ root: path.join(root, 'jobs'), workerURL: new URL('../execution-worker.mjs', import.meta.url) });
  await jobs.initialize();
  return { jobs, root, body: { workspace: root, moduleKind: 'esm', maximumOutputBytes: 4096 } };
}

test('Host-generated child job identity reaches input validation and its durable receipt', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-implicit-job-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const validated = [];
  const jobs = new ExecutionJobs({root: path.join(root, 'jobs'), workerURL: new URL('../execution-worker.mjs', import.meta.url),
    validateInput: async body => {
      assert.match(body.executionID ?? '', /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/);
      validated.push(body.executionID);
      return body;
    }});
  await jobs.initialize();
  // Lifecycle children are created by the Host, without a Swift-issued UUID.
  const header = await jobs.start({source: 'export default "implicit-child";', moduleKind: 'esm', workspace: root});
  const completed = await jobs.wait(header.executionID);
  assert.deepEqual(validated, [header.executionID]);
  assert.equal(completed.state, 'completed');
  assert.equal(completed.result.value, 'implicit-child');
  const reopened = new ExecutionJobs({root: path.join(root, 'jobs'), workerURL: new URL('../execution-worker.mjs', import.meta.url)});
  await reopened.initialize();
  assert.equal(reopened.snapshot(header.executionID).result.value, 'implicit-child');
});

test('actual Worker interruption retains its cause and full output through reopen', async t => {
  const {jobs,root,body} = await fixture(t);
  const header = await jobs.start({...body,source:"console.log('שלום partial output'); await new Promise(() => setInterval(() => {}, 1000));"});
  const deadline = performance.now()+15000;
  while (!jobs.snapshot(header.executionID).stdoutBytes) {
    assert.ok(performance.now()<deadline,'The actual Worker never produced its output');
    await new Promise(resolve=>setTimeout(resolve,10));
  }
  const reason = 'Background continuation ended before this job completed.';
  await jobs.interrupt(header.executionID,reason);
  const ended = await jobs.wait(header.executionID);
  assert.equal(ended.state,'interrupted');
  assert.equal(ended.interruptionReason,reason);
  assert.equal(ended.error,reason);
  assert.match(ended.result.stdout,/שלום partial output/);
  const artifact=ended.result.outputFiles.stdout;
  const bytes=await fs.readFile(artifact.path);
  assert.equal(bytes.length,artifact.bytes);
  assert.equal(createHash('sha256').update(bytes).digest('hex'),artifact.sha256);
  const reopened=new ExecutionJobs({root:path.join(root,'jobs'),workerURL:new URL('../execution-worker.mjs',import.meta.url)});
  await reopened.initialize();
  await reopened.interrupt(header.executionID,'A later unrelated cause');
  assert.equal(reopened.snapshot(header.executionID).interruptionReason,reason);
  await assert.rejects(reopened.start({...body,executionID:header.executionID,source:"throw Error('must never replay');"}),error=>error.status===409);
});

test('late Host operation completion cannot erase an already requested system interruption', async t => {
  const {jobs,body} = await fixture(t);
  let release;
  const gate=new Promise(resolve=>release=resolve);
  let began;
  const started=new Promise(resolve=>began=resolve);
  const header=await jobs.startOperation({},async({emit})=>{emit({phase:'actual operation started'});began();await gate;return {lateValue:'retained'};});
  await started;
  const reason='The system ended the background continuation.';
  await jobs.interrupt(header.executionID,reason);
  release();
  const ended=await jobs.wait(header.executionID);
  assert.equal(ended.state,'interrupted');assert.equal(ended.error,reason);
  assert.deepEqual(ended.result.value,{lateValue:'retained'});
  assert.equal(ended.result.exitCode,1);
  assert.ok(ended.result.outputFiles.stdout.bytes>0);
  const complete=await jobs.start({...body,source:'export default 42;'});
  await jobs.wait(complete.executionID);
  await jobs.interrupt(complete.executionID,'Too late');
  assert.equal(jobs.snapshot(complete.executionID).state,'completed');
  assert.equal(jobs.snapshot(complete.executionID).interruptionReason,undefined);
});

test('interruption before POST or during journal creation cannot start or replay side effects', async t => {
  const {jobs,root,body}=await fixture(t);
  const beforeID=randomUUID(), reason='Continuation ended before native submission';
  await jobs.interrupt(beforeID,reason);
  assert.equal(jobs.snapshot(beforeID).neverStarted,true);
  await assert.rejects(jobs.start({...body,executionID:beforeID,source:'throw Error("must not execute");'}),error=>error.status===409);
  const marker=path.join(root,'must-not-exist.txt');
  const duringID=randomUUID();
  const starting=jobs.start({...body,executionID:duringID,source:`import fs from 'node:fs';fs.writeFileSync(${JSON.stringify(marker)},'side effect');`});
  const cancelling=jobs.interrupt(duringID,reason);
  await Promise.all([starting,cancelling]);
  const ended=await jobs.wait(duringID);
  assert.equal(ended.state,'interrupted');
  assert.equal(ended.interruptionReason,reason);
  await assert.rejects(fs.stat(marker),error=>error.code==='ENOENT');
  const operationID=randomUUID(); let ran=false;
  const staging=jobs.startOperation({executionID:operationID},async()=>{ran=true;return 'must not run';});
  await Promise.all([staging,jobs.interrupt(operationID,reason)]);
  assert.equal((await jobs.wait(operationID)).state,'interrupted');
  assert.equal(ran,false);
  const reopened=new ExecutionJobs({root:path.join(root,'jobs'),workerURL:new URL('../execution-worker.mjs',import.meta.url)});
  await reopened.initialize();
  assert.equal(reopened.snapshot(beforeID).neverStarted,true);
  await assert.rejects(reopened.start({...body,executionID:beforeID,source:'throw Error("must not replay");'}),error=>error.status===409);
});

for (const moduleKind of ['esm','commonjs']) {
  test(`${moduleKind} resolves workspace modules and local exports before pinned global packages`, async t => {
    const {jobs,root,body} = await fixture(t);
    const globalModules=path.join(root,'global','node_modules');
    jobs.globalNodeModules=globalModules;
    const local=path.join(root,'node_modules','fixture');
    const global=path.join(globalModules,'fixture');
    const fallback=path.join(globalModules,'global-only');
    for(const directory of [local,global,fallback]) await fs.mkdir(directory,{recursive:true});
    for(const [directory,value] of [[local,'new-staged'],[global,'old-global'],[fallback,'fallback']]) {
      await fs.writeFile(path.join(directory,'package.json'),JSON.stringify({name:path.basename(directory),version:'1.0.0',
        exports:{import:'./import.mjs',require:'./require.cjs'}}));
      await fs.writeFile(path.join(directory,'import.mjs'),`export default ${JSON.stringify(value+'-import')};`);
      await fs.writeFile(path.join(directory,'require.cjs'),`module.exports=${JSON.stringify(value+'-require')};`);
    }
    await fs.writeFile(path.join(root,'sibling.mjs'),"export default 'relative';");
    await fs.writeFile(path.join(root,'sibling.cjs'),"module.exports='relative';");
    const source=moduleKind==='esm'
      ? "import local from 'fixture'; import global from 'global-only'; import sibling from './sibling.mjs'; export default {local,global,sibling,directory: new URL('.',import.meta.url).pathname};"
      : "module.exports={local:require('fixture'),global:require('global-only'),sibling:require('./sibling.cjs'),directory:__dirname};";
    const header=await jobs.start({...body,moduleKind,source});
    const job=await jobs.wait(header.executionID);
    assert.equal(job.state,'completed',JSON.stringify(job));
    assert.equal(job.result.value.local,`new-staged-${moduleKind==='esm'?'import':'require'}`);
    assert.equal(job.result.value.global,`fallback-${moduleKind==='esm'?'import':'require'}`);
    assert.equal(job.result.value.sibling,'relative');
    assert.ok(job.result.value.directory.replaceAll('\\','/').includes(path.basename(root)));
    // A broken local package may not quietly use the old global version.
    await fs.rm(path.join(local,moduleKind==='esm'?'import.mjs':'require.cjs'));
    const broken=await jobs.start({...body,moduleKind,source});
    const failed=await jobs.wait(broken.executionID);
    assert.equal(failed.state,'failed');
    assert.doesNotMatch(failed.result.stdout,/old-global/);
  });
}

test('managed CLI preload does not configure or leak its private bootstrap into nested Workers',async t=>{
  const {jobs,root,body}=await fixture(t);
  const entryPoint=path.join(root,'nested.cjs');
  await fs.writeFile(entryPoint,`
    const {Worker}=require('node:worker_threads');
    if((process.env.NODE_OPTIONS??'').includes('cli-preload'))throw new Error('private bootstrap leaked');
    const worker=new Worker("require('node:worker_threads').parentPort.postMessage('NESTED_OK')",{eval:true});
    worker.on('message',value=>console.log(value));
  `);
  const header=await jobs.start({...body,executionMode:'cli',entryPoint});
  const job=await jobs.wait(header.executionID);
  assert.equal(job.state,'completed',JSON.stringify(job));
  assert.match(job.result.stdout,/NESTED_OK/);
});

test('Host command wait wakes for actual requests and aborts without cancelling the execution',async t=>{
  const {jobs,root,body}=await fixture(t);
  const aborted=new AbortController();
  const empty=jobs.waitForCommandRequests(aborted.signal);aborted.abort();
  assert.deepEqual(await empty,[]);
  const waiting=jobs.waitForCommandRequests();
  const source=`import {executePortableShell} from ${JSON.stringify(new URL('../portable-shell.mjs',import.meta.url).href)};
    await executePortableShell('node fixture.cjs',[],{cwd:process.cwd(),environment:process.env});`;
  const header=await jobs.start({...body,source});
  const requests=await waiting;
  assert.equal(requests.length,1);assert.equal(requests[0].parentExecutionID,header.executionID);
  assert.equal(jobs.snapshot(header.executionID).state,'running');
  const response=path.join(path.dirname(requests[0].standardInputPath),'response.json');
  await fs.writeFile(response,JSON.stringify({exitCode:0}));
  assert.equal((await jobs.wait(header.executionID)).state,'completed');
  assert.deepEqual(await jobs.allCommandRequests(),[]);
  const controller=new AbortController();
  const next=jobs.waitForCommandRequests(controller.signal);controller.abort();
  assert.deepEqual(await next,[]);
});

test('full stdout and stderr survive preview limits and store reopen with verified hashes', async t => {
  const { jobs, root, body } = await fixture(t);
  const text = 'שלום 👨‍👩‍👧‍👦\n'.repeat(400_000);
  const header = await jobs.start({ ...body, source: `const text = 'שלום 👨‍👩‍👧‍👦\\n'.repeat(400000); process.stdout.write(text); process.stderr.write('tail stderr'); export default 42;` });
  const completed = await jobs.wait(header.executionID);
  assert.equal(completed.state, 'completed', JSON.stringify(completed));
  assert.equal(completed.result.value, 42);
  assert.equal(completed.result.outputWasTruncated, true);
  const actual = await fs.readFile(completed.result.outputFiles.stdout.path);
  assert.ok(actual.length > 10 * 1024 * 1024);
  assert.equal(actual.toString('utf8'), text);
  assert.equal(completed.result.outputFiles.stdout.sha256, createHash('sha256').update(text).digest('hex'));
  assert.equal(await fs.readFile(completed.result.outputFiles.stderr.path, 'utf8'), 'tail stderr');
  const reopened = new ExecutionJobs({ root: path.join(root, 'jobs'), workerURL: new URL('../execution-worker.mjs', import.meta.url) });
  await reopened.initialize();
  assert.equal(reopened.snapshot(header.executionID).state, 'completed');
  const parts = [];
  let offset = 0;
  while (true) {
    const page = await reopened.readOutput(header.executionID, 'stdout', offset, 4093);
    parts.push(Buffer.from(page.base64, 'base64'));
    if (!page.hasMore) break;
    offset = page.nextOffset;
  }
  assert.equal(Buffer.concat(parts).toString('utf8'), text);
  await assert.rejects(jobs.start({ ...body, executionID: header.executionID, source: 'throw new Error("replayed")' }), /already exists/);
});

test('ordinary event-loop work finishes after module evaluation without being terminated early', async t => {
  const { jobs, body } = await fixture(t);
  const started = Date.now();
  const header = await jobs.start({ ...body, source: `setTimeout(() => console.log('ASYNC_TIMER_COMPLETE'), 120); export default 'loaded';` });
  const completed = await jobs.wait(header.executionID);
  assert.equal(completed.state, 'completed');
  assert.ok(Date.now() - started >= 120);
  assert.match(completed.result.stdout, /ASYNC_TIMER_COMPLETE/);
});

test('explicit timeout retains partial output and is distinct from user cancellation', async t => {
  const { jobs, body } = await fixture(t);
  const header = await jobs.start({ ...body, timeoutMilliseconds: 1500, source: `console.log('BEFORE_TIMEOUT'); await new Promise(resolve => setTimeout(resolve, 60000));` });
  const completed = await jobs.wait(header.executionID);
  assert.equal(completed.state, 'failed');
  assert.equal(completed.result.didTimeOut, true);
  assert.equal(completed.result.wasCancelled, false);
  assert.match(await fs.readFile(completed.result.outputFiles.stdout.path, 'utf8'), /BEFORE_TIMEOUT/);
});

test('explicit cancellation terminates the actual worker and retains partial output', async t => {
  const { jobs, body } = await fixture(t);
  const header = await jobs.start({ ...body, source: `console.log('BEFORE_CANCEL'); await new Promise(resolve => setTimeout(resolve, 60000));` });
  while (jobs.snapshot(header.executionID).stdoutBytes === 0) await new Promise(resolve => setTimeout(resolve, 10));
  await jobs.cancel(header.executionID);
  const completed = await jobs.wait(header.executionID);
  assert.equal(completed.state, 'cancelled');
  assert.equal(completed.result.wasCancelled, true);
  assert.equal(completed.result.didTimeOut, false);
  assert.match(await fs.readFile(completed.result.outputFiles.stdout.path, 'utf8'), /BEFORE_CANCEL/);
});

test('actual Node job crosses 300 seconds with no hidden deadline', { skip: process.env.HANLIN_RUN_LONG_JOBS !== '1' }, async t => {
  const { jobs, body } = await fixture(t);
  const start = performance.now();
  const header = await jobs.start({ ...body, source: `console.log('LONG_JOB_STARTED'); await new Promise(resolve => setTimeout(resolve, 305000)); console.log('LONG_JOB_COMPLETED'); export default 305;` });
  const completed = await jobs.wait(header.executionID);
  const elapsed = performance.now() - start;
  assert.ok(elapsed > 300000, String(elapsed));
  assert.equal(completed.state, 'completed');
  assert.equal(completed.result.value, 305);
  assert.match(completed.result.stdout, /LONG_JOB_COMPLETED/);
  console.log(JSON.stringify({ proof: 'actual-node-job-over-300-seconds', elapsedMilliseconds: elapsed, executionID: header.executionID }));
});

test('a later nonzero exit cannot be hidden by an earlier successful module export', async t => {
  const { jobs, body } = await fixture(t);
  const header = await jobs.start({ ...body, source: `process.exitCode = 23; export default 'module loaded';` });
  const result = await jobs.wait(header.executionID);
  assert.equal(result.state, 'failed');
  assert.equal(result.result.exitCode, 23);
});


test('user worker messages cannot hide the final module result', async t => {
  const { jobs, body } = await fixture(t);
  const header = await jobs.start({ ...body, source: `import { parentPort } from 'node:worker_threads'; parentPort.postMessage({ user: 'progress' }); export default 73;` });
  const result = await jobs.wait(header.executionID);
  assert.equal(result.state, 'completed');
  assert.equal(result.result.value, 73);
});

test('a restored job with no opened streams has an empty lossless output page', async t => {
  const { jobs, root } = await fixture(t);
  const id = '10d4d9c5-5cb9-4afb-abc2-2f088de780ac';
  const directory = path.join(root, 'jobs', id);
  await fs.mkdir(directory);
  await fs.writeFile(path.join(directory, 'job.json'), JSON.stringify({ executionID: id, state: 'queued', startedAt: Date.now(), cancellationRequested: true }));
  await jobs.initialize();
  assert.equal(jobs.snapshot(id).state, 'interrupted');
  assert.deepEqual(await jobs.readOutput(id, 'stdout'), { executionID: id, channel: 'stdout', offset: 0, nextOffset: 0, totalBytes: 0, hasMore: false, base64: '' });
});


test('actual CommonJS CLI main preserves argv, cwd, environment, binary stdin and late stdout', async t => {
  const { jobs, root, body } = await fixture(t);
  const entryPoint = path.join(root, 'cli.cjs');
  const input = Buffer.from('שלום 👨‍👩‍👧‍👦\n'.repeat(400_000));
  const standardInputPath = path.join(root, 'stdin.bin');
  await fs.writeFile(standardInputPath, input);
  await fs.writeFile(entryPoint, `
    const assert = require('node:assert/strict');
    assert.equal(require.main, module);
    assert.deepEqual(process.argv.slice(2), ['arg with spaces', 'שלום']);
    assert.equal(process.env.CLI_CUSTOM, 'isolated');
    assert.equal(process.cwd(), ${JSON.stringify(root)});
    assert.equal(typeof require('node:fs').realpathSync.native, 'function');
    const chunks = [];
    process.stdin.on('data', chunk => chunks.push(chunk));
    process.stdin.on('end', () => {
      process.stdout.write(Buffer.concat(chunks));
      setTimeout(() => process.stderr.write('CLI_LATE_COMPLETE'), 30);
    });
  `);
  const started = await jobs.start({ ...body, executionMode: 'cli', entryPoint, standardInputPath,
    arguments: ['arg with spaces', 'שלום'], environment: { CLI_CUSTOM: 'isolated' } });
  const completed = await jobs.wait(started.executionID);
  assert.equal(completed.state, 'completed', JSON.stringify(completed));
  assert.ok(input.length > 10 * 1024 * 1024);
  assert.deepEqual(await fs.readFile(completed.result.outputFiles.stdout.path), input);
  assert.equal(completed.result.outputFiles.stdout.sha256, createHash('sha256').update(input).digest('hex'));
  assert.equal(await fs.readFile(completed.result.outputFiles.stderr.path, 'utf8'), 'CLI_LATE_COMPLETE');
  assert.equal(completed.result.outputWasTruncated, true);
});

test('actual ESM CLI errors and exit status are retained without interpreting user messages as results', async t => {
  const { jobs, root, body } = await fixture(t);
  const entryPoint = path.join(root, 'cli.mjs');
  await fs.writeFile(entryPoint, `import {parentPort} from 'node:worker_threads'; parentPort.postMessage({type:'completed',value:'misleading'}); console.log('ESM_CLI'); process.exitCode=23;`);
  let started = await jobs.start({ ...body, executionMode: 'cli', entryPoint });
  let completed = await jobs.wait(started.executionID);
  assert.equal(completed.state, 'failed');
  assert.equal(completed.result.exitCode, 23);
  assert.equal(completed.result.value, null);
  assert.match(completed.result.stdout, /ESM_CLI/);
  await fs.writeFile(entryPoint, "throw new Error('CLI_REAL_FAILURE');");
  started = await jobs.start({ ...body, executionMode: 'cli', entryPoint });
  completed = await jobs.wait(started.executionID);
  assert.equal(completed.state, 'failed');
  assert.match(completed.result.stderr, /CLI_REAL_FAILURE/);
});


test('CLI cancellation stops the actual main and retains partial output; launch environment is frozen', async t => {
  const { jobs, root, body } = await fixture(t);
  const key = 'HANLIN_TEMPORARY_NATIVE_ENV';
  const previous = process.env[key];
  // A different native engine may temporarily set C environ after host launch.
  process.env[key] = 'must-not-leak';
  t.after(() => { if (previous === undefined) delete process.env[key]; else process.env[key] = previous; });
  const entryPoint = path.join(root, 'cancel.cjs');
  await fs.writeFile(entryPoint, `
    if(process.env.${key}!==undefined) throw new Error('Inherited another engine job environment');
    console.log('CLI_STARTED'); setInterval(()=>{},1000);
  `);
  const started = await jobs.start({ ...body, executionMode: 'cli', entryPoint });
  const deadline = performance.now()+5000;
  while(jobs.snapshot(started.executionID).stdoutBytes===0 && performance.now()<deadline) await new Promise(resolve=>setTimeout(resolve,10));
  assert.ok(jobs.snapshot(started.executionID).stdoutBytes>0, JSON.stringify(jobs.snapshot(started.executionID)));
  await jobs.cancel(started.executionID);
  const completed = await jobs.wait(started.executionID);
  assert.equal(completed.state,'cancelled');
  assert.equal(completed.result.wasCancelled,true);
  assert.match(completed.result.stdout,/CLI_STARTED/);
});


test('user PATH HOME and NODE_OPTIONS apply to the job without reconfiguring Worker bootstrap', async t => {
  const { jobs, root, body } = await fixture(t);
  const environment = {PATH:'/user tools/bin', HOME:'/user-home', NODE_OPTIONS:'--not-a-node-bootstrap-flag', PYTHONHOME:'/user-python','ProgramFiles(x86)':'/explicit-apps','שם-משתנה':'ערך'};
  const assertions = `
    const assert = require('node:assert/strict');
    assert.equal(process.env.PATH,'/user tools/bin');
    assert.equal(process.env.HOME,'/user-home');
    assert.equal(process.env.NODE_OPTIONS,'--not-a-node-bootstrap-flag');
    assert.equal(process.env.PYTHONHOME,'/user-python');
    assert.equal(process.env['ProgramFiles(x86)'],'/explicit-apps');
    assert.equal(process.env['שם-משתנה'],'ערך');
    console.log('JOB_ENV_WITHOUT_BOOTSTRAP_RECONFIGURATION');
  `;
  const original = process.env.NODE_OPTIONS;
  const source = await jobs.start({...body,moduleKind:'commonjs',environment,source:assertions});
  assert.equal((await jobs.wait(source.executionID)).state,'completed');
  const entryPoint = path.join(root,'env.cjs');
  await fs.writeFile(entryPoint,assertions);
  const cli = await jobs.start({...body,executionMode:'cli',entryPoint,environment});
  const completed = await jobs.wait(cli.executionID);
  assert.equal(completed.state,'completed',JSON.stringify(completed));
  assert.match(completed.result.stdout,/JOB_ENV_WITHOUT_BOOTSTRAP_RECONFIGURATION/);
  assert.equal(process.env.NODE_OPTIONS,original);
});
