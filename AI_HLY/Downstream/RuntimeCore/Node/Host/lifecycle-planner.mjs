import { createHash } from 'node:crypto';

const lifecycleNames = ['preinstall', 'install', 'postinstall', 'prepare', 'prepublish'];
const fileUtilities = new Set(['cp', 'mv', 'rm', 'mkdir', 'touch', 'cat', 'tar']);

export function planLifecycle(manifest, integrity = null) {
  const actions = [];
  const rejected = [];
  const visiting = new Set();
  for (const name of lifecycleNames) {
    if (manifest.scripts?.[name]) parseScript(name, manifest.scripts[name], manifest, actions, rejected, visiting);
  }
  const scriptHash = createHash('sha256').update(JSON.stringify({
    package: manifest.name,
    version: manifest.version,
    integrity,
    scripts: Object.fromEntries(lifecycleNames.flatMap(name => manifest.scripts?.[name] ? [[name, manifest.scripts[name]]] : [])),
  })).digest('hex');
  return { packageName: manifest.name, packageVersion: manifest.version, integrity, scriptHash, actions, rejected, requiresApproval: actions.length > 0, executable: rejected.length === 0 };
}

function parseScript(name, script, manifest, actions, rejected, visiting) {
  if (/[`|;&><]|\$\(|\$\{/.test(script)) { rejected.push({ script: name, reason: 'Shell expansion, chaining, pipelines, and redirection are unsupported.' }); return; }
  const tokens = tokenize(script);
  const executable = tokens[0];
  if (executable === 'node' && tokens[1]) actions.push({ script: name, kind: 'node', arguments: tokens.slice(1) });
  else if (executable === 'tsc') actions.push({ script: name, kind: 'typescript', arguments: tokens.slice(1) });
  else if ((executable === 'python' || executable === 'python3') && tokens[1]) actions.push({ script: name, kind: 'python', arguments: tokens.slice(1) });
  else if (fileUtilities.has(executable)) actions.push({ script: name, kind: 'fileUtility', command: executable, arguments: tokens.slice(1) });
  else if (executable === 'npm' && tokens[1] === 'run' && tokens[2]) {
    const target = tokens[2];
    if (visiting.has(target)) { rejected.push({ script: name, reason: `Recursive npm script: ${target}` }); return; }
    const nested = manifest.scripts?.[target];
    if (!nested) { rejected.push({ script: name, reason: `Unknown npm script: ${target}` }); return; }
    visiting.add(target); parseScript(target, nested, manifest, actions, rejected, visiting); visiting.delete(target);
  } else rejected.push({ script: name, reason: `Unsupported executable: ${executable || '<empty>'}` });
}

function tokenize(value) {
  const matches = value.match(/"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[^\s]+/g) ?? [];
  return matches.map(item => {
    if ((item.startsWith('"') && item.endsWith('"')) || (item.startsWith("'") && item.endsWith("'"))) return item.slice(1, -1);
    return item;
  });
}
