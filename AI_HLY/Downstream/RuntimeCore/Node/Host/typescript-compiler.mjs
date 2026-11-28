// Shared compiler implementation for original HTTP compatibility and durable Node jobs.
// Importing this module does not eagerly load the TypeScript compiler.
import {promises as fs, mkdirSync} from 'node:fs';
import path from 'node:path';
import * as nodeModule from 'node:module';
import hostLock from './package-lock.json' with {type: 'json'};
import {globalNodeModules} from './global-package-state.mjs';

export async function compileTypeScript(body, {root}) {
  const clientsRoot = path.join(root, 'clients');
  if (typeof body.source !== 'string') throw new Error('TypeScript source is missing.');
  const ts = await import('typescript');
  const requestedFileName = typeof body.fileName === 'string' ? body.fileName : 'main.ts';
  if (!/\.tsx?$/.test(requestedFileName) || /[\0/\\]/.test(requestedFileName) || path.basename(requestedFileName) !== requestedFileName) throw new Error('TypeScript fileName must be a safe .ts or .tsx basename.');
  const virtualRoot = path.join(clientsRoot, 'typescript-compile');
  const virtualFileName = path.join(virtualRoot, requestedFileName);
  const baseOptions = {
    target: ts.ScriptTarget.ES2022,
    module: ts.ModuleKind.ESNext,
    moduleResolution: ts.ModuleResolutionKind.Bundler,
    strict: true,
    types: ['node'],
    typeRoots: [path.dirname(path.dirname(nodeModule.createRequire(import.meta.url).resolve('@types/node/package.json')))],
    // Installed pure-JavaScript packages are valid runtime dependencies even
    // when they do not publish a declaration package. Explicit TypeScript type
    // errors remain enabled through the rest of strict mode.
    noImplicitAny: false,
    allowJs: true,
    checkJs: false,
    paths: { '*': [path.join(await globalNodeModules(root), '*')] },
    sourceMap: true,
    inlineSources: true,
  };
  const converted = ts.convertCompilerOptionsFromJson(body.tsconfig?.compilerOptions ?? {}, '.');
  const compilerOptions = { ...baseOptions, ...converted.options };
  const sourceFile = ts.createSourceFile(
    virtualFileName,
    body.source,
    compilerOptions.target ?? ts.ScriptTarget.ES2022,
    true,
    requestedFileName.endsWith('.tsx') ? ts.ScriptKind.TSX : ts.ScriptKind.TS,
  );
  const compilerHost = ts.createCompilerHost(compilerOptions);
  const originalGetSourceFile = compilerHost.getSourceFile.bind(compilerHost);
  const originalFileExists = compilerHost.fileExists.bind(compilerHost);
  const originalReadFile = compilerHost.readFile.bind(compilerHost);
  let javaScript = null;
  let sourceMap = null;
  const isVirtual = fileName => path.resolve(fileName) === virtualFileName;
  compilerHost.getSourceFile = (fileName, languageVersion, onError, shouldCreateNewSourceFile) =>
    isVirtual(fileName)
      ? sourceFile
      : originalGetSourceFile(fileName, languageVersion, onError, shouldCreateNewSourceFile);
  compilerHost.fileExists = fileName => isVirtual(fileName) || originalFileExists(fileName);
  compilerHost.readFile = fileName => isVirtual(fileName) ? body.source : originalReadFile(fileName);
  compilerHost.writeFile = (fileName, data) => {
    if (fileName.endsWith('.js')) javaScript = data;
    else if (fileName.endsWith('.js.map')) sourceMap = data;
  };
  const program = ts.createProgram([virtualFileName], compilerOptions, compilerHost);
  const rawDiagnostics = [
    ...(converted.errors ?? []),
    ...ts.getPreEmitDiagnostics(program, sourceFile),
    ...program.getSemanticDiagnostics(sourceFile),
    ...program.getSyntacticDiagnostics(sourceFile),
  ];
  if (!rawDiagnostics.some(item => item.category === ts.DiagnosticCategory.Error)) {
    rawDiagnostics.push(...program.emit().diagnostics);
  }
  const seen = new Set();
  const diagnostics = [];
  for (const diagnostic of rawDiagnostics) {
    const position = diagnostic.file && typeof diagnostic.start === 'number' ? diagnostic.file.getLineAndCharacterOfPosition(diagnostic.start) : null;
    const key = `${diagnostic.code}:${position?.line}:${position?.character}:${diagnostic.messageText}`;
    if (!seen.has(key)) {
      seen.add(key);
      diagnostics.push({
        code: diagnostic.code,
        category: diagnostic.category,
        message: ts.flattenDiagnosticMessageText(diagnostic.messageText, '\n'),
        file: diagnostic.file?.fileName ? path.basename(diagnostic.file.fileName) : null,
        line: position ? position.line + 1 : null,
        column: position ? position.character + 1 : null,
      });
    }
  }
  const failed = diagnostics.some(item => item.category === ts.DiagnosticCategory.Error);
  return { compilerVersion: ts.version, javaScript: failed ? null : javaScript, sourceMap: failed ? null : sourceMap, diagnostics: diagnostics.map(({ category, ...item }) => item), succeeded: !failed };
}

