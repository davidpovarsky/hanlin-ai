import { parentPort, workerData } from 'node:worker_threads';
import * as nodeModule from 'node:module';
import { readFileSync, promises as fs } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
import ts from 'typescript';

const blockedBuiltins = new Set(['cluster']);
const entryPoint = path.resolve(workerData.entryPoint);
const packageRoot = path.resolve(workerData.packageRoot);
const relative = path.relative(packageRoot, entryPoint);
if (relative === '..' || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) {
  throw policyError('entry_point_escape', 'Entry point escapes package root.', { resolvedPath: relative });
}
if (typeof nodeModule.registerHooks !== 'function') {
  throw policyError(
    'module_policy_unavailable',
    `Node ${process.versions.node} does not provide module.registerHooks; package code was not loaded.`,
  );
}

// Worker threads expose the wrapper as argv[1]. MCP packages are executable
// entry points, so present the selected package file exactly as a direct Node
// launch would; argv[2...] remains the validated server arguments.
process.argv[1] = entryPoint;

const inspectedSources = new Set();
globalThis[Symbol.for('hanlin.mcp.blockChildProcess')] = operation => {
  deny(
    'reachable_external_executable',
    'child_process',
    callerURL(),
    null,
    operation,
  );
};
installChildProcessPolicy();

nodeModule.registerHooks({
  resolve(specifier, context, nextResolve) {
    const normalized = normalizeBuiltin(specifier);
    if (normalized === 'child_process') {
      parentPort?.postMessage({
        type: 'module-edge',
        parentPath: reportLocation(context.parentURL),
        specifier: reportSpecifier(specifier),
        resolvedPath: 'node:child_process',
        moduleType: 'builtin-policy',
      });
      return nextResolve(specifier, context);
    }
    if (blockedBuiltins.has(normalized)) {
      deny('reachable_blocked_builtin', specifier, context.parentURL);
    }
    const resolved = nextResolve(specifier, context);
    const edge = {
      type: 'module-edge',
      parentPath: reportLocation(context.parentURL),
      specifier: reportSpecifier(specifier),
      resolvedPath: reportLocation(resolved.url),
      moduleType: moduleType(resolved),
    };
    parentPort?.postMessage(edge);
    if (isNativeAddon(resolved.url)) {
      deny('reachable_native_addon', specifier, context.parentURL, resolved.url);
    }
    inspectLoadedSource(resolved.url);
    return resolved;
  },
  load(url, context, nextLoad) {
    if (typeof url === 'string' && url.startsWith('file:') && /\.(?:ts|cts|mts)$/i.test(url)) {
      const file = fileURLToPath(url);
      if (!insidePackage(file)) return nextLoad(url, context);
      const isCommonJS = /\.cts$/i.test(file);
      const result = ts.transpileModule(readFileSync(file, 'utf8'), {
        fileName: file,
        compilerOptions: {
          target: ts.ScriptTarget.ES2022,
          module: isCommonJS ? ts.ModuleKind.CommonJS : ts.ModuleKind.ESNext,
          sourceMap: false,
          inlineSourceMap: false,
        },
        reportDiagnostics: true,
      });
      const errors = (result.diagnostics ?? []).filter(item => item.category === ts.DiagnosticCategory.Error);
      if (errors.length) {
        throw policyError(
          'typescript_compilation_failed',
          `Reachable TypeScript compilation failed for ${reportLocation(url)}: ${errors.map(item => ts.flattenDiagnosticMessageText(item.messageText, ' ')).join('; ')}`,
        );
      }
      parentPort?.postMessage({ type: 'typescript-compiled', path: reportLocation(url) });
      return { format: isCommonJS ? 'commonjs' : 'module', source: result.outputText, shortCircuit: true };
    }
    return nextLoad(url, context);
  },
});

const originalGetBuiltinModule = process.getBuiltinModule?.bind(process);
if (originalGetBuiltinModule) {
  process.getBuiltinModule = specifier => {
    if (normalizeBuiltin(specifier) === 'child_process') {
      parentPort?.postMessage({
        type: 'module-edge',
        parentPath: reportLocation(callerURL()),
        specifier: reportSpecifier(specifier),
        resolvedPath: 'node:child_process',
        moduleType: 'builtin-policy',
      });
      return originalGetBuiltinModule(specifier);
    }
    if (blockedBuiltins.has(normalizeBuiltin(specifier))) {
      deny('reachable_blocked_builtin', String(specifier), callerURL());
    }
    return originalGetBuiltinModule(specifier);
  };
}

const originalBinding = process.binding.bind(process);
process.binding = name => {
  if (name === 'spawn_sync' || name === 'process_wrap') {
    deny(
      'reachable_external_executable',
      name,
      callerURL(),
      null,
      `process.binding(${name})`,
    );
  }
  return originalBinding(name);
};

const manifest = JSON.parse(await fs.readFile(path.join(packageRoot, 'package.json'), 'utf8'));
const extension = path.extname(entryPoint).toLowerCase();
const useESM = workerData.moduleKind
  ? workerData.moduleKind === 'esm'
  : extension === '.mjs' || (extension !== '.cjs' && manifest.type === 'module');

