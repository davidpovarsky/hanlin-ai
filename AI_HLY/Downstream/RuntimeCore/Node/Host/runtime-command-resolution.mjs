import { promises as fs, createReadStream } from 'node:fs';
import path from 'node:path';
import { workerData } from 'node:worker_threads';

/** Resolve real installed bin files. Native interpreter validity remains the
 * chosen engine's responsibility; no shell wrappers are parsed into commands. */
export async function resolveRuntimeCommand(command, cwd, environment) {
  if (['node', 'nodejs', 'python', 'python3'].includes(command)) return {};
  const candidates = command.includes('/') || command.includes('\\') ? [path.resolve(cwd, command)]
    : (environment.PATH ?? '').split(path.delimiter).filter(Boolean).map(folder => path.resolve(cwd, folder, command));
  if (workerData?.globalNodeModules && !command.includes('/')) candidates.push(path.join(workerData.globalNodeModules, '.bin', command));
  for (const candidate of candidates) {
    let file;
    try { file = await fs.realpath(candidate); if (!(await fs.stat(file)).isFile()) continue; }
    catch (error) { if (['ENOENT','ENOTDIR'].includes(error.code)) continue; throw error; }
    const extension = path.extname(file).toLowerCase();
    if (['.js','.cjs','.mjs','.ts','.cts','.mts'].includes(extension)) return {engine:'node',entryPoint:file};
    if (['.py','.pyw','.pyc'].includes(extension)) return {engine:'python',entryPoint:file};
    const descriptor = await fs.open(file,'r');
    const start = Buffer.alloc(2);
    try { await descriptor.read(start,0,2,0); } finally { await descriptor.close(); }
    if (start.toString() !== '#!') continue;
    let line = '';
    for await (const chunk of createReadStream(file, {encoding:'utf8'})) {
      line += chunk;
      if (line.includes('\n')) { line=line.split('\n',1)[0]; break; }
    }
    const words = line.slice(2).trim().split(/\s+/);
    const executable = path.basename(words[0] ?? '');
    const interpreter = executable === 'env' ? words[1] : executable;
    if (['node','nodejs'].includes(interpreter) && words.length === (executable==='env'?2:1)) return {engine:'node',entryPoint:file};
    if (/^python(?:3(?:\.\d+)?)?$/.test(interpreter ?? '') && words.length === (executable==='env'?2:1)) return {engine:'python',entryPoint:file};
  }
  return {};
}
