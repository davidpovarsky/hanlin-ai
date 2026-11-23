// Authoring uses original TypeScript and Metro APIs. No miniapp code is executed here.
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { createHash, randomUUID } from 'node:crypto';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const engines = new Set(['expo', 'nativescript', 'scriptwidget']);
const ignoredDirectories = new Set(['node_modules', '.git', 'dist', 'build', '.hanlin-build', '.hanlin-authoring']);
const slash = value => value.split(path.sep).join('/');
const sha256 = value => createHash('sha256').update(value).digest('hex');
const inside = (root, file) => {
  const relative = path.relative(root, file);
  return relative !== '..' && !relative.startsWith('..' + path.sep) && !path.isAbsolute(relative);
};
function child(root, name) {
  if (typeof name !== 'string' || !name || name.includes('\0') || path.isAbsolute(name)) throw new Error('A relative project path is required.');
  const resolved = path.resolve(root, name);
  if (!inside(root, resolved)) throw new Error('Project path leaves its source directory: ' + name);
  return resolved;
}
async function json(file) { return JSON.parse(await fs.readFile(file, 'utf8')); }
async function optionalJSON(file) {
  try { return await json(file); } catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}
async function writeJSON(file, value) {
  await fs.mkdir(path.dirname(file), { recursive: true });
  await fs.writeFile(file, JSON.stringify(value, null, 2) + '\n');
}
function finding(code, message, file, remediation) {
  return { code, category: 'error', message, ...(file ? {file} : {}), ...(remediation ? {remediation} : {}) };
}
function normalizedDiagnostic(ts, diagnostic, root) {
  const start = diagnostic.file && typeof diagnostic.start === 'number'
    ? diagnostic.file.getLineAndCharacterOfPosition(diagnostic.start) : null;
  const end = diagnostic.file && typeof diagnostic.start === 'number'
    ? diagnostic.file.getLineAndCharacterOfPosition(diagnostic.start + (diagnostic.length ?? 0)) : null;
  return {
    code: 'TS' + diagnostic.code,
    category: ts.DiagnosticCategory[diagnostic.category]?.toLowerCase() ?? 'error',
    message: ts.flattenDiagnosticMessageText(diagnostic.messageText, '\n'),
    ...(diagnostic.file ? {file: slash(path.relative(root, diagnostic.file.fileName))} : {}),
    ...(start ? {line: start.line + 1, column: start.character + 1} : {}),
    ...(end ? {endLine: end.line + 1, endColumn: end.character + 1} : {})
  };
}
function deduplicate(diagnostics) {
  return [...new Map(diagnostics.map(item => [JSON.stringify(item), item])).values()];
}

export async function readMiniAppSDK(sdkRoot, request = {}) {
  const root = await fs.realpath(sdkRoot);
  const bytes = await fs.readFile(path.join(root, 'miniapp-sdk.json'));
  const manifest = JSON.parse(bytes);
  if (manifest.schemaVersion !== 1 || !manifest.engines) throw new Error('Unsupported MiniApp SDK manifest.');
  if (request.engine && (!engines.has(request.engine) || !manifest.engines[request.engine]))
    throw new Error('The requested engine is not present in this host SDK: ' + request.engine);
  if (request.resource) {
    const resource = child(root, request.resource);
    const actual = await fs.realpath(resource);
    if (!inside(root, actual)) throw new Error('SDK resource resolves outside its SDK.');
    return {schemaVersion: 1, resource: request.resource, content: await fs.readFile(actual, 'utf8'),
      manifestSHA256: sha256(bytes)};
  }
  return {
    ...manifest, sdkRoot: root, manifestSHA256: sha256(bytes),
    ...(request.engine ? {engine: request.engine, selectedEngine: manifest.engines[request.engine]} : {}),
    authoring: {
      config: 'hanlin.authoring.json',
      operations: ['get_miniapp_sdk', 'validate_miniapp', 'build_miniapp', 'import_miniapp'],
      sourceRetention: 'source/',
      template: {schemaVersion: 1, engine: request.engine ?? 'expo', entry: 'index.tsx', tsconfig: 'tsconfig.json'},
      instructions: [
        'Use the selected engine packageVersions and original declarations in toolingRoot.',
        'Create script.json, package.json, tsconfig.json, an entry source, and hanlin.authoring.json in a project directory.',
        'Run validate_miniapp; repair every error using the reported file and one-based line/column.',
        'Run build_miniapp, then import_miniapp with archive_path from the successful build report.',
        'A queued import is not yet installed; retain its transfer ID and inspect the receiver result.'
      ]
    }
  };
}

