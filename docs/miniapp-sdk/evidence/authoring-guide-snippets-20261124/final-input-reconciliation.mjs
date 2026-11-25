
import assert from 'node:assert/strict';
import {promises as fs} from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {createHash} from 'node:crypto';
import {readGuideExamples, prepareGuideProjects} from './Scripts/MiniApps/check-authoring-examples.mjs';
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const evidence = '/dev/shm/hanlin-guide-snippet-evidence-20261124';
const sdkRoot = '/dev/shm/hanlin-sdk-only-kit-45335292541/AI_HLY/Downstream/RuntimeCore/Node/Host/MiniAppSDK';
const original = JSON.parse(await fs.readFile(path.join(evidence, 'first-original-compiler.json')));
const ns = JSON.parse(await fs.readFile(path.join(evidence, 'nativescript-guide-green.json')));
const guides = await readGuideExamples();
const temporary = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-guide-final-inputs-'));
const sdkSHA = sha(await fs.readFile(path.join(sdkRoot, 'miniapp-sdk.json')));
try {
  const projects = await prepareGuideProjects({blocks: guides.blocks, directory: temporary});
  const comparisons = [];
  for (const current of projects) {
    const prior = current.name === 'nativescript-guide' ? {...ns.project, validation: ns.report}
      : original.projects.find(item => item.name === current.name);
    assert.equal(prior.validation.succeeded, true);
    assert.equal(prior.validation.sdk.manifestSHA256, sdkSHA);
    const expected = new Map(prior.snippets.map(item => [item.file, item.sha256]));
    for (const item of prior.context) expected.set(item.path, item.checkedFileSHA256 ?? item.sha256);
    const files = [];
    for (const [file, expectedHash] of expected) {
      const actualHash = sha(await fs.readFile(path.join(current.root, file)));
      assert.equal(actualHash, expectedHash, current.name + '/' + file);
      files.push({path: file, sha256: actualHash});
    }
    const actualPaths = [...current.snippets.map(item => item.file), ...current.context.map(item => item.path)];
    assert.deepEqual(new Set(actualPaths), new Set(expected.keys()));
    comparisons.push({name: current.name, engine: current.engine, status: 'REUSED_VERIFIED_PASS',
      actualExecution: current.name === 'nativescript-guide' ? 'nativescript-guide-green.json' : 'first-original-compiler.json',
      compilerVersion: prior.validation.sdk.compilerVersion, typecheck: prior.validation.typecheck,
      effectiveCompilerInputBytesIdentical: true, files, currentSnippets: current.snippets});
  }
  const result = {status: 'REUSED_VERIFIED_PASS', sdkManifestSHA256: sdkSHA,
    sourceBlockCount: [...guides.blocks.values()].filter(item => item.kind === 'source').length,
    jsonBlockCount: [...guides.blocks.values()].filter(item => item.kind === 'json').length,
    documents: guides.documents, projects: comparisons,
    excluded: [...guides.blocks.values()].filter(item => item.kind === 'excluded').map(({id, reason}) => ({id, reason, status: 'NOT_RUN'})),
    note: 'No compiler was rerun for this comparison. It proves the final Markdown projection produces byte-identical effective inputs to the recorded original-compiler passes. The NS config now visibly includes moduleDetection:force instead of receiving that same option from checker scaffolding.',
    nativeLaunch: 'NOT_RUN', deviceExecution: 'NOT_RUN', shellInstructionExecution: 'NOT_RUN'};
  await fs.writeFile(path.join(evidence, 'final-input-reconciliation.json'), JSON.stringify(result, null, 2) + '\n');
  console.log(JSON.stringify({status: result.status, sources: result.sourceBlockCount, json: result.jsonBlockCount,
    projects: result.projects.map(item => ({name: item.name, files: item.files.length, exact: item.effectiveCompilerInputBytesIdentical}))}));
} finally { await fs.rm(temporary, {recursive: true, force: true}); }
