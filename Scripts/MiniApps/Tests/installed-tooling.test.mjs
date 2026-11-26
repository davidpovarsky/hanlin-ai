import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdtemp,mkdir,readFile,writeFile,rm,cp} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {ensureInstalledTooling,verifyInstalledGraph,resealInstalledTooling} from '../install-tooling.mjs';
import {copyAuthoringTree} from '../stage-sdk.mjs';

const sha=value=>createHash('sha256').update(value).digest('hex');
const json=async(file,value)=>writeFile(file,JSON.stringify(value)+'\n');
async function originalGraph(fn) {
  const directory=await mkdtemp(path.join(tmpdir(),'hanlin-install-integrity-'));
  const cache=path.join(directory,'npm-cache'),toolingRoot=path.join(directory,'tooling'),local=path.join(directory,'local');
  const npm=(args,cwd=directory)=>execFileSync(process.platform==='win32'?'npm.cmd':'npm',[...args,'--cache',cache,'--offline','--ignore-scripts','--no-audit','--no-fund'],{cwd,encoding:'utf8',stdio:['ignore','pipe','pipe']});
  try {
    for(const name of ['child','parent','tooling','local'])await mkdir(path.join(directory,name));
    const child=path.join(directory,'child'),parent=path.join(directory,'parent');
    await json(path.join(child,'package.json'),{name:'original-child',version:'1.0.0',files:['index.d.ts','index.js']});
    await writeFile(path.join(child,'index.d.ts'),'export declare const value: number;\n');
    await writeFile(path.join(child,'index.js'),'exports.value = 42;\n');
    const childTar=path.join(directory,JSON.parse(npm(['pack',child,'--pack-destination',directory,'--json']))[0].filename);
    await json(path.join(parent,'package.json'),{name:'original-parent',version:'1.0.0',files:['index.d.ts'],dependencies:{'original-child':'file:'+childTar}});
    await writeFile(path.join(parent,'index.d.ts'),"export { value } from 'original-child';\n");
    const parentTar=path.join(directory,JSON.parse(npm(['pack',parent,'--pack-destination',directory,'--json']))[0].filename);
    await json(path.join(local,'package.json'),{name:'@hanlin/local',version:'1.0.0',types:'index.d.ts'});
    await writeFile(path.join(local,'index.d.ts'),'export declare const current: 1;\n');
    await json(path.join(toolingRoot,'package.json'),{name:'tooling-fixture',version:'1.0.0',private:true,dependencies:{'original-parent':'file:'+parentTar,'@hanlin/local':'file:../local'}});
    npm(['install','--package-lock-only','--prefix',toolingRoot]);
    const ensure=()=>ensureInstalledTooling({toolingRoot,ignoreScripts:true,npmArguments:['--offline','--cache',cache]});
    await fn({directory,toolingRoot,local,ensure});
  } finally {await rm(directory,{recursive:true,force:true});}
}
test('real original npm install rejects stale transitive bytes and local declarations, then reuses exact verified inputs',async t=>originalGraph(async({toolingRoot,local,ensure})=>{
  await assert.rejects(verifyInstalledGraph(toolingRoot),/No verified original npm installation receipt/);
  assert.equal((await ensure()).status,'installed');
  const child=path.join(toolingRoot,'node_modules/original-child'),parent=path.join(toolingRoot,'node_modules/original-parent');
  await t.test('unchanged original inputs reuse the existing installation',async()=>{
    assert.equal((await ensure()).status,'reused');
    assert.ok((await verifyInstalledGraph(toolingRoot)).installedPackages.some(item=>item.path==='node_modules/original-child'));
  });
  await t.test('missing transitive declaration is rejected and restored by original npm ci',async()=>{
    await rm(path.join(child,'index.d.ts'));
    await assert.rejects(verifyInstalledGraph(toolingRoot),/original file is missing or changed: node_modules\/original-child\/index.d.ts/);
    assert.equal((await ensure()).status,'installed');
    assert.equal(await readFile(path.join(child,'index.d.ts'),'utf8'),'export declare const value: number;\n');
  });
  await t.test('same-version transitive JavaScript modification cannot pass a version-only check',async()=>{
    await writeFile(path.join(child,'index.js'),'exports.value = "stale";\n');
    await assert.rejects(verifyInstalledGraph(toolingRoot),/original-child\/index.js/);
    assert.equal((await ensure()).status,'installed');
    assert.equal(await readFile(path.join(child,'index.js'),'utf8'),'exports.value = 42;\n');
  });
  await t.test('transitive package version drift is rejected even when direct versions match',async()=>{
    const file=path.join(child,'package.json'),pkg=JSON.parse(await readFile(file,'utf8'));
    await json(file,{...pkg,version:'9.9.9'});
    await assert.rejects(verifyInstalledGraph(toolingRoot),/differs from package-lock: node_modules\/original-child/);
    assert.equal((await ensure()).status,'installed');
  });
  await t.test('a copied local package must match current source bytes despite an unchanged version',async()=>{
    const installed=path.join(toolingRoot,'node_modules/@hanlin/local');
    await rm(installed,{recursive:true,force:true});await cp(local,installed,{recursive:true});
    await writeFile(path.join(local,'index.d.ts'),'export declare const current: 2;\n');
    await assert.rejects(verifyInstalledGraph(toolingRoot),/local SDK source differs.*index.d.ts/);
    assert.equal((await ensure()).status,'installed');
    assert.equal(await readFile(path.join(installed,'index.d.ts'),'utf8'),'export declare const current: 2;\n');
    // The current source link is already the correct package. Reinstalling every
    // time its authored code changes would accomplish no dependency work.
    await writeFile(path.join(local,'index.d.ts'),'export declare const current: 3;\n');
    assert.equal((await ensure()).status,'reused');
  });
  await t.test('a changed transitive lock identity cannot reuse a receipt with unchanged installed versions',async()=>{
    const file=path.join(toolingRoot,'package-lock.json'),before=await readFile(file,'utf8'),lock=JSON.parse(before);
    lock.packages['node_modules/original-child'].integrity='sha512-changed-original-publication';
    await json(file,lock);
    await assert.rejects(verifyInstalledGraph(toolingRoot),/input fingerprint is stale/);
    await writeFile(file,before);
    assert.equal((await ensure()).status,'reused');
  });
  await t.test('authenticated declaration reseal cannot conceal another changed original file',async()=>{
    const declaration=path.join(parent,'index.d.ts'),before=await readFile(declaration),after=Buffer.from('export declare const value: 42;\n');
    await writeFile(declaration,after);await writeFile(path.join(child,'index.js'),'exports.value = "unrelated change";\n');
    const changes=[{path:'node_modules/original-parent/index.d.ts',beforeSHA256:sha(before),afterSHA256:sha(after)}];
    await assert.rejects(resealInstalledTooling(toolingRoot,changes),/Unapproved SDK file changed.*original-child\/index.js/);
    await writeFile(path.join(child,'index.js'),'exports.value = 42;\n');
    await resealInstalledTooling(toolingRoot,changes);
    assert.equal((await ensure()).status,'reused');
  });
}));