async function projectInput(request) {
  const project = await fs.realpath(request.projectRoot);
  let author = await optionalJSON(path.join(project, 'hanlin.authoring.json')) ?? {};
  if (author.schemaVersion !== undefined && author.schemaVersion !== 1) throw new Error('Unsupported hanlin.authoring.json version.');
  const packagedAuthor = author.sourceRoot ? author : null;
  const sourceRoot = author.sourceRoot ? await fs.realpath(child(project, author.sourceRoot)) : project;
  if (!inside(project, sourceRoot)) throw new Error('Authoring sources resolve outside the package.');
  // The original project metadata survives archive import; the outer file binds the source root.
  if (sourceRoot !== project) author = {...author, ...(await optionalJSON(path.join(sourceRoot, 'hanlin.authoring.json')) ?? {})};
  const script = await json(path.join(sourceRoot, 'script.json'));
  const pkg = await optionalJSON(path.join(sourceRoot, 'package.json')) ?? {};
  const inferred = script.widgetEngine === 'scriptwidget' ? 'scriptwidget'
    : script.hanlinRuntime === 'hanlin-expo' ? 'expo'
    : script.hanlinRuntime === 'hanlin-nativescript' ? 'nativescript' : null;
  const engine = request.engine ?? author.engine ?? inferred;
  if (!engines.has(engine)) throw new Error('Specify expo, nativescript, or scriptwidget in hanlin.authoring.json.');
  if (author.engine && author.engine !== engine) throw new Error('Requested engine differs from the authoring project.');
  if (inferred && inferred !== engine) throw new Error('script.json runtime differs from the authoring engine.');
  const entry = author.entry ?? (engine === 'scriptwidget' ? script.entry : null);
  if (!entry) throw new Error('hanlin.authoring.json must declare the source entry (for example index.tsx).');
  const entryFile = child(sourceRoot, entry);
  if (!(await fs.stat(entryFile)).isFile()) throw new Error('Authoring entry must be a source file.');
  return {project, sourceRoot, author, packagedAuthor, script, pkg, engine, entry, entryFile};
}

async function fileHashes(root, exclude = new Set()) {
  const hashes = {};
  async function walk(directory, prefix = '') {
    for (const entry of await fs.readdir(directory, {withFileTypes: true})) {
      if (!prefix && exclude.has(entry.name)) continue;
      const name = prefix ? prefix + '/' + entry.name : entry.name;
      if (entry.isDirectory()) await walk(path.join(directory, entry.name), name);
      else if (entry.isFile()) hashes[name] = sha256(await fs.readFile(path.join(directory, entry.name)));
    }
  }
  await walk(root);
  return hashes;
}

async function packageConsistency(input) {
  if (!input.packagedAuthor) return [];
  const diagnostics = [];
  for (const [field, root, code] of [
    ['sourceHashes', input.sourceRoot, 'MINIAPP_SOURCE_CHANGED'],
    ['compiledHashes', input.project, 'MINIAPP_COMPILED_OUTPUT_CHANGED']
  ]) {
    const hashes = input.packagedAuthor[field];
    if (!hashes || typeof hashes !== 'object' || !Object.keys(hashes).length) {
      diagnostics.push(finding('MINIAPP_BUILD_IDENTITY_MISSING', 'The source-preserving package has no ' + field + ' build identity.',
        'hanlin.authoring.json', 'Build again from ' + input.sourceRoot + ' with build_miniapp.'));
      continue;
    }
    for (const [name, expected] of Object.entries(hashes)) {
      let actual;
      try { actual = sha256(await fs.readFile(child(root, name))); } catch {}
      if (actual !== expected) diagnostics.push(finding(code, 'The package no longer matches its recorded build: ' + name,
        name, 'Repair and validate the source project, then build a fresh archive before importing.'));
    }
  }
  return diagnostics;
}

