#!/usr/bin/env node
// Checks the current public guide text with the same original SDK/public validator as authors.
import {promises as fs} from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {runMiniAppOperation, readMiniAppSDK} from '../../AI_HLY/Downstream/RuntimeCore/Node/Host/miniapp-authoring.mjs';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const digest = value => createHash('sha256').update(value).digest('hex');
const requireValue = (value, message) => { if (!value) throw new Error(message); };
const readJSON = async file => JSON.parse(await fs.readFile(file, 'utf8'));
const writeJSON = (file, value) => fs.writeFile(file, JSON.stringify(value, null, 2) + '\n');

export function extractGuideBlocks(source, document) {
  const lines = source.split(/\r?\n/);
  const blocks = [];
  for (let index = 0; index < lines.length; index++) {
    const fence = lines[index].match(/^( {0,3})(\x60{3,}|~{3,})(\S*)\s*$/);
    if (!fence) {
      // Only ordinary fences are extracted. Detect other Markdown fence forms
      // outside a recognized block so quote/list containers or indentation cannot
      // hide a new example from the inventory. Do not reinterpret their code.
      let candidate = lines[index].trimStart();
      const container = /^(?:>[ \t]*|(?:[-+*]|\d+[.)])[ \t]+)/;
      for (let prefix; (prefix = candidate.match(container));)
        candidate = candidate.slice(prefix[0].length).trimStart();
      requireValue(!/^(?:\x60{3,}|~{3,})/.test(candidate),
        document + ':' + (index + 1) + ': unsupported Markdown fence form (container, indentation or info string)');
      continue;
    }
    const label = lines[index - 1]?.trim().match(/^<!-- miniapp-snippet: ([\w.-]+) -->$/);
    requireValue(label, document + ':' + (index + 1) + ': unclassified fenced block');
    const startLine = index + 2;
    const body = [];
    let closed = false;
    while (++index < lines.length) {
      const end = lines[index].match(/^ {0,3}(\x60{3,}|~{3,})\s*$/);
      if (end && end[1][0] === fence[2][0] && end[1].length >= fence[2].length) {
        closed = true;
        break;
      }
      // CommonMark removes the opening fence's indentation from the code content.
      body.push(lines[index].slice(Math.min(fence[1].length, lines[index].match(/^ */)[0].length)));
    }
    requireValue(closed, document + ': unclosed fenced block ' + label[1]);
    blocks.push({id: label[1], document, line: startLine, language: fence[3],
      source: body.join('\n') + '\n'});
  }
  return blocks;
}

export async function readGuideExamples(root = repositoryRoot, overrides = new Map()) {
  const manifest = await readJSON(path.join(repositoryRoot, 'Scripts/MiniApps/authoring-examples.json'));
  requireValue(manifest.schemaVersion === 1, 'Unknown authoring example inventory');
  const blocks = new Map();
  const documents = [];
  for (const document of manifest.documents) {
    const bytes = overrides.has(document.path) ? Buffer.from(overrides.get(document.path))
      : await fs.readFile(path.join(root, document.path));
    const found = extractGuideBlocks(bytes.toString('utf8'), document.path);
    requireValue(found.length === document.blocks.length, document.path + ': fenced-block inventory changed');
    const expected = new Map(document.blocks.map(item => [item.id, item]));
    for (const block of found) {
      const declaration = expected.get(block.id);
      requireValue(declaration, document.path + ': unclassified snippet ' + block.id);
      requireValue(block.language === declaration.language, block.id + ': language changed without inventory review');
      requireValue(!blocks.has(block.id), 'Duplicate snippet label: ' + block.id);
      if (declaration.kind === 'excluded') requireValue(declaration.reason, block.id + ': excluded block needs a reason');
      else requireValue(['json', 'source'].includes(declaration.kind), block.id + ': unknown check kind');
      blocks.set(block.id, {...block, ...declaration, sha256: digest(block.source)});
      expected.delete(block.id);
    }
    requireValue(!expected.size, document.path + ': missing snippets');
    documents.push({path: document.path, sha256: digest(bytes)});
  }
  return {blocks, documents};
}