test('native ExpoModulesJSI build output preserves a verified install and stays out of the author SDK',async()=>{
  const directory=await mkdtemp(path.join(tmpdir(),'hanlin-jsi-output-integrity-'));
  const source=path.join(directory,'original-jsi'),toolingRoot=path.join(directory,'tooling'),cache=path.join(directory,'npm-cache');
  const npm=args=>execFileSync(process.platform==='win32'?'npm.cmd':'npm',[...args,'--cache',cache,'--offline','--ignore-scripts','--no-audit','--no-fund'],{cwd:directory,encoding:'utf8',stdio:['ignore','pipe','pipe']});
  try {
    await mkdir(path.join(source,'apple'),{recursive:true});await mkdir(path.join(source,'src/build'),{recursive:true});await mkdir(path.join(source,'dist'),{recursive:true});await mkdir(toolingRoot);
    await json(path.join(source,'package.json'),{name:'expo-modules-jsi',version:'58.0.23',files:['apple/source.d.ts','src/build/config.ts','dist/index.d.ts']});
    await writeFile(path.join(source,'apple/source.d.ts'),'export declare const original: number;\n');
    await writeFile(path.join(source,'src/build/config.ts'),'export const authored = 1;\n');
    await writeFile(path.join(source,'dist/index.d.ts'),'export declare const published: number;\n');
    const tarball=path.join(directory,JSON.parse(npm(['pack',source,'--pack-destination',directory,'--json']))[0].filename);
    await json(path.join(toolingRoot,'package.json'),{name:'native-output-fixture',version:'1.0.0',private:true,dependencies:{'expo-modules-jsi':'file:'+tarball}});
    npm(['install','--package-lock-only','--prefix',toolingRoot]);
    const ensure=()=>ensureInstalledTooling({toolingRoot,ignoreScripts:true,npmArguments:['--offline','--cache',cache]});
    assert.equal((await ensure()).status,'installed');
    const installed=path.join(toolingRoot,'node_modules/expo-modules-jsi');
    for(const output of ['.DerivedData','.build','.swiftpm','.generated','Products']) {
      await mkdir(path.join(installed,'apple',output),{recursive:true});
      await writeFile(path.join(installed,'apple',output,'generated.json'),'{"nativeBuild":"prepared"}\n');
    }
    assert.equal((await ensure()).status,'reused');
    assert.equal(await readFile(path.join(installed,'apple/Products/generated.json'),'utf8'),'{"nativeBuild":"prepared"}\n');
    const copied=[],sdk=path.join(directory,'sdk');
    await copyAuthoringTree(path.join(toolingRoot,'node_modules'),sdk,copied,'expo/node_modules');
    assert.ok(copied.some(file=>file.path.endsWith('/src/build/config.ts')));
    assert.ok(copied.some(file=>file.path.endsWith('/dist/index.d.ts')));
    assert.ok(copied.some(file=>file.path.endsWith('/apple/source.d.ts')));
    assert.ok(!copied.some(file=>file.path.endsWith('/generated.json')));
    await writeFile(path.join(installed,'apple/source.d.ts'),'export declare const original: string;\n');
    await assert.rejects(verifyInstalledGraph(toolingRoot),/original file is missing or changed:.*apple\/source.d.ts/);
  } finally {await rm(directory,{recursive:true,force:true});}
});
