#!/usr/bin/env node
// Synchronize canonical derived pins without executing or checking out candidate code.
import { execFileSync } from 'node:child_process';
import { mkdtemp,readFile,writeFile,rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join,resolve,dirname,basename } from 'node:path';
import { dependencyImpact } from './dependency-update-policy.mjs';
const [repository,number] = process.argv.slice(2);
if(!/^[\w.-]+\/[\w.-]+$/.test(repository??'')||!/^\d+$/.test(number??''))throw new Error('Expected repository PR-number');
const api=(suffix,body)=>JSON.parse(execFileSync('gh',['api',`repos/${repository}/${suffix}`,...(body?['--method','POST','--input','-']:[])],
  {input:body?JSON.stringify(body):undefined,encoding:'utf8',stdio:['pipe','pipe','pipe']}));
const pr=api(`pulls/${number}`);
if(pr.state!=='open'||pr.head.repo.full_name!==repository||!pr.head.ref.startsWith('codex/renovate/'))throw new Error('Only an open same-repository owned Renovate candidate can be synchronized');
const files=api(`pulls/${number}/files?per_page=100`);
if(files.length!==pr.changed_files||files.length>=100||dependencyImpact(files.map(x=>x.filename))!=='runtime-host')throw new Error('Unscoped candidate diff');
const paths=['RuntimeDependencies.lock.json','AI_HLY/Downstream/RuntimeCore/Node/Host/package.json',
 'AI_HLY/Downstream/RuntimeCore/Node/Host/package-lock.json','AI_HLY/Downstream/RuntimeCore/Resources/RuntimeManifest.json'];
const content=path=>Buffer.from(api(`contents/${path}?ref=${pr.head.sha}`).content.replace(/\s/g,''),'base64');
const scratch=await mkdtemp(join(tmpdir(),'hanlin-upstream-sync-'));
try {
 const originals=await Promise.all(paths.map(content));
 const temp=paths.map((_,i)=>join(scratch,`${i}.json`));
 await Promise.all(temp.map((p,i)=>writeFile(p,originals[i])));
 execFileSync(process.execPath,[resolve('Scripts/Runtime/update-runtime-dependencies.mjs'),...temp.slice(0,3),'--sync-package-lock'],{stdio:'inherit'});
 execFileSync(process.execPath,[resolve('Scripts/Runtime/generate-runtime-manifest.mjs'),temp[0],temp[3]],{stdio:'inherit'});
 execFileSync(process.execPath,[resolve('Scripts/Runtime/validate-runtime-lock.mjs'),temp[0]],{stdio:'inherit'});
 const tree=[];
 for(const i of [0,3]) {
  const bytes=await readFile(temp[i]);if(bytes.equals(originals[i]))continue;
  const blob=api('git/blobs',{content:bytes.toString('base64'),encoding:'base64'});
  tree.push({path:paths[i],mode:'100644',type:'blob',sha:blob.sha});
 }
 if(!tree.length){console.log(JSON.stringify({number,head:pr.head.sha,changed:false}));process.exitCode=0;}
 else {
  const parent=api(`git/commits/${pr.head.sha}`);
  const nextTree=api('git/trees',{base_tree:parent.tree.sha,tree});
  const commit=api('git/commits',{message:'Synchronize canonical Runtime Host dependency pins',tree:nextTree.sha,parents:[pr.head.sha]});
  const latest=api(`pulls/${number}`);
  if(latest.head.sha!==pr.head.sha)throw new Error('Candidate moved; retry against current head');
  const result=JSON.parse(execFileSync('gh',['api','--method','PATCH',`repos/${repository}/git/refs/heads/${pr.head.ref}`,'--input','-'],
   {input:JSON.stringify({sha:commit.sha,force:false}),encoding:'utf8',stdio:['pipe','pipe','pipe']}));
  console.log(JSON.stringify({number,previous:pr.head.sha,head:result.object.sha,changed:true,paths:tree.map(x=>x.path)}));
 }
} finally {
 if(dirname(scratch)!==resolve(tmpdir())||!basename(scratch).startsWith('hanlin-upstream-sync-'))throw new Error('Unexpected cleanup target');
 await rm(scratch,{recursive:true,force:true});
}