export function checkExpoRegistration(ts, source, nativeSessionSource) {
  const defaults = [...nativeSessionSource.matchAll(/public func start\(moduleName: String = "([^"]+)"/g)];
  requireValue(defaults.length === 1, 'Cannot determine the actual native Expo root registration contract');
  const expectedName = defaults[0][1];
  const file = ts.createSourceFile('index.ts', source, ts.ScriptTarget.Latest, true);
  const names = new Set();
  for (const node of file.statements) {
    if (!ts.isImportDeclaration(node) || node.moduleSpecifier.text !== 'react-native') continue;
    for (const item of node.importClause?.namedBindings?.elements ?? []) {
      if ((item.propertyName?.text ?? item.name.text) === 'AppRegistry') names.add(item.name.text);
    }
  }
  const registrations = [];
  function visit(node) {
    if (ts.isCallExpression(node) && ts.isPropertyAccessExpression(node.expression)
      && ts.isIdentifier(node.expression.expression) && names.has(node.expression.expression.text)
      && node.expression.name.text === 'registerComponent'
      && node.arguments[0] && ts.isStringLiteralLike(node.arguments[0])) registrations.push(node.arguments[0].text);
    ts.forEachChild(node, visit);
  }
  visit(file);
  requireValue(registrations.includes(expectedName),
    'Expo guide registers ' + JSON.stringify(registrations) + ', but the native foreground host requests ' + expectedName);
  return {expectedName, registrations, nativeSessionSHA256: digest(nativeSessionSource),
    mode: 'source-contract-check', nativeLaunch: 'NOT_RUN'};
}

export async function prepareGuideProjects({blocks, directory}) {
  const used = new Set();
  function block(id, kind) {
    const value = blocks.get(id);
    requireValue(value?.kind === kind, 'Missing ' + kind + ' snippet: ' + id);
    requireValue(!used.has(id), 'Snippet assigned twice: ' + id);
    used.add(id);
    return value;
  }
  const projects = [];
  async function project(name, engine, entries, scaffold) {
    const root = path.join(directory, name);
    await fs.mkdir(root, {recursive: true});
    const snippets = [];
    for (const [id, relative, kind, mode] of entries) {
      const value = block(id, kind);
      if (kind === 'json') JSON.parse(value.source);
      const file = path.join(root, relative);
      await fs.mkdir(path.dirname(file), {recursive: true});
      await fs.writeFile(file, value.source);
      snippets.push({id, file: relative, document: value.document, line: value.line,
        sha256: value.sha256, mode: mode ?? 'original-source-typecheck'});
    }
    const files = [];
    for (const [relative, value] of Object.entries(scaffold)) {
      const file = path.join(root, relative);
      await fs.mkdir(path.dirname(file), {recursive: true});
      const source = typeof value === 'string' ? value : JSON.stringify(value, null, 2) + '\n';
      await fs.writeFile(file, source);
      files.push({path: relative, sha256: digest(source)});
    }
    projects.push({name, engine, root, snippets, context: files});
  }
  await project('expo-guide', 'expo', [
    ['expo.app', 'App.tsx', 'source'],
    ['expo.registration', 'index.ts', 'source'],
    ['expo.script', 'script.json', 'json', 'public-authoring-loader-fields'],
    ['workflow.descriptor', 'hanlin.authoring.json', 'json', 'public-authoring-project-config']
  ], {
    'tsconfig.json': {compilerOptions: {strict: true, skipLibCheck: false}, include: ['*.ts', '*.tsx']},
    'package.json': {name: 'hanlin-guide-expo', version: '1.0.0', private: true},
    'data/catalog.json': {items: []}
  });
  await project('nativescript-guide', 'nativescript', [
    ['ns.construction', 'src/construction.js', 'source'],
    ['ns.initializers', 'src/initializers.js', 'source'],
    ['ns.factories', 'src/factories.js', 'source'],
    ['ns.properties', 'src/properties.js', 'source'],
    ['ns.callbacks', 'src/callbacks.js', 'source'],
    ['ns.presentation', 'src/presentation.js', 'source'],
    ['ns.tabs', 'src/tabs.js', 'source'],
    ['ns.swiftui-provider', 'src/swiftui-provider.ts', 'source'],
    ['ns.tsconfig', 'tsconfig.json', 'json', 'original-compiler-config'],
    ['ns.script', 'script.json', 'json', 'public-authoring-loader-fields'],
    ['ns.package', 'package.json', 'json', 'public-authoring-loader-fields'],
    ['readme.descriptor', 'hanlin.authoring.json', 'json', 'public-authoring-project-config']
  ], {
    // Each guide fragment has explicit native values/provider parameters.
    // This module is only a source entry; the checker executes no app source.
    'index.ts': ['construction.js', 'initializers.js', 'factories.js', 'properties.js',
      'callbacks.js', 'presentation.js', 'tabs.js', 'swiftui-provider']
      .map(file => "import './src/" + file + "';").join('\n') + '\n'
  });
  await project('scriptwidget-guide', 'scriptwidget', [
    ['widget.services', 'services.tsx', 'source'],
    ['widget.http', 'http.ts', 'source'],
    ['widget.presentation', 'presentation.tsx', 'source']
  ], {
    'hanlin.authoring.json': {schemaVersion: 1, engine: 'scriptwidget', entry: 'services.tsx', tsconfig: 'tsconfig.json'},
    'script.json': {name: 'ScriptWidget guide', version: '1.0.0', entry: 'services.tsx', widgetEngine: 'scriptwidget'},
    'tsconfig.json': {compilerOptions: {strict: true, skipLibCheck: false, moduleDetection: 'force'},
      include: ['*.ts', '*.tsx']}
  });
  await project('scriptwidget-controls', 'scriptwidget', [
    ['controls.manifest', 'widget.json', 'json', 'original-widget-manifest-semantic-validation'],
    ['controls.handler', 'main.jsx', 'source']
  ], {
    'hanlin.authoring.json': {schemaVersion: 1, engine: 'scriptwidget', entry: 'main.jsx', tsconfig: 'tsconfig.json'},
    'script.json': {name: 'Focus controls', version: '1.0.0', entry: 'main.jsx', widgetEngine: 'scriptwidget'},
    'tsconfig.json': {compilerOptions: {strict: true, skipLibCheck: false, checkJs: true}, files: ['main.jsx']}
  });
  const expected = [...blocks.values()].filter(item => item.kind !== 'excluded');
  requireValue(expected.length === used.size, 'A current authoring snippet has no executable/config check assignment');
  return projects;
}

export async function validateGuideProject(project, sdkRoot) {
  const report = await runMiniAppOperation({operation: 'validate', engine: project.engine, projectRoot: project.root}, {sdkRoot});
  requireValue(report.typecheck?.strict === true, project.name + ': source strict checking was not enabled');
  requireValue(report.typecheck.skipLibCheck === (project.engine === 'nativescript'),
    project.name + ': original SDK declaration-checking policy changed; review the actual contract');
  if (project.engine === 'nativescript' || project.name === 'scriptwidget-controls')
    requireValue(report.typecheck.checkJs === true, project.name + ': JavaScript semantic checking was not enabled');
  return report;
}

export async function checkAuthoringExamples({sdkRoot, root = repositoryRoot, outputDirectory,
  requireSDKDocs = false, documentOverrides = new Map()} = {}) {
  const guides = await readGuideExamples(root, documentOverrides);
  const sdk = await readMiniAppSDK(sdkRoot);
  const nativePath = 'Packages/HanlinExpoRuntime/Sources/HanlinExpoRuntime/HanlinExpoSession.swift';
  const nativeSource = await fs.readFile(path.join(root, nativePath), 'utf8');
  const ts = (await import(pathToFileURL(path.join(sdkRoot, sdk.engines.expo.typescriptPath)).href)).default;
  const registration = checkExpoRegistration(ts, guides.blocks.get('expo.registration').source, nativeSource);
  const documentation = [];
  for (const document of guides.documents) {
    const shipped = await fs.readFile(path.join(sdkRoot, document.path));
    const matches = digest(shipped) === document.sha256;
    requireValue(!requireSDKDocs || matches, document.path + ': staged SDK guide differs from the checked repository guide');
    documentation.push({...document, stagedSDKMatches: matches, stagedSDKSHA256: digest(shipped)});
  }
  const temporary = outputDirectory ?? await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-guide-check-'));
  try {
    const projects = await prepareGuideProjects({blocks: guides.blocks, directory: temporary});
    const results = [];
    for (const project of projects) {
      const validation = await validateGuideProject(project, sdkRoot);
      results.push({name: project.name, engine: project.engine, snippets: project.snippets,
        context: project.context, validation});
    }
    return {
      schemaVersion: 1, status: results.every(item => item.validation.succeeded) ? 'EXECUTED_PASS' : 'FAILED',
      scope: 'Static authoring examples in the six inventoried current public guides',
      sdk: {manifestSHA256: sdk.manifestSHA256, inputSHA256: sdk.inputSHA256},
      checkerInputs: await Promise.all([
        'Scripts/MiniApps/check-authoring-examples.mjs',
        'Scripts/MiniApps/authoring-examples.json',
        'AI_HLY/Downstream/RuntimeCore/Node/Host/miniapp-authoring.mjs'
      ].map(async file => ({path: file, sha256: digest(await fs.readFile(path.join(repositoryRoot, file)))}))),
      documentation, registration: {...registration, nativePath},
      sourceBlockCount: [...guides.blocks.values()].filter(item => item.kind === 'source').length,
      jsonBlockCount: [...guides.blocks.values()].filter(item => item.kind === 'json').length,
      projects: results,
      excluded: [...guides.blocks.values()].filter(item => item.kind === 'excluded')
        .map(({id, document, line, language, reason, sha256}) => ({id, document, line, language, reason, sha256, status: 'NOT_RUN'})),
      boundary: {
        code: 'Original TypeScript semantic checking through the public authoring validator; source is not executed.',
        json: 'Descriptors and compiler config are consumed by the production authoring path. Script/package metadata excerpts are parsed loader fields, not a full native prepared-package validation. Only widget.json runs the exported original manifest semantic validator.',
        shells: 'Repository commands and path placeholders are classified instructions, not executed shell examples.',
        nativeLaunch: 'NOT_RUN', deviceOperations: 'NOT_RUN', networkCalls: 'NOT_RUN'
      }
    };
  } finally {
    if (!outputDirectory) await fs.rm(temporary, {recursive: true, force: true});
  }
}

export function extractOriginalSDKArchive(archive, destination) {
  execFileSync('python3', ['-c', [
    'import pathlib, sys, zipfile',
    'target = pathlib.Path(sys.argv[2]).resolve()',
    'with zipfile.ZipFile(sys.argv[1]) as archive:',
    '    for item in archive.infolist():',
    '        if not item.filename.startswith("MiniAppSDK/") or item.is_dir(): continue',
    '        output = (target / item.filename).resolve()',
    '        if not output.is_relative_to(target / "MiniAppSDK"): raise ValueError("SDK archive path leaves extraction root")',
    '        output.parent.mkdir(parents=True, exist_ok=True)',
    '        output.write_bytes(archive.read(item))'
  ].join('\n'), archive, destination], {stdio: 'inherit'});
}

async function main() {
  const options = {};
  const args = process.argv.slice(2);
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--require-sdk-docs') options.requireSDKDocs = true;
    else if (['--sdk', '--sdk-archive', '--report', '--repository'].includes(args[i]) && args[i + 1])
      options[args[i].slice(2)] = args[++i];
    else throw new Error('Usage: check-authoring-examples.mjs (--sdk <directory> | --sdk-archive <verified RuntimeHost ZIP>) [--require-sdk-docs] [--report <JSON>] [--repository <root>]');
  }
  requireValue(Boolean(options.sdk) !== Boolean(options['sdk-archive']), 'Choose one original SDK directory or verified RuntimeHost ZIP');
  let extracted;
  let report;
  try {
    if (options['sdk-archive']) {
      extracted = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-guide-sdk-'));
      extractOriginalSDKArchive(path.resolve(options['sdk-archive']), extracted);
      options.sdk = path.join(extracted, 'MiniAppSDK');
    }
    report = await checkAuthoringExamples({sdkRoot: path.resolve(options.sdk),
      root: options.repository ? path.resolve(options.repository) : repositoryRoot,
      requireSDKDocs: options.requireSDKDocs});
  } catch (error) {
    report = {schemaVersion: 1, status: 'FAILED', error: error.message,
      boundary: {nativeLaunch: 'NOT_RUN', sourceExecution: 'NOT_RUN'}};
  } finally {
    if (extracted) await fs.rm(extracted, {recursive: true, force: true});
  }
  if (options.report) {
    await fs.mkdir(path.dirname(path.resolve(options.report)), {recursive: true});
    await writeJSON(path.resolve(options.report), report);
  }
  console.log(JSON.stringify({status: report.status, sourceBlocks: report.sourceBlockCount,
    jsonBlocks: report.jsonBlockCount, sdk: report.sdk, error: report.error,
    projects: report.projects?.map(item => ({name: item.name, succeeded: item.validation.succeeded,
      diagnostics: item.validation.diagnostics})), nativeLaunch: report.boundary.nativeLaunch}, null, 2));
  process.exitCode = report.status === 'EXECUTED_PASS' ? 0 : 1;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  await main();