async function parseProject(ts, input, sdkRoot, sdkEngine) {
  const basePath = sdkEngine.tsconfigPath ? child(sdkRoot, sdkEngine.tsconfigPath) : null;
  let base = {options: {}, errors: []};
  if (basePath) {
    const config = ts.readConfigFile(basePath, ts.sys.readFile);
    base = ts.parseJsonConfigFileContent(config.config ?? {}, ts.sys, path.dirname(basePath), {}, basePath);
    if (config.error) base.errors.push(config.error);
    // Base templates describe options/types. A template without root source files is expected.
    base.errors = base.errors.filter(item => item.code !== 18003);
  }
  const configPath = child(input.sourceRoot, input.author.tsconfig ?? 'tsconfig.json');
  const sourceConfig = ts.readConfigFile(configPath, ts.sys.readFile);
  const config = sourceConfig.config ?? {};
  const parsed = ts.parseJsonConfigFileContent(config, ts.sys, path.dirname(configPath), {}, configPath);
  const toolingRoot = child(sdkRoot, sdkEngine.toolingRoot);
  const options = {
    target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext,
    moduleResolution: ts.ModuleResolutionKind.Bundler,
    strict: true, allowJs: true, noEmit: true,
    ...base.options, ...parsed.options,
    noEmit: true, incremental: false, composite: false,
    typeRoots: [...new Set([...(parsed.options.typeRoots ?? []), ...(base.options.typeRoots ?? []),
      path.join(toolingRoot, 'node_modules', '@types')])],
    paths: {...base.options.paths, ...parsed.options.paths}
  };
  const compilerHost = ts.createCompilerHost(options);
  const sdkOptions = {...options, baseUrl: toolingRoot,
    paths: {...options.paths, '*': [path.join(toolingRoot, 'node_modules', '*')]}};
  // Resolve original dependencies through the installed host's SDK when this project has no local npm tree.
  compilerHost.resolveModuleNames = (names, containingFile) => names.map(name =>
    ts.resolveModuleName(name, containingFile, options, compilerHost).resolvedModule
    ?? ts.resolveModuleName(name, containingFile, sdkOptions, compilerHost).resolvedModule);
  compilerHost.resolveTypeReferenceDirectives = (names, containingFile, redirectedReference, compilerOptions) =>
    names.map(name => {
      const requested = typeof name === 'string' ? name : name.fileName;
      return ts.resolveTypeReferenceDirective(requested, containingFile, compilerOptions ?? options, compilerHost, redirectedReference).resolvedTypeReferenceDirective
        ?? ts.resolveTypeReferenceDirective(path.join(toolingRoot, 'node_modules', requested), containingFile, compilerOptions ?? options, compilerHost, redirectedReference).resolvedTypeReferenceDirective;
    });
  const rootNames = [...new Set([...parsed.fileNames, input.entryFile,
    ...(base.fileNames ?? []).filter(file => file.endsWith('.d.ts'))])];
  const program = ts.createProgram({rootNames, options, host: compilerHost, projectReferences: parsed.projectReferences});
  const diagnostics = [...base.errors, ...(sourceConfig.error ? [sourceConfig.error] : []),
    ...parsed.errors, ...ts.getPreEmitDiagnostics(program)];
  return {program, compilerHost, options, sdkOptions, toolingRoot,
    diagnostics: deduplicate(diagnostics.map(item => normalizedDiagnostic(ts, item, input.sourceRoot)))};
}

async function retainSources(input, stage) {
  const destination = path.join(stage, 'source');
  const hashes = {};
  async function walk(directory, relative = '', ancestors = new Set()) {
    const actual = await fs.realpath(directory);
    if (ancestors.has(actual)) throw new Error('Project source contains a circular directory link: ' + relative);
    const nextAncestors = new Set([...ancestors, actual]);
    for (const entry of await fs.readdir(directory, {withFileTypes: true})) {
      if (ignoredDirectories.has(entry.name)) continue;
      const name = relative ? relative + '/' + entry.name : entry.name;
      const file = path.join(directory, entry.name);
      const stat = entry.isSymbolicLink() ? await fs.stat(file) : entry;
      if (stat.isDirectory()) { await walk(file, name, nextAncestors); continue; }
      if (!stat.isFile()) continue;
      const bytes = await fs.readFile(file);
      const target = child(destination, name);
      await fs.mkdir(path.dirname(target), {recursive: true});
      await fs.writeFile(target, bytes);
      hashes[name] = sha256(bytes);
    }
  }
  await walk(input.sourceRoot);
  for (const resource of input.author.resources ?? []) {
    const source = child(input.sourceRoot, resource);
    const actual = await fs.realpath(source);
    if (!inside(input.sourceRoot, actual)) throw new Error('Resource leaves the project: ' + resource);
    const bytes = await fs.readFile(actual);
    const target = child(destination, resource);
    await fs.mkdir(path.dirname(target), {recursive: true});
    await fs.writeFile(target, bytes);
    hashes[resource] = sha256(bytes);
  }
  return hashes;
}

