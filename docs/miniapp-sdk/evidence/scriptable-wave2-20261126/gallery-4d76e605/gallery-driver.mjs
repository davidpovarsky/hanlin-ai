import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';

const [sdkRoot, runRoot, authoringPath] = process.argv.slice(2);
const {runMiniAppOperation} = await import(pathToFileURL(authoringPath).href);
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const sdk = JSON.parse(await fs.readFile(path.join(sdkRoot, 'miniapp-sdk.json')));
const index = JSON.parse(await fs.readFile(path.join(sdkRoot, 'examples/index.json')));
if (sdk.inputSHA256 !== '48f09da9dc0ec43b5591db3a701d9572204b31785bf5049bae0044a78b191289'
    || index.projects.length !== 5) throw new Error('Unexpected immutable SDK/gallery identity.');
const receipt = {schemaVersion: 1, sourceCommit: '4d76e605', inputSHA256: sdk.inputSHA256,
  sdkRoot, nodeVersion: process.version, startedAt: new Date().toISOString(),
  scope: 'Original canonical authoring validate/build against actual fresh staged dependencies; no Apple UI/runtime execution.',
  projects: []};
const writeReceipt = () => fs.writeFile(path.join(runRoot, 'gallery-receipt.json'), JSON.stringify(receipt, null, 2) + '\n');
await writeReceipt();
const ordered = [...index.projects].sort((a,b) => Number(b.engine === 'nativescript') - Number(a.engine === 'nativescript'));
for (const item of ordered) {
  const source = path.join(sdkRoot, 'examples', item.directory);
  const project = path.join(runRoot, 'projects', item.directory);
  await fs.cp(source, project, {recursive: true, errorOnExist: true});
  const result = {id: item.id, engine: item.engine, source, project, reports: []};
  receipt.projects.push(result);
  for (const operation of ['validate', 'build']) {
    const started = performance.now();
    const report = await runMiniAppOperation({operation, projectRoot: project,
      outputDirectory: path.join(runRoot, 'packages', item.directory)}, {sdkRoot});
    const reportPath = path.join(runRoot, item.id + '-' + operation + '.json');
    await fs.writeFile(reportPath, JSON.stringify(report, null, 2) + '\n');
    const accepted = report.succeeded === true && report.typecheck?.strict === true
      && report.typecheck?.skipLibCheck === false && report.typecheck?.dependencyDeclarationsChecked === true;
    result.reports.push({operation, accepted, reportPath, durationMilliseconds: Math.round(performance.now() - started),
      compilerVersion: report.sdk?.compilerVersion, packageVersions: report.sdk?.packageVersions,
      typecheck: report.typecheck, diagnostics: report.diagnostics, preparedPackagePath: report.preparedPackagePath});
    console.log(JSON.stringify({id: item.id, operation, accepted, typecheck: report.typecheck,
      compilerVersion: report.sdk?.compilerVersion, diagnostics: report.diagnostics}));
    if (accepted && operation === 'build') {
      const prepared = report.preparedPackagePath;
      const retained = JSON.parse(await fs.readFile(path.join(prepared, 'hanlin.authoring.json')));
      if (!Object.keys(retained.sourceHashes ?? {}).length || !Object.keys(retained.compiledHashes ?? {}).length)
        throw new Error('Prepared package has no complete source/compiled identity: ' + item.id);
      for (const [name, hash] of Object.entries(retained.sourceHashes)) {
        const original = await fs.readFile(path.join(project, name));
        const output = await fs.readFile(path.join(prepared, 'source', name));
        if (sha(original) !== hash || sha(output) !== hash)
          throw new Error('Source bytes changed while building ' + item.id + ': ' + name);
      }
      for (const [name, hash] of Object.entries(retained.compiledHashes)) {
        if (sha(await fs.readFile(path.join(prepared, name))) !== hash)
          throw new Error('Prepared file identity changed: ' + name);
      }
      result.retainedSourceFiles = Object.keys(retained.sourceHashes).length;
      result.verifiedCompiledFiles = Object.keys(retained.compiledHashes).length;
      result.entrypoint = JSON.parse(await fs.readFile(path.join(prepared, 'script.json'))).entry;
    }
    await writeReceipt();
    globalThis.gc?.();
    if (!accepted) break;
  }
}
receipt.finishedAt = new Date().toISOString();
receipt.passed = receipt.projects.length === 5 && receipt.projects.every(project =>
  project.reports.length === 2 && project.reports.every(report => report.accepted)
  && project.retainedSourceFiles > 0 && project.verifiedCompiledFiles > 0);
await writeReceipt();
console.log(JSON.stringify({passed: receipt.passed, projects: receipt.projects.map(p => ({
  id:p.id, reports:p.reports.map(r=>({operation:r.operation,accepted:r.accepted})),
  retainedSourceFiles:p.retainedSourceFiles,verifiedCompiledFiles:p.verifiedCompiledFiles
})),receipt:path.join(runRoot,'gallery-receipt.json')}));
process.exitCode = receipt.passed ? 0 : 1;
