import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
const [sdkRoot, runRoot, authoringPath] = process.argv.slice(2);
const {runMiniAppOperation} = await import(pathToFileURL(authoringPath).href);
const sha = value => createHash('sha256').update(value).digest('hex');
const sdk = JSON.parse(await fs.readFile(path.join(sdkRoot, 'miniapp-sdk.json')));
if (sdk.inputSHA256 !== '48f09da9dc0ec43b5591db3a701d9572204b31785bf5049bae0044a78b191289') throw new Error('SDK changed');
const previous = JSON.parse(await fs.readFile(path.join(runRoot, 'gallery-receipt.json')));
const receipt = {...previous, startedAt: new Date().toISOString(), finishedAt: undefined, passed: false,
  originalContract: 'Original runMiniAppOperation succeeded with strict user-source typing; original NativeScript SDK base skipLibCheck remains true.',
  dependencyDeclarationScope: 'Expo validates dependency declarations; NativeScript preserves original skipLibCheck=true. Earlier additional receipt requirement is separately recorded, not a product failure.',
  priorAdditionalGateAttempt: path.join(runRoot, 'gallery-receipt.json'), projects: []};
const out = path.join(runRoot, 'gallery-original-contract-receipt.json');
const persist = () => fs.writeFile(out, JSON.stringify(receipt, null, 2) + '\n');
await persist();
for (const old of previous.projects) {
 const item = {...old, reports: []};
 receipt.projects.push(item);
 for (const operation of ['validate', 'build']) {
  const prior = old.reports.find(r => r.operation === operation);
  const reportPath = path.join(runRoot, item.id + '-' + operation + '.json');
  const started = performance.now();
  const report = prior ? JSON.parse(await fs.readFile(prior.reportPath)) :
    await runMiniAppOperation({operation, projectRoot:item.project,
      outputDirectory:path.join(runRoot,'packages',path.basename(item.project))},{sdkRoot});
  if (!prior) await fs.writeFile(reportPath,JSON.stringify(report,null,2)+'\n');
  const accepted=report.succeeded===true && report.typecheck?.strict===true;
  item.reports.push({operation,accepted,succeeded:report.succeeded,reusedOriginalOperation:!!prior,reportPath,
    durationMilliseconds:prior?.durationMilliseconds??Math.round(performance.now()-started),
    compilerVersion:report.sdk?.compilerVersion,packageVersions:report.sdk?.packageVersions,
    typecheck:report.typecheck,diagnostics:report.diagnostics,preparedPackagePath:report.preparedPackagePath});
  if (accepted && operation==='build') {
   const prepared=report.preparedPackagePath;
   const retained=JSON.parse(await fs.readFile(path.join(prepared,'hanlin.authoring.json')));
   if (!Object.keys(retained.sourceHashes??{}).length || !Object.keys(retained.compiledHashes??{}).length) throw new Error('Missing hashes');
   for (const [name,hash] of Object.entries(retained.sourceHashes)) {
    const paths=[path.join(item.project,name),path.join(item.source,name),path.join(prepared,'source',name)];
    for(const file of paths) if(sha(await fs.readFile(file))!==hash) throw new Error('Source mismatch: '+file);
   }
   for(const [name,hash] of Object.entries(retained.compiledHashes))
    if(sha(await fs.readFile(path.join(prepared,name)))!==hash) throw new Error('Compiled mismatch: '+name);
   item.retainedSourceFiles=Object.keys(retained.sourceHashes).length;
   item.verifiedCompiledFiles=Object.keys(retained.compiledHashes).length;
   item.entrypoint=JSON.parse(await fs.readFile(path.join(prepared,'script.json'))).entry;
  }
  await persist();
  console.log(JSON.stringify({id:item.id,operation,accepted,reused:!!prior,typecheck:report.typecheck,compilerVersion:report.sdk?.compilerVersion,diagnostics:report.diagnostics}));
  globalThis.gc?.();
  if (!accepted) break;
 }
}
receipt.finishedAt=new Date().toISOString();
receipt.passed=receipt.projects.length===5 && receipt.projects.every(p=>p.reports.length===2 && p.reports.every(r=>r.accepted) && p.retainedSourceFiles>0 && p.verifiedCompiledFiles>0);
await persist();
console.log(JSON.stringify({passed:receipt.passed,receipt:out,projects:receipt.projects.map(p=>({id:p.id,sourceFiles:p.retainedSourceFiles,compiledFiles:p.verifiedCompiledFiles,entrypoint:p.entrypoint}))}));
process.exitCode=receipt.passed?0:1;
