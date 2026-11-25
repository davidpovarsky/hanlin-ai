// Authoring uses original TypeScript and Metro APIs. No miniapp code is executed here.
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { createHash, randomUUID } from 'node:crypto';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import {assistantToolSourceEntries, assistantToolWrapper} from './miniapp-assistant-tools.mjs';

const engines = new Set(['expo', 'nativescript', 'scriptwidget']);
const ignoredDirectories = new Set(['node_modules', '.git', '.hanlin-build', '.hanlin-authoring']);
const slash = value => value.split(path.sep).join('/');
const packageName = name => name.startsWith('.') || path.isAbsolute(name) ? null
  : name.startsWith('@') ? name.split('/').slice(0, 2).join('/') : name.split('/')[0];
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
  const {files, sourceInputs, ...metadata} = manifest;
  const described = {};
  for (const [name, descriptor] of Object.entries(manifest.engines)) {
    if (request.engine && name !== request.engine) continue;
    const packageResources = [];
    for (const packageName of Object.keys(descriptor.packageVersions ?? {})) {
      const packagePath = path.posix.join(descriptor.toolingRoot, 'node_modules', packageName, 'package.json');
      const pkg = await optionalJSON(child(root, packagePath));
      if (!pkg) continue;
      const declaration = pkg.types ?? pkg.typings;
      packageResources.push({name: packageName, packageJSON: packagePath,
        ...(typeof declaration === 'string' ? {types: path.posix.join(path.posix.dirname(packagePath), declaration)} : {})});
    }
    const config = descriptor.tsconfigPath ? await optionalJSON(child(root, descriptor.tsconfigPath)) : null;
    const declarations = (config?.files ?? []).map(file => path.posix.join(path.posix.dirname(descriptor.tsconfigPath), file));
    described[name] = {...descriptor, packageResources, declarationEntrypoints: declarations};
  }
  return {
    ...metadata, engines: {...manifest.engines, ...described}, sdkRoot: root, manifestSHA256: sha256(bytes),
    inventory: {resource: 'miniapp-sdk.json', fileCount: files?.length ?? 0, sourceInputCount: sourceInputs?.length ?? 0},
    ...(request.engine ? {engine: request.engine, selectedEngine: described[request.engine]} : {}),
    authoring: {
      config: 'hanlin.authoring.json',
      ...(files?.some(file => file.path === 'docs/miniapp-sdk/AUTHORING_WORKFLOW.md')
        ? {documentation: 'docs/miniapp-sdk/AUTHORING_WORKFLOW.md'} : {}),
      operations: ['get_miniapp_sdk', 'write_miniapp', 'validate_miniapp', 'build_miniapp', 'import_miniapp'],
      sourceRetention: 'source/',
      template: {schemaVersion: 1, engine: request.engine ?? 'expo', entry: 'index.tsx', tsconfig: 'tsconfig.json'},
      instructions: [
        'Use the selected engine packageVersions and original declarations in toolingRoot.',
        'For chat tools, declare assistantTool metadata and map each entrypoint ID to a dedicated source in hanlin.authoring.json assistantTools. Import @hanlin/assistant-tools with import type.',
        'Use write_miniapp to create script.json, package.json, tsconfig.json, an entry source, and hanlin.authoring.json; it returns a writable sourceRoot.',
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
  const assistant = assistantToolSourceEntries(script, {...author, entry}, engine);
  const assistantTools = [];
  for (const tool of assistant.entries) {
    const sourceFile = child(sourceRoot, tool.source);
    if (!(await fs.stat(sourceFile).then(info => info.isFile(), () => false))) {
      assistant.diagnostics.push(finding('MINIAPP_ASSISTANT_SOURCE_MISSING',
        'The dedicated assistant source does not exist: ' + tool.source, 'hanlin.authoring.json'));
      continue;
    }
    if (!inside(sourceRoot, await fs.realpath(sourceFile))) throw new Error('Assistant source leaves its project.');
    assistantTools.push({...tool, sourceFile});
  }
  return {project, sourceRoot, author, packagedAuthor, script, pkg, engine, entry, entryFile,
    assistantTools, assistantDiagnostics: assistant.diagnostics};
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

async function parseProject(ts, input, sdkRoot, sdkEngine, fallbackConfig, useProjectConfig = true) {
  const basePath = sdkEngine.tsconfigPath ? child(sdkRoot, sdkEngine.tsconfigPath) : null;
  let base = {options: {}, errors: []};
  if (basePath) {
    const config = ts.readConfigFile(basePath, ts.sys.readFile);
    base = ts.parseJsonConfigFileContent(config.config ?? {}, ts.sys, path.dirname(basePath), {}, basePath);
    if (config.error) base.errors.push(config.error);
    // Base templates describe options/types. A template without root source files is expected.
    base.errors = base.errors.filter(item => item.code !== 18003);
  }
  const toolingRoot = child(sdkRoot, sdkEngine.toolingRoot);
  const originalPackages = new Set(Object.keys(sdkEngine.packageVersions ?? {}));
  const isOriginalPackage = name => originalPackages.has(packageName(name));
  const configPath = child(input.sourceRoot, input.author.tsconfig ?? 'tsconfig.json');
  const sourceConfig = fallbackConfig && (!useProjectConfig || !ts.sys.fileExists(configPath))
    ? {config: fallbackConfig} : ts.readConfigFile(configPath, ts.sys.readFile);
  const config = {...sourceConfig.config};
  if (input.originalWidgetManifestText !== undefined)
    config.compilerOptions = {...config.compilerOptions, allowJs: true, checkJs: true};
  const resolveExtendedConfig = value => {
    if (typeof value !== 'string' || value.startsWith('.') || path.isAbsolute(value)) return value;
    if (isOriginalPackage(value) && !ts.sys.fileExists(path.join(toolingRoot, 'node_modules', packageName(value), 'package.json')))
      return path.join(toolingRoot, 'node_modules', value);
    const roots = isOriginalPackage(value) ? [toolingRoot] : [input.sourceRoot, toolingRoot];
    for (const root of roots) {
      const resolve = createRequire(path.join(root, 'package.json')).resolve;
      for (const specifier of [value, path.join(root, 'node_modules', value)]) {
        try {
          const resolved = resolve(specifier);
          if (!isOriginalPackage(value) || inside(ts.sys.realpath(path.join(toolingRoot, 'node_modules', packageName(value))), resolved)) return resolved;
        } catch (error) { if (!['MODULE_NOT_FOUND', 'ERR_PACKAGE_PATH_NOT_EXPORTED'].includes(error.code)) throw error; }
      }
    }
    // A missing canonical config must not fall back to another checkout's package.
    return isOriginalPackage(value) ? path.join(toolingRoot, 'node_modules', value) : value;
  };
  if (config.extends) config.extends = Array.isArray(config.extends)
    ? config.extends.map(resolveExtendedConfig) : resolveExtendedConfig(config.extends);
  const parsed = ts.parseJsonConfigFileContent(config, ts.sys, path.dirname(configPath), {}, configPath);
  const options = {
    target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext,
    moduleResolution: ts.ModuleResolutionKind.Bundler,
    strict: true, allowJs: true, noEmit: true,
    ...base.options, ...parsed.options,
    ...(input.originalWidgetManifestText !== undefined ? {allowJs: true, checkJs: true} : {}),
    noEmit: true, incremental: false, composite: false,
    typeRoots: [...new Set([...(parsed.options.typeRoots ?? []), ...(base.options.typeRoots ?? []),
      path.join(toolingRoot, 'node_modules', '@types')])],
    paths: {...base.options.paths, ...parsed.options.paths}
  };
  const compilerHost = ts.createCompilerHost(options);
  const sdkOptions = {...options, baseUrl: undefined, paths: undefined,
    typeRoots: [...new Set([...(base.options.typeRoots ?? []), path.join(toolingRoot, 'node_modules', '@types')])]};
  const sdkContainingFile = path.join(toolingRoot, '__hanlin_authoring__.ts');
  // TypeScript normally walks every ancestor node_modules directory. SDK
  // dependencies may use their own nested packages, but never another checkout.
  const sdkLookup = file => !path.resolve(file).split(path.sep).includes('node_modules') || inside(toolingRoot, path.resolve(file));
  const sdkResolutionHost = {...compilerHost,
    fileExists: file => sdkLookup(file) && compilerHost.fileExists(file),
    readFile: file => sdkLookup(file) ? compilerHost.readFile(file) : undefined,
    directoryExists: directory => sdkLookup(directory) && compilerHost.directoryExists(directory),
    getDirectories: directory => sdkLookup(directory) ? compilerHost.getDirectories(directory).filter(sdkLookup) : []
  };
  const sdkSource = file => file && inside(toolingRoot, file);
  const resolveModule = (name, containingFile) => {
    const fromSDK = sdkSource(containingFile);
    const original = isOriginalPackage(name);
    // The supplied host owns its canonical React/Expo/NativeScript packages.
    // Keep SDK-local nested dependencies, relative imports and project aliases;
    // never satisfy a missing canonical export from an ancestor installation.
    if (fromSDK || original) {
      return (fromSDK ? ts.resolveModuleName(name, containingFile, sdkOptions, sdkResolutionHost).resolvedModule : undefined)
        ?? (packageName(name) ? ts.resolveModuleName(name, sdkContainingFile, sdkOptions, sdkResolutionHost).resolvedModule : undefined);
    }
    return ts.resolveModuleName(name, containingFile, options, compilerHost).resolvedModule
      ?? (packageName(name) ? ts.resolveModuleName(name, sdkContainingFile, sdkOptions, sdkResolutionHost).resolvedModule : undefined);
  };
  compilerHost.resolveModuleNames = (names, containingFile) => names.map(name => resolveModule(name, containingFile));
  compilerHost.resolveTypeReferenceDirectives = (names, containingFile, redirectedReference, compilerOptions) =>
    names.map(name => {
      const requested = typeof name === 'string' ? name : name.fileName;
      const fromSDK = sdkSource(containingFile);
      const original = isOriginalPackage(requested) || originalPackages.has('@types/' + requested.replace(/^@/, '').replace('/', '__'));
      const origins = fromSDK ? [[containingFile, sdkOptions], [sdkContainingFile, sdkOptions]]
        : original ? [[sdkContainingFile, sdkOptions]]
        : [[containingFile, compilerOptions ?? options], [sdkContainingFile, sdkOptions]];
      for (const [origin, settings] of origins) {
        const resolved = ts.resolveTypeReferenceDirective(requested, origin, settings, settings === sdkOptions ? sdkResolutionHost : compilerHost, redirectedReference).resolvedTypeReferenceDirective;
        if (resolved) return resolved;
      }
      const module = ts.resolveModuleName(requested, sdkContainingFile, sdkOptions, sdkResolutionHost).resolvedModule;
      return module && /\.d\.[cm]?ts$/.test(module.resolvedFileName)
        ? {primary: false, resolvedFileName: module.resolvedFileName, packageId: module.packageId, isExternalLibraryImport: true}
        : undefined;
    });
  const rootNames = [...new Set([...parsed.fileNames, input.entryFile, ...input.assistantTools.map(tool => tool.sourceFile),
    ...(base.fileNames ?? []).filter(file => file.endsWith('.d.ts'))])];
  const program = ts.createProgram({rootNames, options, host: compilerHost, projectReferences: parsed.projectReferences});
  const diagnostics = [...base.errors, ...(sourceConfig.error ? [sourceConfig.error] : []),
    ...parsed.errors, ...ts.getPreEmitDiagnostics(program)];
  return {program, compilerHost, options, sdkOptions, toolingRoot, originalPackages,
    diagnostics: deduplicate(diagnostics.map(item => normalizedDiagnostic(ts, item, input.sourceRoot)))};
}


async function validateNativePresentations(input, sdk, compiler) {
  const declarations = input.script.nativePresentations;
  if (!declarations) return {programs: [], sourceFiles: [], diagnostics: []};
  if (typeof declarations !== 'object' || Array.isArray(declarations))
    return {programs: [], sourceFiles: [], diagnostics: [finding('MINIAPP_NATIVE_PRESENTATIONS_INVALID',
      'nativePresentations must map entrypoint IDs to native presentation descriptors.', 'script.json')]};
  const programs = [];
  const sourceFiles = [];
  const diagnostics = [];
  const visited = new Set();
  for (const [identifier, presentation] of Object.entries(declarations)) {
    if (!presentation || !['expo', 'scriptwidget'].includes(presentation.engine) ||
        !['jsx', 'tsx', 'javascript', 'expo-layout'].includes(presentation.sourceFormat) ||
        (presentation.sourceFormat === 'expo-layout' && presentation.engine !== 'expo') ||
        typeof presentation.sourcePath !== 'string') {
      diagnostics.push(finding('MINIAPP_NATIVE_PRESENTATION_INVALID',
        'Native presentation ' + identifier + ' must declare an Expo or ScriptWidget renderer, a supported sourceFormat, and sourcePath.', 'script.json'));
      continue;
    }
    const entryFile = child(input.sourceRoot, presentation.sourcePath);
    const identity = presentation.engine + ':' + entryFile;
    if (visited.has(identity)) continue;
    visited.add(identity);
    const descriptor = sdk.engines[presentation.engine];
    if (!descriptor) {
      diagnostics.push(finding('MINIAPP_PRESENTATION_SDK_MISSING',
        'The installed author SDK lacks the native presentation engine: ' + presentation.engine, presentation.sourcePath,
        'Stage the original ' + presentation.engine + ' SDK from the same host build, then validate again.'));
      continue;
    }
    if (!await fs.stat(entryFile).then(info => info.isFile(), () => false)) {
      diagnostics.push(finding('MINIAPP_PRESENTATION_SOURCE_MISSING',
        'Native presentation source does not exist: ' + presentation.sourcePath, presentation.sourcePath));
      continue;
    }
    sourceFiles.push(entryFile);
    if (presentation.sourceFormat === 'expo-layout') {
      // The actual native compiler accepts a serialized layout expression, which
      // may be JSON or JavaScript (including a props => layout function).
      // Parse with the original Expo Babel parser; native layout decoding still
      // belongs to the native renderer, so no replacement schema is invented.
      const requireSDK = createRequire(path.join(child(sdk.sdkRoot, descriptor.toolingRoot), 'package.json'));
      const parser = requireSDK('@babel/parser');
      try { parser.parseExpression(await fs.readFile(entryFile, 'utf8'), {sourceType: 'script'}); }
      catch (error) {
        diagnostics.push({...finding('MINIAPP_PRESENTATION_LAYOUT_INVALID', error.message, presentation.sourcePath),
          ...(error.loc ? {line: error.loc.line, column: error.loc.column + 1} : {})});
      }
      continue;
    }
    let nativeRoot = path.dirname(entryFile);
    // Use a native subtree config when present, never inherit the outer Expo/React
    // JSX config into a different native renderer's TypeScript environment.
    let directory = nativeRoot;
    while (directory !== input.sourceRoot && inside(input.sourceRoot, directory)) {
      if (await fs.stat(path.join(directory, 'tsconfig.json')).then(info => info.isFile(), () => false)) {
        nativeRoot = directory;
        break;
      }
      directory = path.dirname(directory);
    }
    const nativeInput = {...input, sourceRoot: nativeRoot, entryFile, assistantTools: [],
      entry: slash(path.relative(nativeRoot, entryFile)),
      author: {engine: presentation.engine, tsconfig: 'tsconfig.json'}};
    const ts = compiler ?? (await import(pathToFileURL(child(sdk.sdkRoot, descriptor.typescriptPath)).href)).default;
    const parsed = await parseProject(ts, nativeInput, sdk.sdkRoot, descriptor,
      {files: [nativeInput.entry], compilerOptions: {strict: true, allowJs: true}},
      presentation.engine === input.engine || nativeRoot !== input.sourceRoot);
    programs.push(parsed.program);
    diagnostics.push(...parsed.diagnostics.map(diagnostic => ({...diagnostic,
      ...(diagnostic.file ? {file: slash(path.relative(input.sourceRoot,
        path.resolve(nativeRoot, diagnostic.file)))} : {})})));
  }
  return {programs, sourceFiles, diagnostics: deduplicate(diagnostics)};
}

async function copyNativePresentationSources(input, programs, stage, declaredSources = []) {
  const sources = new Set(declaredSources);
  for (const program of programs) for (const source of program.getSourceFiles()) {
    if (!source.isDeclarationFile && inside(input.sourceRoot, source.fileName) &&
        !source.fileName.includes(path.sep + 'node_modules' + path.sep)) sources.add(source.fileName);
  }
  for (const source of sources) {
    const target = child(stage, path.relative(input.sourceRoot, source));
    await fs.mkdir(path.dirname(target), {recursive: true});
    await fs.copyFile(source, target);
  }
  if (sources.size && input.engine === 'nativescript') await copyResources(input, stage);
}

async function retainSources(input, stage, parsed, nativePrograms = []) {
  const compilerFiles = [parsed.program, ...nativePrograms].flatMap(program => program.getSourceFiles()).map(file => path.resolve(file.fileName));
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
      // Root output folders are omitted only when no actual compiler input lives there.
      // A nested source folder such as src/build is ordinary authoring content.
      if (!relative && stat.isDirectory() && ['dist', 'build'].includes(entry.name) &&
          !compilerFiles.some(source => inside(file, source))) continue;
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
  await copyResources(input, destination, (name, bytes) => { hashes[name] = sha256(bytes); });
  return hashes;
}

async function copyResources(input, root, didCopy) {
  const copy = async (relative, ancestors = new Set()) => {
    const actual = await fs.realpath(child(input.sourceRoot, relative));
    if (!inside(input.sourceRoot, actual)) throw new Error('Resource leaves the project: ' + relative);
    // An explicitly selected containing directory must never recursively copy
    // this build's own output into itself.
    if (inside(root, actual)) return;
    const info = await fs.stat(actual);
    if (info.isDirectory()) {
      if (ancestors.has(actual)) throw new Error('Resource contains a circular directory link: ' + relative);
      const next = new Set([...ancestors, actual]);
      for (const name of (await fs.readdir(actual)).sort()) await copy(path.posix.join(relative, name), next);
      return;
    }
    if (!info.isFile()) throw new Error('Resource must be a regular file or directory: ' + relative);
    const bytes = await fs.readFile(actual);
    const target = child(root, relative);
    await fs.mkdir(path.dirname(target), {recursive: true});
    await fs.writeFile(target, bytes);
    didCopy?.(relative, bytes);
  };
  for (const resource of input.author.resources ?? []) await copy(resource);
}

function relativeImportTransformer(ts, parsed, input, sourceOutputs) {
  return context => {
    const rewrite = (specifier, sourceFile) => {
      if (!ts.isStringLiteral(specifier)) return specifier;
      const resolved = parsed.compilerHost.resolveModuleNames([specifier.text], sourceFile.fileName)[0];
      if (!resolved || !inside(input.sourceRoot, resolved.resolvedFileName) || resolved.resolvedFileName.endsWith('.d.ts')) return specifier;
      const importerOutput = sourceOutputs.get(path.resolve(sourceFile.fileName));
      const targetOutput = sourceOutputs.get(path.resolve(resolved.resolvedFileName));
      const relative = targetOutput && importerOutput
        ? slash(path.relative(path.dirname(importerOutput), targetOutput))
        : slash(path.relative(path.dirname(sourceFile.fileName), resolved.resolvedFileName));
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


function runtimePackageName(specifier) {
  if (specifier.startsWith('.') || path.isAbsolute(specifier) || specifier.includes(':') || specifier.startsWith('#')) return null;
  return specifier.startsWith('@') ? specifier.split('/').slice(0, 2).join('/') : specifier.split('/')[0];
}
function runtimeImports(ts, emittedSources) {
  const packages = new Set();
  for (const [file, source] of emittedSources) {
    const ast = ts.createSourceFile(file, source, ts.ScriptTarget.Latest, true, ts.ScriptKind.JS);
    const add = literal => {
      if (literal && ts.isStringLiteralLike(literal)) {
        const name = runtimePackageName(literal.text);
        if (name) packages.add(name);
      }
    };
    const visit = node => {
      if (ts.isImportDeclaration(node) || ts.isExportDeclaration(node)) add(node.moduleSpecifier);
      if (ts.isCallExpression(node) &&
          (node.expression.kind === ts.SyntaxKind.ImportKeyword || ts.isIdentifier(node.expression) && node.expression.text === 'require')) add(node.arguments[0]);
      ts.forEachChild(node, visit);
    };
    visit(ast);
  }
  return packages;
}
async function installedPackage(name, from, fallback, boundary) {
  // A supplied SDK fallback is a complete installed graph, not a starting point
  // for searching unrelated ancestor installations.
  for (const [start, limit] of [[from, boundary], [fallback, fallback]]) {
    if (!start) continue;
    let directory = start;
    while (!limit || inside(limit, directory)) {
      const candidate = path.join(directory, 'node_modules', name);
      if (await optionalJSON(path.join(candidate, 'package.json'))) return fs.realpath(candidate);
      const parent = path.dirname(directory);
      if (parent === directory) break;
      directory = parent;
    }
  }
  return null;
}
async function copyNativeScriptDependencies(ts, input, parsed, app, emittedSources) {
  // The exact shared Core and host-services modules are linked by the original host.
  const provided = new Set(['@nativescript/core', '@hanlin/host-services']);
  const names = new Set([...Object.keys(input.pkg.dependencies ?? {}),
    ...Object.keys(input.pkg.hanlinNativeScript?.plugins ?? {}), ...runtimeImports(ts, emittedSources)]);
  const locations = new Map();
  const copied = new Set();
  const directSources = new Map();
  const nativePlugins = {};
  const directVersions = {};
  const rootModules = path.join(app, 'node_modules');
  const copy = async (name, source, importer) => {
    if (provided.has(name)) return;
    let destination = path.join(rootModules, name);
    if (importer) {
      let directory = importer;
      while (inside(app, directory)) {
        const candidate = path.join(directory, 'node_modules', name);
        if (locations.has(candidate)) {
          if (locations.get(candidate) === source) return;
          destination = path.join(importer, 'node_modules', name);
          break;
        }
        const parent = path.dirname(directory);
        if (parent === directory) break;
        directory = parent;
      }
    }
    if (locations.get(destination) === source && copied.has(destination)) return;
    if (locations.has(destination) && locations.get(destination) !== source) throw new Error('Runtime dependency version collision at ' + destination);
    locations.set(destination, source);
    copied.add(destination);
    const pkg = await json(path.join(source, 'package.json'));
    if (!importer) directVersions[name] = pkg.version;
    if (pkg.nativescript?.platforms?.ios) nativePlugins[name] = pkg.version;
    await fs.cp(source, destination, {recursive: true, dereference: true, filter: file => {
      if (file === source) return true;
      const relative = path.relative(source, file);
      return !relative.split(path.sep).some(part => ['node_modules', '.git', '.bin'].includes(part)) &&
        !/\.(?:node|a|o|so|dylib|dll|exe|framework|xcframework)$/.test(file);
    }});
    const required = {...pkg.dependencies, ...pkg.peerDependencies};
    const optional = {...pkg.optionalDependencies};
    for (const [peer, info] of Object.entries(pkg.peerDependenciesMeta ?? {}))
      if (info.optional) { optional[peer] = required[peer]; delete required[peer]; }
    for (const dependency of new Set([...Object.keys(required), ...Object.keys(optional)])) {
      if (provided.has(dependency)) continue;
      const sdkSource = inside(parsed.toolingRoot, source) || parsed.originalPackages.has(name);
      const resolved = sdkSource
        ? await installedPackage(dependency, source, parsed.toolingRoot, inside(parsed.toolingRoot, source) ? parsed.toolingRoot : source)
        : parsed.originalPackages.has(dependency)
          ? await installedPackage(dependency, parsed.toolingRoot, undefined, parsed.toolingRoot)
          : await installedPackage(dependency, source, parsed.toolingRoot);
      if (!resolved) {
        if (dependency in optional) continue;
        throw new Error('Original runtime dependency is not installed: ' + dependency + ' (used by ' + name + ').');
      }
      await copy(dependency, resolved, destination);
    }
  };
  // Reserve/copy direct modules first, then each actual installed dependency graph.
  for (const name of names) {
    if (provided.has(name)) continue;
    const source = parsed.originalPackages.has(name)
      ? await installedPackage(name, parsed.toolingRoot, undefined, parsed.toolingRoot)
      : await installedPackage(name, input.sourceRoot, parsed.toolingRoot);
    if (!source) throw new Error('Original runtime package is not installed in the project or host SDK: ' + name);
    directSources.set(name, source);
    locations.set(path.join(rootModules, name), source);
  }
  for (const [name, source] of directSources) await copy(name, source);
  return {nativePlugins, directVersions};
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
  // Plan from actual compiler output: the original iOS loader recognizes .mjs
  // as ESM, while authored CommonJS .js must retain its original module mode.
  const moduleOutputs = new Map();
  const sourceOutputs = new Map();
  const planning = program.emit(undefined, (file, text, _bom, _error, sources) => {
    if (!/\.[cm]?js$/.test(file)) return;
    const isESM = ts.isExternalModule(ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true, ts.ScriptKind.JS));
    const output = isESM ? file.replace(/\.js$/, '.mjs') : file;
    moduleOutputs.set(file, output);
    for (const source of sources ?? []) sourceOutputs.set(path.resolve(source.fileName), output);
  });
  if (planning.diagnostics.some(item => item.category === ts.DiagnosticCategory.Error))
    return planning.diagnostics.map(item => normalizedDiagnostic(ts, item, input.sourceRoot));

  const pending = [];
  const emittedSources = [];
  const emitted = program.emit(undefined, (file, text) => {
    if (!inside(modules, path.resolve(file))) throw new Error('Compiler output leaves the prepared app.');
    const output = file.endsWith('.map')
      ? (moduleOutputs.get(file.slice(0, -4)) ?? file.slice(0, -4)) + '.map'
      : moduleOutputs.get(file) ?? file;
    if (output !== file && file.endsWith('.map')) {
      const map = JSON.parse(text);
      map.file = path.basename(output.slice(0, -4));
      text = JSON.stringify(map);
    } else if (output !== file) {
      text = text.replace(/(\/\/# sourceMappingURL=[^\r\n]+)\.js\.map(\r?\n)?$/, '$1.mjs.map$2');
    }
    if (/\.[cm]?js$/.test(output)) emittedSources.push([output, text]);
    pending.push(fs.mkdir(path.dirname(output), {recursive: true}).then(() => fs.writeFile(output, text)));
  }, undefined, undefined, {before: [relativeImportTransformer(ts, parsed, input, sourceOutputs)]});
  await Promise.all(pending);
  const entryOutput = sourceOutputs.get(path.resolve(input.sourceRoot, input.entry));
  if (!entryOutput) throw new Error('The compiler did not emit the NativeScript entry module.');
  const entry = slash(path.relative(modules, entryOutput));
  await fs.mkdir(app, {recursive: true});
  await fs.writeFile(path.join(app, 'bundle.mjs'), 'import ' + JSON.stringify('./modules/' + entry) + ';\n');
  const dependencies = await copyNativeScriptDependencies(ts, input, parsed, app, emittedSources);
  await writeJSON(path.join(app, 'package.json'), {
    ...input.pkg, dependencies: {...input.pkg.dependencies, ...dependencies.directVersions,
      ...(sdkEngine.packageVersions?.['@nativescript/core'] ? {'@nativescript/core': sdkEngine.packageVersions['@nativescript/core']} : {})}, main: 'bundle.mjs', type: 'module', hanlinRuntime: 'hanlin-nativescript',
    hanlinNativeScript: {...input.pkg.hanlinNativeScript,
      runtimeVersion: sdkEngine.packageVersions?.['@nativescript/ios'] ?? sdkEngine.packageVersions?.['@nativescript/core'],
      plugins: {...input.pkg.hanlinNativeScript?.plugins, ...dependencies.nativePlugins}},
  });
  await copyResources(input, modules);
  for (const tool of input.assistantTools) {
    const toolRoot = path.dirname(child(stage, tool.sourcePath));
    if (inside(app, toolRoot) || inside(toolRoot, app)) throw new Error('Assistant program must have a separate prepared folder.');
    await fs.cp(app, toolRoot, {recursive: true});
    const toolOutput = sourceOutputs.get(path.resolve(tool.sourceFile));
    if (!toolOutput) throw new Error('The compiler did not emit the dedicated NativeScript assistant module: ' + tool.id);
    const toolEntry = slash(path.relative(modules, toolOutput));
    await fs.writeFile(path.join(toolRoot, 'bundle.mjs'), assistantToolWrapper(tool, './modules/' + toolEntry, 'nativescript'));
  }
  await writeJSON(path.join(stage, 'script.json'), {...input.script,
    entry: 'nativescript/app/bundle.mjs', runInApp: true, hanlinRuntime: 'hanlin-nativescript'});
  return emitted.diagnostics.map(item => normalizedDiagnostic(ts, item, input.sourceRoot));
}

async function buildExpo(input, parsed, stage, sdkEngine) {
  if (sdkEngine.hostContract) {
    for (const name of Object.keys(input.pkg.hanlinExpo?.plugins ?? {})) {
      if (!(name in sdkEngine.hostContract.plugins)) throw Object.assign(new Error(
        'The installed native host does not embed the declared plugin: ' + name), {
        miniAppCode: 'MINIAPP_NATIVE_PLUGIN_NOT_EMBEDDED', filename: path.join(input.sourceRoot, 'package.json'),
        remediation: 'Build the host with the original native dependency, then rebuild this project against that host SDK.'
      });
    }
  }
  const requireSDK = createRequire(path.join(parsed.toolingRoot, 'package.json'));
  const metro = requireSDK('metro');
  const {mergeConfig} = requireSDK('metro-config');
  // Preserve the complete original Expo configuration, including its matching
  // transformer and Babel preset. Missing dependencies inside that config are
  // real errors; they must not silently select another renderer's transformer.
  const configPath = path.join(parsed.toolingRoot, 'metro.config.cjs');
  const hasOriginalConfig = await fs.stat(configPath).then(info => info.isFile(), error => {
    if (error.code === 'ENOENT') return false;
    throw error;
  });
  const original = hasOriginalConfig ? requireSDK(configPath)
    : requireSDK('expo/metro-config').getDefaultConfig(parsed.toolingRoot);
  const originalPackages = new Set(Object.keys(sdkEngine.packageVersions ?? {}));
  const originalResolveRequest = original.resolver?.resolveRequest;
  const config = mergeConfig(original, {
    projectRoot: parsed.toolingRoot,
    watchFolders: [input.sourceRoot, parsed.toolingRoot, stage],
    maxWorkers: 1,
    resolver: {useWatchman: false,
      nodeModulesPaths: [path.join(input.sourceRoot, 'node_modules'), path.join(parsed.toolingRoot, 'node_modules')],
      resolveRequest(context, name, platform) {
        const fromSDK = inside(parsed.toolingRoot, context.originModulePath);
        if (fromSDK || originalPackages.has(packageName(name))) {
          const originModulePath = fromSDK ? context.originModulePath : path.join(parsed.toolingRoot, '__hanlin_authoring__.js');
          const nodeModulesPaths = [];
          for (let directory = path.dirname(originModulePath); inside(parsed.toolingRoot, directory); directory = path.dirname(directory)) {
            nodeModulesPaths.push(path.join(directory, 'node_modules'));
            if (directory === parsed.toolingRoot) break;
          }
          context = {...context, originModulePath, disableHierarchicalLookup: true, nodeModulesPaths};
        }
        return (originalResolveRequest ?? context.resolveRequest)(context, name, platform);
      }},
    watcher: {healthCheck: {enabled: false}},
    fileMapCacheDirectory: path.join(stage, '.metro-cache'),
    cacheStores: [],
    transformer: {unstable_allowRequireContext: true}
  });
  // This original Metro version uses its Node filesystem crawler with useWatchman=false.
  // maxWorkers=1 also keeps both compiler worker pools inside the existing Node process.
  config.resolver.unstable_enablePackageExports = true;
  await fs.mkdir(config.fileMapCacheDirectory, {recursive: true});
  const bundle = async (entryFile, output) => {
    await fs.mkdir(output, {recursive: true});
    const result = await metro.runBuild(config, {
      entry: entryFile, platform: 'ios', dev: false, minify: false,
      sourceMap: true, sourceMapUrl: 'bundle.js.map', assets: true
    });
    if (typeof result?.code !== 'string' || !result.map) throw new Error('Original Metro produced no complete bundle and source map.');
    await fs.writeFile(path.join(output, 'bundle.js'), result.code);
    await fs.writeFile(path.join(output, 'bundle.js.map'), typeof result.map === 'string' ? result.map : JSON.stringify(result.map));
    if (result.assets?.length) {
      const pluginRoot = path.dirname(requireSDK.resolve('@react-native/community-cli-plugin/package.json'));
      const saveAssets = requireSDK(path.join(pluginRoot, 'dist/commands/bundle/saveAssets.js')).default;
      await saveAssets(result.assets, 'ios', output);
    }
  };
  await bundle(input.entryFile, stage);
  const wrappers = path.join(stage, '.assistant-tool-sources');
  for (const [index, tool] of input.assistantTools.entries()) {
    await fs.mkdir(wrappers, {recursive: true});
    const wrapper = path.join(wrappers, index + '.js');
    await fs.writeFile(wrapper, assistantToolWrapper(tool, slash(tool.sourceFile), 'expo'));
    await bundle(wrapper, path.dirname(child(stage, tool.sourcePath)));
  }
  await fs.rm(path.join(stage, '.metro-cache'), {recursive: true, force: true});
  await fs.rm(wrappers, {recursive: true, force: true});
  await copyResources(input, stage);
  await writeJSON(path.join(stage, 'script.json'), {...input.script, entry: 'bundle.js', runInApp: true, hanlinRuntime: 'hanlin-expo'});
  const contract = sdkEngine.hostContract;
  const dependencies = Object.fromEntries(Object.entries(input.pkg.dependencies ?? {}).map(([name, version]) =>
    [name, sdkEngine.packageVersions?.[name] ?? version]));
  const preparedContract = contract ? {...input.pkg.hanlinExpo,
    runtimeVersion: contract.runtimeVersion, bridgeVersion: contract.bridgeVersion,
    plugins: {...input.pkg.hanlinExpo?.plugins, ...contract.plugins},
    nativeApi: {...input.pkg.hanlinExpo?.nativeApi,
      contractVersion: contract.nativeApiContractVersion, abiIdentity: contract.nativeApiAbiIdentity}
  } : input.pkg.hanlinExpo;
  await writeJSON(path.join(stage, 'package.json'), {...input.pkg, dependencies,
    main: 'bundle.js', hanlinRuntime: 'hanlin-expo', ...(preparedContract ? {hanlinExpo: preparedContract} : {})});
  const preparedPackage = await json(path.join(stage, 'package.json'));
  for (const tool of input.assistantTools)
    await writeJSON(path.join(path.dirname(child(stage, tool.sourcePath)), 'package.json'), preparedPackage);
}

async function validateOriginalScriptWidgetManifest(input, sdk, ts) {
  if (input.engine !== 'scriptwidget') return {diagnostics: []};
  const names = await fs.readdir(input.sourceRoot);
  const ambiguous = names.find(name => name.toLowerCase() === 'widget.json' && name !== 'widget.json');
  if (ambiguous) return {diagnostics: [finding('SCRIPTWIDGET_INVALID_MANIFEST_NAME',
    'The original ScriptWidget manifest must be named exactly widget.json.', ambiguous)]};
  if (!names.includes('widget.json')) return {diagnostics: []};
  input.originalWidgetManifestText = await fs.readFile(path.join(input.sourceRoot, 'widget.json'), 'utf8');
  const descriptor = sdk.engines.scriptwidget;
  if (!descriptor.packageManifestSchemaPath || !descriptor.packageManifestValidatorPath)
    return {diagnostics: [finding('SCRIPTWIDGET_MANIFEST_SDK_MISSING',
      'This SDK does not contain the original ScriptWidget manifest authoring contract.', 'widget.json',
      'Stage the SDK from the current host build and validate again.')]};
  const schema = await json(child(sdk.sdkRoot, descriptor.packageManifestSchemaPath));
  const {validateScriptWidgetManifest} = await import(pathToFileURL(child(sdk.sdkRoot, descriptor.packageManifestValidatorPath)).href);
  const result = await validateScriptWidgetManifest({text: input.originalWidgetManifestText,
    entry: input.entry, compiler: ts, schema,
    exists: relative => fs.stat(child(input.sourceRoot, relative)).then(info => info.isFile(), () => false)});
  input.originalWidgetManifest = result.manifest;
  return {...result, schemaPath: descriptor.packageManifestSchemaPath, sources: schema['x-original-contract'].sources};
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
  if (input.originalWidgetManifestText !== undefined) {
    // The installed original control runtime reads this exact root-level file.
    await fs.writeFile(path.join(stage, 'widget.json'), input.originalWidgetManifestText);
    const preview = input.originalWidgetManifest?.preview;
    if (preview && await fs.stat(child(input.sourceRoot, preview)).then(info => info.isFile(), () => false)) {
      const target = child(stage, preview);
      await fs.mkdir(path.dirname(target), {recursive: true});
      await fs.copyFile(child(input.sourceRoot, preview), target);
    }
  }
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
    report.diagnostics = input.assistantDiagnostics;
    if (report.diagnostics.some(item => item.category === 'error')) return report;
    const sdk = await readMiniAppSDK(sdkRoot, {engine: input.engine});
    const descriptor = sdk.selectedEngine;
    const ts = compiler ?? (descriptor.typescriptPath
      ? (await import(pathToFileURL(child(sdk.sdkRoot, descriptor.typescriptPath)).href)).default
      : (await import('typescript')).default);
    if (!ts?.createProgram) throw new Error('The original TypeScript compiler is unavailable in this SDK.');
    report.sdk = {packageVersions: descriptor.packageVersions ?? {},
      manifestSHA256: sdk.manifestSHA256, compilerVersion: ts.version};
    const originalManifest = await validateOriginalScriptWidgetManifest(input, sdk, ts);
    if (originalManifest.schemaPath) report.manifestValidation = {schemaPath: originalManifest.schemaPath, sources: originalManifest.sources};
    const parsed = await parseProject(ts, input, sdk.sdkRoot, descriptor);
    report.typecheck = {strict: parsed.options.strict === true, checkJs: parsed.options.checkJs === true, skipLibCheck: parsed.options.skipLibCheck === true,
      dependencyDeclarationsChecked: parsed.options.skipLibCheck !== true};
    const native = await validateNativePresentations(input, sdk, compiler);
    const assistantDiagnostics = [];
    const checker = parsed.program.getTypeChecker();
    for (const tool of input.assistantTools) {
      const source = parsed.program.getSourceFile(tool.sourceFile);
      const symbol = source && checker.getSymbolAtLocation(source);
      const exported = symbol ? checker.getExportsOfModule(symbol) : [];
      for (const action of tool.assistantTool.actions) {
        const name = action.exportedSymbol ?? action.id;
        const value = exported.find(item => item.name === name);
        if (!value || !checker.getTypeOfSymbolAtLocation(value, source).getCallSignatures().length)
          assistantDiagnostics.push(finding('MINIAPP_ASSISTANT_EXPORT_MISSING',
            'The dedicated assistant module must export a callable ' + name + '.', tool.source));
      }
    }
    report.diagnostics = [...originalManifest.diagnostics, ...parsed.diagnostics, ...native.diagnostics,
      ...assistantDiagnostics, ...await packageConsistency(input)];
    if (report.diagnostics.some(item => item.category === 'error')) return report;
    if (request.operation === 'validate') { report.succeeded = true; return report; }
    stage = request.outputDirectory ? path.resolve(request.outputDirectory)
      : path.join(input.project, '.hanlin-build', randomUUID(), 'package');
    if (inside(stage, input.sourceRoot) || stage === input.sourceRoot) throw new Error('Build output must not contain the source project.');
    // Never reuse stale output or overwrite another build.
    await fs.mkdir(path.dirname(stage), {recursive: true});
    await fs.mkdir(stage, {recursive: false});
    ownsStage = true;
    const sourceHashes = await retainSources(input, stage, parsed, native.programs);
    if (input.engine === 'nativescript')
      report.diagnostics.push(...await buildNativeScript(ts, input, parsed, stage, descriptor));
    else if (input.engine === 'expo') await buildExpo(input, parsed, stage, descriptor);
    else await buildScriptWidget(input, parsed, stage);
    await copyNativePresentationSources(input, native.programs, stage, native.sourceFiles);
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
    const diagnostic = finding(error.miniAppCode ?? 'MINIAPP_AUTHORING_FAILED', error.message,
      file && input ? slash(path.relative(input.sourceRoot, file)) : file,
      error.remediation ?? 'Read get_miniapp_sdk for this installed host, repair the source/configuration, then validate again.');
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