async function copyResources(input, root) {
  for (const resource of input.author.resources ?? []) {
    const from = child(input.sourceRoot, resource);
    const to = child(root, resource);
    await fs.mkdir(path.dirname(to), {recursive: true});
    await fs.copyFile(from, to);
  }
}

function relativeImportTransformer(ts, parsed, input) {
  return context => {
    const rewrite = (specifier, sourceFile) => {
      if (!ts.isStringLiteral(specifier) || !specifier.text.startsWith('.')) return specifier;
      const resolved = ts.resolveModuleName(specifier.text, sourceFile.fileName, parsed.options, parsed.compilerHost).resolvedModule;
      if (!resolved || !inside(input.sourceRoot, resolved.resolvedFileName) || resolved.resolvedFileName.endsWith('.d.ts')) return specifier;
      const relative = slash(path.relative(path.dirname(sourceFile.fileName), resolved.resolvedFileName)).replace(/\.(tsx?|jsx?|mts|cts)$/, '.js');
      return ts.factory.createStringLiteral(relative.startsWith('.') ? relative : './' + relative);
    };
    return sourceFile => {
      const visit = node => {
        if (ts.isImportDeclaration(node))
          return ts.factory.updateImportDeclaration(node, node.modifiers, node.importClause, rewrite(node.moduleSpecifier, sourceFile), node.attributes);
        if (ts.isExportDeclaration(node) && node.moduleSpecifier)
          return ts.factory.updateExportDeclaration(node, node.modifiers, node.isTypeOnly, node.exportClause, rewrite(node.moduleSpecifier, sourceFile), node.attributes);
        if (ts.isCallExpression(node) && node.expression.kind === ts.SyntaxKind.ImportKeyword && node.arguments.length)
          return ts.factory.updateCallExpression(node, node.expression, node.typeArguments, [rewrite(node.arguments[0], sourceFile), ...node.arguments.slice(1)]);
        return ts.visitEachChild(node, visit, context);
      };
      return ts.visitNode(sourceFile, visit);
    };
  };
}

async function buildNativeScript(ts, input, parsed, stage, sdkEngine) {
  const app = path.join(stage, 'nativescript', 'app');
  const modules = path.join(app, 'modules');
  const options = {...parsed.options, noEmit: false, noEmitOnError: true,
    declaration: false, declarationMap: false, emitDeclarationOnly: false,
    rootDir: input.sourceRoot, outDir: modules, sourceMap: true, inlineSources: true,
    module: ts.ModuleKind.ESNext, moduleResolution: ts.ModuleResolutionKind.Bundler};
  const sourceFiles = parsed.program.getSourceFiles().filter(file =>
    inside(input.sourceRoot, file.fileName) && !file.isDeclarationFile && !file.fileName.includes(path.sep + 'node_modules' + path.sep));
  const host = ts.createCompilerHost(options);
  host.resolveModuleNames = parsed.compilerHost.resolveModuleNames;
  host.resolveTypeReferenceDirectives = parsed.compilerHost.resolveTypeReferenceDirectives;
  const program = ts.createProgram({rootNames: [...sourceFiles.map(file => file.fileName),
    ...parsed.program.getRootFileNames().filter(file => file.endsWith('.d.ts'))], options, host});
  const diagnostics = ts.getPreEmitDiagnostics(program);
  if (diagnostics.some(item => item.category === ts.DiagnosticCategory.Error))
    return diagnostics.map(item => normalizedDiagnostic(ts, item, input.sourceRoot));
  const pending = [];
  const emitted = program.emit(undefined, (file, text) => {
    if (!inside(modules, path.resolve(file))) throw new Error('Compiler output leaves the prepared app.');
    pending.push(fs.mkdir(path.dirname(file), {recursive: true}).then(() => fs.writeFile(file, text)));
  }, undefined, undefined, {before: [relativeImportTransformer(ts, parsed, input)]});
  await Promise.all(pending);
  const entry = slash(input.entry).replace(/\.(tsx?|jsx?|mts|cts)$/, '.js');
  await fs.mkdir(app, {recursive: true});
  await fs.writeFile(path.join(app, 'bundle.mjs'), 'import ' + JSON.stringify('./modules/' + entry) + ';\n');
  await writeJSON(path.join(app, 'package.json'), {
    ...input.pkg, main: 'bundle.mjs', type: 'module', hanlinRuntime: 'hanlin-nativescript',
    hanlinNativeScript: {...input.pkg.hanlinNativeScript,
      runtimeVersion: sdkEngine.packageVersions?.['@nativescript/ios'] ?? sdkEngine.packageVersions?.['@nativescript/core']},
  });
  await copyResources(input, modules);
  await writeJSON(path.join(stage, 'script.json'), {...input.script,
    entry: 'nativescript/app/bundle.mjs', runInApp: true, hanlinRuntime: 'hanlin-nativescript'});
  return emitted.diagnostics.map(item => normalizedDiagnostic(ts, item, input.sourceRoot));
}