export async function compileTypeScriptProject(body) {
  const workspace = path.resolve(String(body.workspace ?? ''));
  if (!workspace) throw new Error('TypeScript lifecycle workspace must be specified.');
  let stat;
  try {
    stat = await fs.stat(workspace);
  } catch (err) {
    const error = new Error(`TypeScript lifecycle workspace does not exist: ${err.message}`);
    error.status = 404;
    throw error;
  }
  if (!stat.isDirectory()) {
    const error = new Error('TypeScript lifecycle workspace must be a directory.');
    error.status = 400;
    throw error;
  }
  const args = Array.isArray(body.arguments) ? body.arguments.map(String) : [];
  if (args.some(argument => /\0/.test(argument))) throw new Error('Invalid TypeScript lifecycle arguments.');
  const ts = await import('typescript');
  const commandLine = ts.parseCommandLine(args);
  const diagnostics = [...commandLine.errors];
  const requestedProject = commandLine.options.project;
  const configPath = requestedProject
    ? path.resolve(workspace, requestedProject)
    : ts.findConfigFile(workspace, ts.sys.fileExists, 'tsconfig.json');
  if (!configPath || !isInside(workspace, configPath)) throw new Error('A tsconfig.json inside the package workspace is required.');
  const config = ts.readConfigFile(configPath, ts.sys.readFile);
  if (config.error) diagnostics.push(config.error);
  const parsed = ts.parseJsonConfigFileContent(config.config ?? {}, ts.sys, path.dirname(configPath), commandLine.options, configPath);
  diagnostics.push(...parsed.errors);
  const emittedFiles = [];
  if (!diagnostics.some(item => item.category === ts.DiagnosticCategory.Error)) {
    const program = ts.createProgram({ rootNames: parsed.fileNames, options: parsed.options, projectReferences: parsed.projectReferences });
    diagnostics.push(...ts.getPreEmitDiagnostics(program));
    if (!diagnostics.some(item => item.category === ts.DiagnosticCategory.Error)) {
      const emit = program.emit(undefined, (fileName, data, writeByteOrderMark) => {
        const destination = path.resolve(fileName);
        if (!isInside(workspace, destination)) throw new Error(`TypeScript output escapes the package workspace: ${fileName}`);
        mkdirSync(path.dirname(destination), { recursive: true });
        ts.sys.writeFile(destination, data, writeByteOrderMark);
        emittedFiles.push(path.relative(workspace, destination));
      });
      diagnostics.push(...emit.diagnostics);
    }
  }
  const normalized = diagnostics.map(diagnostic => {
    const position = diagnostic.file && typeof diagnostic.start === 'number' ? diagnostic.file.getLineAndCharacterOfPosition(diagnostic.start) : null;
    return {
      code: diagnostic.code,
      category: ts.DiagnosticCategory[diagnostic.category]?.toLowerCase() ?? 'error',
      message: ts.flattenDiagnosticMessageText(diagnostic.messageText, '\n'),
      file: diagnostic.file?.fileName ? path.relative(workspace, diagnostic.file.fileName) : null,
      line: position ? position.line + 1 : null,
      column: position ? position.character + 1 : null,
    };
  });
  return {
    compilerVersion: ts.version,
    compilerIntegrity: hostLock.packages['node_modules/typescript'].integrity,
    diagnostics: normalized,
    emittedFiles: emittedFiles.sort(),
    succeeded: !diagnostics.some(item => item.category === ts.DiagnosticCategory.Error),
  };
}

function isInside(parent, child) { const relative = path.relative(path.resolve(parent), path.resolve(child)); return relative !== '..' && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative); }
