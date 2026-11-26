import assert from 'node:assert/strict';
import {readFile, writeFile, mkdir, readdir, mkdtemp} from 'node:fs/promises';
import path from 'node:path';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {spawnSync} from 'node:child_process';
const root = process.argv[2];
const evidence = path.dirname(import.meta.filename);
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const packagePath = 'Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/Resources/NativeScriptSharedRuntime/@hanlin/host-services/package.json';
const facade = path.dirname(path.join(root, packagePath));
const report = {startedAt: new Date().toISOString(), root, node: process.version, sourceHEAD: spawnSync('git', ['rev-parse','HEAD'], {cwd: root, encoding: 'utf8'}).stdout.trim(), commands: [], assertions: []};
const command = (name, args) => {
  const start = Date.now();
  const result = spawnSync(process.execPath, args, {cwd: root, encoding: 'utf8', timeout: 60000});
  const log = `${result.stdout ?? ''}${result.stderr ?? ''}`;
  return writeFile(path.join(evidence, name + '.log'), log).then(() => {
    report.commands.push({name, argv: [process.execPath,...args], elapsedSeconds:(Date.now()-start)/1000, exitCode:result.status, signal:result.signal, logSHA256:sha(log)});
    assert.equal(result.error, undefined); assert.equal(result.status, 0, log);
    process.stdout.write(log);
  });
};
const trackedHashes = async () => {
  const listing = spawnSync('git', ['diff','--name-only','-z','HEAD'], {cwd:root, encoding:'utf8'});
  assert.equal(listing.status,0);
  const entries = [];
  for (const file of listing.stdout.split('\0').filter(Boolean).sort()) {
    const bytes = await readFile(path.join(root,file)).catch(() => null);
    entries.push([file,bytes === null ? null : sha(bytes)]);
  }
  return Object.fromEntries(entries);
};
const facadeHashes = async () => Object.fromEntries(await Promise.all((await readdir(facade)).sort().map(async name => [name,sha(await readFile(path.join(facade,name)))])));
async function productionFunction(name) {
  const bytes = await readFile(path.join(evidence,name));
  const source = bytes.toString();
  const start = source.indexOf('  async function normalizePackageJsons(dir) {');
  const end = source.indexOf('\n  await normalizePackageJsons(sharedStaging);', start);
  assert.ok(start >= 0 && end > start);
  const body = source.slice(start,end);
  const moduleSource = `import {readdir,readFile,writeFile} from 'node:fs/promises';\nimport {resolve} from 'node:path';\n${body}\nexport {normalizePackageJsons};\n`;
  const loaded = await import('data:text/javascript;base64,'+Buffer.from(moduleSource).toString('base64'));
  return {fn:loaded.normalizePackageJsons, body, sourceSHA256:sha(bytes), bodySHA256:sha(body)};
}
try {
  const before = await productionFunction('normalizer-before.mjs');
  const after = await productionFunction('normalizer-after.mjs');
  assert.equal(after.sourceSHA256,'b5114a3be1fc846e288128af08cef9f38b0cac8e34923780325c4edc2976ebd9');
  assert.equal(after.body.replace("          if (data !== null && Object.hasOwn(data, 'type')) continue;\n",''), before.body);
  report.production = {beforeSourceSHA256:before.sourceSHA256,afterSourceSHA256:after.sourceSHA256,beforeFunctionSHA256:before.bodySHA256,afterFunctionSHA256:after.bodySHA256,method:'Exact source function body loaded unchanged with only its three filesystem/path imports; not the full native preparation module.'};
  const canonical = await readFile(path.join(evidence,'expected-package.json'));
  assert.equal(sha(canonical),'c42e3fe3eb38b7289ba3cf49ca0b56bcbd7ac2d27d68955f27e3d5e33e642a7e');
  const work = await mkdtemp(path.join(evidence,'normalizer-cases-'));
  report.fixtureRoot = work;
  const oldFixture = path.join(work,'authentic-old-writer'); await mkdir(oldFixture);
  await writeFile(path.join(oldFixture,'package.json'),canonical);
  await before.fn(oldFixture);
  const red = await readFile(path.join(oldFixture,'package.json'));
  assert.equal(sha(red),'ebe6634d2e019c9da759ac280c1269d721e2105681fdbc8a1796f464d0b9ee9e');
  assert.notDeepEqual(red,canonical);assert.deepEqual(JSON.parse(red),JSON.parse(canonical));
  report.assertions.push('Original exact writer reproduced the retained 147-byte key-order-only drift.');
  const explicit = {module:canonical.toString(),commonjs:'{ "name": "fixture", "type": "commonjs" }\n',null:'{"name":"fixture","type":null}\n',unknown:'{"name":"fixture","type":"custom"}\n',false:'{"name":"fixture","type":false}\n',zero:'{"name":"fixture","type":0}\n'};
  for (const [name,bytes] of Object.entries(explicit)) {
    const dir = path.join(work,'own-type',name); await mkdir(dir,{recursive:true});await writeFile(path.join(dir,'package.json'),bytes);
  }
  await after.fn(path.join(work,'own-type'));await after.fn(path.join(work,'own-type'));
  for (const [name,bytes] of Object.entries(explicit)) assert.equal(await readFile(path.join(work,'own-type',name,'package.json'),'utf8'),bytes);
  report.assertions.push('Two recursive production passes preserve exact bytes for own type module/commonjs/null/unknown/false/0.');
  const absent = {object:'{"name":"fixture","funding":{"type":"individual"}}\n',null:'null\n',array:'[]\n'};
  for (const [name,bytes] of Object.entries(absent)) {
    const oldDir=path.join(work,'absent-old',name),newDir=path.join(work,'absent-new',name);
    for (const dir of [oldDir,newDir]) {await mkdir(dir,{recursive:true});await writeFile(path.join(dir,'package.json'),bytes);}
    await before.fn(oldDir);await after.fn(newDir);
    const expected=await readFile(path.join(oldDir,'package.json'),'utf8');assert.equal(await readFile(path.join(newDir,'package.json'),'utf8'),expected);
    await after.fn(newDir);assert.equal(await readFile(path.join(newDir,'package.json'),'utf8'),expected);
    assert.equal(JSON.parse(expected).type,'module');
  }
  report.assertions.push('Absent own type retains original module-default output, including null JSON and array inputs; second pass is byte-stable.');
  const invalid=path.join(work,'invalid');await mkdir(invalid);await writeFile(path.join(invalid,'package.json'),'{ invalid JSON\n');await after.fn(invalid);assert.equal(await readFile(path.join(invalid,'package.json'),'utf8'),'{ invalid JSON\n');
  report.assertions.push('Malformed JSON retains existing catch/leave-unchanged behavior.');
  report.trackedBefore=await trackedHashes();report.facadeBefore=await facadeHashes();
  assert.equal(report.facadeBefore['package.json'],'ebe6634d2e019c9da759ac280c1269d721e2105681fdbc8a1796f464d0b9ee9e');
  const require=createRequire(path.join(root,'Scripts/NativeScript/build-host-services.mjs'));
  report.typescriptModule=require.resolve('typescript');
  await command('generator-recovery',['Scripts/NativeScript/build-host-services.mjs','--write']);
  report.facadeRecovered=await facadeHashes();assert.equal(report.facadeRecovered['package.json'],sha(canonical));
  for (const [name,hash] of Object.entries(report.facadeBefore)) if(name!=='package.json') assert.equal(report.facadeRecovered[name],hash);
  await after.fn(facade);await after.fn(facade);
  report.facadeAfterTwoPasses=await facadeHashes();assert.deepEqual(report.facadeAfterTwoPasses,report.facadeRecovered);
  await command('generator-check',['Scripts/NativeScript/build-host-services.mjs','--check']);
  report.trackedAfter=await trackedHashes();
  const allPaths=new Set([...Object.keys(report.trackedBefore),...Object.keys(report.trackedAfter)]);
  report.changedPreparedPaths=[];
  for (const file of allPaths) {if(report.trackedBefore[file]!==report.trackedAfter[file]) report.changedPreparedPaths.push(file);}
  assert.deepEqual(report.changedPreparedPaths,[packagePath]);
  report.assertions.push('Original strict generator --write repaired only the known package bytes; exact candidate writer twice plus original --check PASS; every other prepared tracked path retained.');
  report.status='PASS';report.boundary='Focused original Node/TypeScript generator and exact production normalizer only; full native preparation, corrected JSI/Core and all 52 app cases NOT_RUN.';
} catch(error) {report.status='FAIL';report.error=String(error.stack ?? error);process.exitCode=1;console.error(error);}
finally {report.completedAt=new Date().toISOString();await writeFile(path.join(evidence,'focused-result.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({status:report.status,assertions:report.assertions,commands:report.commands,changedPreparedPaths:report.changedPreparedPaths}));}