async function buildExpo(input, parsed, stage) {
  const requireSDK = createRequire(path.join(parsed.toolingRoot, 'package.json'));
  const metro = requireSDK('metro');
  const {getDefaultConfig, mergeConfig} = requireSDK('@react-native/metro-config');
  // The original configuration supplies the actual NativeScript/Worklets Babel plugins.
  let original = {};
  try { original = requireSDK(path.join(parsed.toolingRoot, 'metro.config.cjs')); }
  catch (error) { if (error.code !== 'MODULE_NOT_FOUND') throw error; }
  const config = mergeConfig(getDefaultConfig(parsed.toolingRoot), original, {
    projectRoot: parsed.toolingRoot,
    watchFolders: [input.sourceRoot, parsed.toolingRoot],
    maxWorkers: 1,
    resolver: {useWatchman: false,
      nodeModulesPaths: [path.join(input.sourceRoot, 'node_modules'), path.join(parsed.toolingRoot, 'node_modules')]},
    watcher: {healthCheck: {enabled: false}},
    fileMapCacheDirectory: path.join(stage, '.metro-cache'),
    cacheStores: [],
    transformer: {unstable_allowRequireContext: true}
  });
  // This original Metro version uses its Node filesystem crawler with useWatchman=false.
  // maxWorkers=1 also keeps both compiler worker pools inside the existing Node process.
  config.resolver.unstable_enablePackageExports = true;
  const result = await metro.runBuild(config, {
    entry: input.entryFile, bundleOut: path.join(stage, 'bundle.js'), platform: 'ios',
    dev: false, minify: false, sourceMap: true, sourceMapOut: path.join(stage, 'bundle.js.map'),
    sourceMapUrl: 'bundle.js.map', assets: true
  });
  if (!result?.code && !(await fs.stat(path.join(stage, 'bundle.js'))).isFile()) throw new Error('Metro produced no bundle.');
  if (result.assets?.length) {
    const pluginRoot = path.dirname(requireSDK.resolve('@react-native/community-cli-plugin/package.json'));
    const saveAssets = requireSDK(path.join(pluginRoot, 'dist/commands/bundle/saveAssets.js')).default;
    await saveAssets(result.assets, 'ios', stage);
  }
  await fs.rm(path.join(stage, '.metro-cache'), {recursive: true, force: true});
  await copyResources(input, stage);
  await writeJSON(path.join(stage, 'script.json'), {...input.script, entry: 'bundle.js', runInApp: true, hanlinRuntime: 'hanlin-expo'});
  await writeJSON(path.join(stage, 'package.json'), {...input.pkg, main: 'bundle.js', hanlinRuntime: 'hanlin-expo'});
}

