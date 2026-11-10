import { execute, globUtils, hanlinCommandAdapterVersion } from '@yarnpkg/shell';
import { parseShell } from '@yarnpkg/parsers';
import { npath } from '@yarnpkg/fslib';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { workerData } from 'node:worker_threads';
import { dispatchRuntimeCommand } from './runtime-command-client.mjs';

if (hanlinCommandAdapterVersion !== 1) throw new Error('The authenticated Yarn command-adapter patch is missing. Rebuild the Host dependencies.');

/** Public upstream parser for previews; retain the original source for execution. */
export function validatePortableShell(source) {
  parseShell(source, { isGlobPattern: globUtils.isGlobPattern });
}

/**
 * Yarn handles its original quoting, variables, globbing, pipes and redirects.
 * The narrow audited extension dispatches expanded external commands through
 * existing engine adapters, with no OS fork/spawn fallback. No AST round trip,
 * private parser hooks, hand tokenization or claim of full Bash compatibility.
 */
export async function executePortableShell(source, args = [], {
  cwd = process.cwd(), environment = process.env,
  stdin = process.stdin, stdout = process.stdout, stderr = process.stderr,
  dispatch,
} = {}) {
  return execute(source, args, {
    cwd: npath.toPortablePath(cwd), env: { ...environment }, stdin, stdout, stderr,
    executeCommand: async (command, arguments_, context) => {
      const adapter = dispatch ?? (workerData?.commandPort ? dispatchRuntimeCommand : undefined);
      const request = { command, arguments: arguments_, cwd: npath.fromPortablePath(context.cwd),
        environment: { ...context.env }, stdin: context.stdin, stdout: context.stdout, stderr: context.stderr };
      if (command === 'npm' && ['run','run-script','test','start','stop','restart'].includes(arguments_[0])) {
        return executeNpmScript(request, adapter);
      }
      if (!adapter) {
        context.stderr.write(`No linked runtime adapter is available for command: ${command}\n`);
        return 127;
      }
      const code = await adapter(request);
      if (!Number.isInteger(code)) throw new TypeError('A runtime command adapter must return its actual integer exit code.');
      return code;
    },
  });
}


async function executeNpmScript(context, dispatch) {
  const [operation, ...arguments_] = context.arguments;
  const run = ['run','run-script'].includes(operation);
  const target = run ? arguments_.shift() : operation;
  const manifestPath = path.join(context.cwd, 'package.json');
  const manifest = JSON.parse(await fs.readFile(manifestPath, 'utf8'));
  if (!target) {
    context.stdout.write(JSON.stringify(manifest.scripts ?? {}, null, 2) + '\n');
    return 0;
  }
  if (target.startsWith('-')) {
    context.stderr.write('This npm run adapter expects a script name before script arguments.\n');
    return 2;
  }
  if (arguments_[0] === '--') arguments_.shift();
  const scripts = { ...manifest.scripts };
  if (target === 'start' && !scripts.start) {
    try { if ((await fs.stat(path.join(context.cwd,'server.js'))).isFile()) scripts.start='node server.js'; }
    catch (error) { if(error.code!=='ENOENT') throw error; }
  }
  if (typeof scripts[target] !== 'string') {
    context.stderr.write(`Missing npm script: ${target}\n`);
    return 1;
  }
  for (const event of ['pre'+target,target,'post'+target]) {
    if (scripts[event] == null) continue;
    if (typeof scripts[event] !== 'string') throw new TypeError(`npm script ${event} must be a string.`);
    const status = await executePortableShell(scripts[event], event===target?arguments_:[], {
      ...context, environment: await packageLifecycleEnvironment({cwd:context.cwd,environment:context.environment,manifest,event,source:scripts[event],command:'run-script'}), dispatch,
    });
    if (status !== 0) return status;
  }
  return 0;
}


export async function packageLifecycleEnvironment({cwd,environment,manifest,packageName,packageVersion,event,source,initialCwd,command='install'}) {
  manifest??=JSON.parse(await fs.readFile(path.join(cwd,'package.json'),'utf8'));
  const bins=[];
  for(let directory=cwd;;directory=path.dirname(directory)) {
    bins.push(path.join(directory,'node_modules','.bin'));
    if(path.dirname(directory)===directory)break;
  }
  const packageValues={};
  const flatten=(key,value)=>{
    if(value===undefined)return;
    if(value!==null && typeof value==='object')for(const [child,item] of Object.entries(value))flatten(key+'_'+child,item);
    else packageValues[key]=value===null||value===false?'':String(value);
  };
  // npm RFC 183: lifecycle metadata includes these five package fields only.
  for(const key of ['name','version','config','engines','bin'])flatten('npm_package_'+key,manifest[key]);
  return {...environment,...packageValues,INIT_CWD:environment.INIT_CWD??initialCwd??cwd,
    PATH:[...bins,environment.PATH??''].join(path.delimiter),
    npm_package_json:path.join(cwd,'package.json'),npm_package_name:String(packageName??manifest.name??''),
    npm_package_version:String(packageVersion??manifest.version??''),npm_command:command,
    npm_lifecycle_event:event,npm_lifecycle_script:source};
}