if (useESM) {
  await import(pathToFileURL(entryPoint).href);
} else {
  const require = nodeModule.createRequire(path.join(packageRoot, 'package.json'));
  require(entryPoint);
}

parentPort?.postMessage({ type: 'loaded', modulePolicyHooksAvailable: true });
// stdin is the lifetime of an MCP stdio server. The diagnostics port must not
// keep the Worker alive after the host closes stdin during Stop.
parentPort?.unref();

function deny(code, specifier, parentURL, resolvedURL = null, operation = null) {
  const access = {
    type: 'policy-blocked',
    code,
    specifier,
    parentPath: reportLocation(parentURL),
    resolvedPath: reportLocation(resolvedURL),
    operation,
  };
  parentPort?.postMessage(access);
  const location = access.parentPath ?? '<selected entry point>';
  const message = code === 'reachable_native_addon'
    ? `The selected server entry point attempted to load native addon ${access.resolvedPath ?? specifier} from ${location}.`
    : code === 'reachable_external_executable'
      ? `The selected server entry point attempted to access external process capability ${operation ?? specifier} from ${location}.`
      : `The selected server entry point attempted to load ${specifier} from ${location}.`;
  throw policyError(code, message, access);
}

function inspectLoadedSource(url) {
  if (typeof url !== 'string' || !url.startsWith('file:') || inspectedSources.has(url)) return;
  inspectedSources.add(url);
  let file;
  try { file = fileURLToPath(url); } catch { return; }
  if (!insidePackage(file) || !/\.(?:js|cjs|mjs)$/i.test(file)) return;
  try {
    const source = readFileSync(file, 'utf8');
    if (/\b(?:import|require)\s*\(\s*(?!['"`])/.test(source)) {
      parentPort?.postMessage({ type: 'dynamic-unresolved', path: reportLocation(url) });
    }
  } catch {
    // Node's loader remains authoritative; source inventory is warning-only.
  }
}

function normalizeBuiltin(specifier) {
  return String(specifier).replace(/^node:/, '');
}

function installChildProcessPolicy() {
  const childProcess = nodeModule.createRequire(import.meta.url)('node:child_process');
  for (const name of [
    'spawn',
    'exec',
    'execFile',
    'fork',
    'spawnSync',
    'execSync',
    'execFileSync',
    '_forkChild',
  ]) {
    const operation = `child_process.${name}`;
    Object.defineProperty(childProcess, name, {
      configurable: false,
      enumerable: true,
      value: (..._arguments) => globalThis[
        Symbol.for('hanlin.mcp.blockChildProcess')
      ](operation),
      writable: false,
    });
  }
  Object.defineProperty(childProcess.ChildProcess.prototype, 'spawn', {
    configurable: false,
    value: (..._arguments) => globalThis[
      Symbol.for('hanlin.mcp.blockChildProcess')
    ]('ChildProcess.prototype.spawn'),
    writable: false,
  });
}

function reportSpecifier(specifier) {
  const value = String(specifier);
  if (value.startsWith('file:')) return reportLocation(value) ?? '<runtime>';
  if (path.isAbsolute(value)) return insidePackage(value) ? reportLocation(value) : '<runtime>';
  return value;
}

function isNativeAddon(url) {
  if (typeof url !== 'string') return false;
  try { return path.extname(fileURLToPath(url)).toLowerCase() === '.node'; } catch { return false; }
}

function moduleType(resolved) {
  if (resolved?.format) return resolved.format;
  const location = reportLocation(resolved?.url);
  if (!location) return 'unknown';
  if (location.startsWith('node:')) return 'builtin';
  return path.extname(location).slice(1).toLowerCase() || 'unknown';
}

function reportLocation(url) {
  if (!url) return null;
  if (typeof url === 'string' && url.startsWith('node:')) return url;
  let candidate;
  try { candidate = typeof url === 'string' && url.startsWith('file:') ? fileURLToPath(url) : path.resolve(String(url)); }
  catch { return null; }
  if (!insidePackage(candidate)) return null;
  return path.relative(packageRoot, candidate).replaceAll(path.sep, '/') || '.';
}

function insidePackage(candidate) {
  const candidateRelative = path.relative(packageRoot, path.resolve(candidate));
  return candidateRelative !== '..'
    && !candidateRelative.startsWith(`..${path.sep}`)
    && !path.isAbsolute(candidateRelative);
}

function callerURL() {
  const normalizedRoot = packageRoot.replaceAll('\\', '/');
  for (const line of String(new Error().stack ?? '').split('\n')) {
    const normalized = line.replaceAll('\\', '/');
    const start = normalized.indexOf(normalizedRoot);
    if (start < 0) continue;
    const pathWithPosition = normalized.slice(start).replace(/\)?$/, '');
    const file = pathWithPosition.replace(/:\d+:\d+$/, '');
    return pathToFileURL(file).href;
  }
  return null;
}

function policyError(code, message, fields = {}) {
  const error = new Error(message);
  error.name = 'MCPRuntimePolicyError';
  error.code = code;
  Object.assign(error, fields);
  return error;
}