async function buildScriptWidget(input, parsed, stage) {
  // Keep original JSX/TSX for the installed original ScriptWidget compiler/runtime.
  for (const source of parsed.program.getSourceFiles()) {
    if (source.isDeclarationFile || !inside(input.sourceRoot, source.fileName) ||
      source.fileName.includes(path.sep + 'node_modules' + path.sep)) continue;
    const target = child(stage, path.relative(input.sourceRoot, source.fileName));
    await fs.mkdir(path.dirname(target), {recursive: true});
    await fs.copyFile(source.fileName, target);
  }
  await copyResources(input, stage);
  await writeJSON(path.join(stage, 'script.json'), {...input.script, kind: 'widget',
    entry: input.entry, widgetEngine: 'scriptwidget', hanlinRuntime: 'scripting-jsc'});
  if (Object.keys(input.pkg).length) await writeJSON(path.join(stage, 'package.json'), input.pkg);
}

export async function runMiniAppOperation(request, {sdkRoot, compiler} = {}) {
  if (request.operation === 'sdk') return readMiniAppSDK(sdkRoot, request);
  if (!['validate', 'build'].includes(request.operation)) throw new Error('Unknown MiniApp authoring operation.');
  let input;
  let stage;
  let ownsStage = false;
  const report = {schemaVersion: 1, engine: request.engine ?? 'unknown', operation: request.operation,
    succeeded: false, diagnostics: []};
  try {
    input = await projectInput(request);
    report.engine = input.engine;
    report.sourceRoot = input.sourceRoot;
    const sdk = await readMiniAppSDK(sdkRoot, {engine: input.engine});
    const descriptor = sdk.selectedEngine;
    const ts = compiler ?? (descriptor.typescriptPath
      ? (await import(pathToFileURL(child(sdk.sdkRoot, descriptor.typescriptPath)).href)).default
      : (await import('typescript')).default);
    if (!ts?.createProgram) throw new Error('The original TypeScript compiler is unavailable in this SDK.');
    report.sdk = {packageVersions: descriptor.packageVersions ?? {},
      manifestSHA256: sdk.manifestSHA256, compilerVersion: ts.version};
    const parsed = await parseProject(ts, input, sdk.sdkRoot, descriptor);
    report.diagnostics = [...parsed.diagnostics, ...await packageConsistency(input)];
    if (report.diagnostics.some(item => item.category === 'error')) return report;
    if (request.operation === 'validate') { report.succeeded = true; return report; }
    stage = request.outputDirectory ? path.resolve(request.outputDirectory)
      : path.join(input.project, '.hanlin-build', randomUUID(), 'package');
    if (inside(stage, input.sourceRoot) || stage === input.sourceRoot) throw new Error('Build output must not contain the source project.');
    // Never reuse stale output or overwrite another build.
    await fs.mkdir(path.dirname(stage), {recursive: true});
    await fs.mkdir(stage, {recursive: false});
    ownsStage = true;
    const sourceHashes = await retainSources(input, stage);
    if (input.engine === 'nativescript')
      report.diagnostics.push(...await buildNativeScript(ts, input, parsed, stage, descriptor));
    else if (input.engine === 'expo') await buildExpo(input, parsed, stage);
    else await buildScriptWidget(input, parsed, stage);
    if (report.diagnostics.some(item => item.category === 'error')) return report;
    await writeJSON(path.join(stage, 'hanlin.authoring.json'), {
      schemaVersion: 1, engine: input.engine, entry: input.entry,
      tsconfig: input.author.tsconfig ?? 'tsconfig.json', sourceRoot: 'source',
      sourceHashes, compiledHashes: await fileHashes(stage, new Set(['source'])), sdk: report.sdk
    });
    report.preparedPackagePath = stage;
    report.succeeded = true;
    await writeJSON(path.join(stage, 'hanlin.validation.json'), {...report, sourceRoot: 'source', preparedPackagePath: undefined});
    return report;
  } catch (error) {
    const file = error.filename ?? error.loc?.filename;
    const diagnostic = finding('MINIAPP_AUTHORING_FAILED', error.message,
      file && input ? slash(path.relative(input.sourceRoot, file)) : file,
      'Read get_miniapp_sdk for this installed host, repair the source/configuration, then validate again.');
    const line = error.lineNumber ?? error.loc?.line;
    const column = error.column ?? error.loc?.column;
    if (Number.isInteger(line)) diagnostic.line = line;
    if (Number.isInteger(column)) diagnostic.column = column + 1;
    report.diagnostics.push(diagnostic);
    return report;
  } finally {
    if (ownsStage && !report.succeeded) await fs.rm(stage, {recursive: true, force: true});
  }
}
