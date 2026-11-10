import fs from 'node:fs';
import path from 'node:path';
import { registerHooks, isBuiltin, createRequire } from 'node:module';
import { pathToFileURL, fileURLToPath } from 'node:url';

/** Public synchronous Node hooks apply equally to import and createRequire.
 * Source stays in its durable journal; resolution uses its actual workspace.
 * A local package's exports/errors must never fall back to an older global copy.
 */
export function configureExecutionModules({entryPoint, workspace, moduleKind, executionMode, globalNodeModules}) {
  const physical = pathToFileURL(entryPoint).href;
  const virtualPath = executionMode === 'cli' || !workspace || path.dirname(entryPoint) === workspace ? entryPoint
    : path.join(workspace, `.hanlin-execution-${path.basename(path.dirname(entryPoint))}.${moduleKind === 'commonjs' ? 'cjs' : 'mjs'}`);
  const virtual = pathToFileURL(virtualPath).href;
  const format = moduleKind === 'commonjs' ? 'commonjs' : 'module';
  const globalEntry = globalNodeModules ? pathToFileURL(path.join(path.dirname(globalNodeModules), '.hanlin-global-entry.mjs')).href : null;
  let resolvingGlobal = false;
  registerHooks({
    resolve(specifier, context, nextResolve) {
      if(specifier==='hanlin:runtime')return {url:new URL('./native-commands.mjs',import.meta.url).href,format:'module',shortCircuit:true};
      const url = specifier.startsWith('file:') ? new URL(specifier) : null;
      if (url) { url.search = ''; url.hash = ''; }
      if (virtual !== physical && (specifier === entryPoint || url?.href === physical)) {
        return {url: virtual, format, shortCircuit: true};
      }
      try { return nextResolve(specifier, context); }
      catch (error) {
        if (resolvingGlobal || !globalEntry || !['ERR_MODULE_NOT_FOUND','MODULE_NOT_FOUND'].includes(error.code)
            || !barePackage(specifier) || isBuiltin(specifier) || localPackageExists(specifier, context.parentURL)) throw error;
        if (Array.from(context.conditions).includes('require')) {
          // v24.5's CJS nextResolve retains its original parent internally.
          // A public require anchored to the generation preserves require exports.
          resolvingGlobal = true;
          try { return {url:pathToFileURL(createRequire(globalEntry).resolve(specifier)).href,shortCircuit:true}; }
          finally { resolvingGlobal = false; }
        }
        return nextResolve(specifier, {...context, parentURL:globalEntry});
      }
    },
    load(url, context, nextLoad) {
      if (virtual !== physical && url === virtual) return {source: fs.readFileSync(entryPoint), format, shortCircuit: true};
      return nextLoad(url, context);
    },
  });
  return virtualPath;
}

function barePackage(specifier) {
  return !specifier.startsWith('.') && !specifier.startsWith('#') && !path.isAbsolute(specifier)
    && !/^[a-zA-Z][a-zA-Z\d+.-]*:/.test(specifier);
}
function localPackageExists(specifier, parentURL) {
  if (!parentURL?.startsWith('file:')) return true;
  const name = specifier.startsWith('@') ? specifier.split('/').slice(0,2).join('/') : specifier.split('/')[0];
  for (let directory = path.dirname(fileURLToPath(parentURL));; directory = path.dirname(directory)) {
    try { fs.lstatSync(path.join(directory,'node_modules',name)); return true; }
    catch (error) { if (!['ENOENT','ENOTDIR'].includes(error.code)) throw error; }
    if (path.dirname(directory) === directory) return false;
  }
}
