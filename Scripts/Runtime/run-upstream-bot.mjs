#!/usr/bin/env node
import { execFileSync,spawnSync } from 'node:child_process';
import { readFile,writeFile,mkdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { dependencyImpact } from './dependency-update-policy.mjs';

const [repository,branch,mode='extract',onlyPackage,onlyFile='AI_HLY/Downstream/RuntimeCore/Node/Host/package.json'] = process.argv.slice(2);
if (!/^[\w.-]+\/[\w.-]+$/.test(repository??'') || !/^[\w./-]+$/.test(branch??'') || !['extract','lookup','full','apply'].includes(mode)) {
  throw new Error('Expected repository branch extract|lookup|full|apply [single Host package]');
}
const output=resolve('build/upstream-updates');await mkdir(output,{recursive:true});
const config=JSON.parse(await readFile('.renovaterc.json','utf8'));
Object.assign(config,{platform:'github',repositories:[repository],baseBranchPatterns:[branch],onboarding:false,
  requireConfig:'ignored',allowScripts:false,allowPlugins:false,exposeAllEnv:false,binarySource:'global',
  baseDir:resolve('.scratch/upstream-renovate'),cacheDir:resolve('.scratch/upstream-renovate-cache'),
  gitAuthor:'Hanlin dependency maintenance <41898282+github-actions[bot]@users.noreply.github.com>',
  force:{automerge:false,platformAutomerge:false}});
if(mode!=='apply')config.dryRun=mode;
if(onlyPackage) {
  if(!/^(?:@?[\w.-]+\/)?[\w.-]+$/.test(onlyPackage))throw new Error('Invalid package name');
  if(!['AI_HLY/Downstream/RuntimeCore/Node/Host/package.json','Packages/HanlinSkillFormat/Package.swift'].includes(onlyFile))throw new Error('Unsupported scoped consumer');
  config.force.packageRules=[{matchPackageNames:['*'],enabled:false},
    {matchPackageNames:[onlyPackage],matchFileNames:[onlyFile],enabled:true,automerge:false}];
}
const file=resolve(output,'renovate-admin.json');await writeFile(file,JSON.stringify(config,null,2)+'\n');
const token=process.env.RENOVATE_TOKEN||execFileSync('gh',['auth','token'],{encoding:'utf8',stdio:['ignore','pipe','pipe']}).trim();
const cli=resolve('Scripts/Runtime/DependencyUpdates/node_modules/renovate/dist/renovate.js');
const result=spawnSync(process.execPath,[cli],{
  env:{...process.env,RENOVATE_CONFIG_FILE:file,RENOVATE_TOKEN:token,LOG_LEVEL:'debug',LOG_FORMAT:'json'},encoding:'utf8',maxBuffer:67_108_864});
// Neither the generated config nor retained logs contain the repository credential.
const redact=text=>String(text??'').replaceAll(token,'[REDACTED]').replaceAll(encodeURIComponent(token),'[REDACTED]')
  .replaceAll(Buffer.from('x-access-token:'+token).toString('base64'),'[REDACTED]');
await writeFile(resolve(output,'renovate.log'),redact(result.stdout)+'\n'+redact(result.stderr));
const summary={repository,branch,mode,onlyPackage:onlyPackage??null,exitCode:result.status,
  tool:JSON.parse(await readFile('Scripts/Runtime/DependencyUpdates/node_modules/renovate/package.json','utf8')).version,
  node:process.version,mergeEnabled:false,log:'build/upstream-updates/renovate.log'};
await writeFile(resolve(output,'renovate-run.json'),JSON.stringify(summary,null,2)+'\n');
console.log(JSON.stringify(summary));
if(result.error)throw new Error(redact(result.error.message));
process.exitCode=result.status??1;
if(result.status===0&&mode==='apply') {
 const pulls=JSON.parse(execFileSync('gh',['pr','list','--repo',repository,'--base',branch,'--limit','100','--json','number,headRefName'],{encoding:'utf8',stdio:['ignore','pipe','pipe']}));
 for(const pr of pulls.filter(p=>p.headRefName.startsWith('codex/renovate/'))) {
  const files=JSON.parse(execFileSync('gh',['api',`repos/${repository}/pulls/${pr.number}/files?per_page=100`],{encoding:'utf8',stdio:['ignore','pipe','pipe']}));
  if(files.length<100&&dependencyImpact(files.map(x=>x.filename))==='runtime-host') {
   execFileSync(process.execPath,[resolve('Scripts/Runtime/sync-upstream-host-pr.mjs'),repository,String(pr.number)],{stdio:'inherit'});
  }
 }
}
