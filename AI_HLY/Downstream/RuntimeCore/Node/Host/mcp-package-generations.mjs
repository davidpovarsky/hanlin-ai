import {promises as fs} from 'node:fs';
import path from 'node:path';
import {randomUUID} from 'node:crypto';

const marker = path.join('.hanlin-runtime', 'installation-transaction.json');
const transitions = new Map();
const validID = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);

export function mcpGenerationDirectory(root, serverID, operationID) {
  if (!validID(serverID) || !validID(operationID)) throw new Error('Invalid MCP generation identity.');
  return path.join(root, 'packages', 'mcp', serverID.toLowerCase(), '.hanlin-generations', operationID.toLowerCase());
}

export async function publishMCPGeneration({root, serverID, operationID, packageRoot}) {
  const directory = mcpGenerationDirectory(root, serverID, operationID);
  try {await fs.access(directory); throw new Error('This MCP generation already exists; existing code was preserved.');}
  catch (error) {if (error.code !== 'ENOENT') throw error;}
  await fs.mkdir(path.dirname(directory), {recursive: true});
  const legacy = path.dirname(path.dirname(directory));
  if ((await fs.lstat(legacy)).isSymbolicLink()
      || (await fs.lstat(path.dirname(directory))).isSymbolicLink()) {
    throw new Error('MCP generation parent must not be a symbolic link.');
  }
  await fs.mkdir(path.join(packageRoot, '.hanlin-runtime'), {recursive: true});
  await fs.writeFile(path.join(packageRoot, marker), JSON.stringify({schemaVersion: 1,
    serverID: serverID.toLowerCase(), operationID: operationID.toLowerCase(), state: 'staged'}), {flag: 'wx', mode: 0o600});
  // Running Workers keep their physical package root, including late imports.
  // The persisted Swift descriptor selects the new generation; no legacy tree
  // or previous generation is moved, overwritten or recursively deleted.
  await fs.rename(packageRoot, directory);
  return directory;
}

async function readTransaction(directory, serverID, operationID) {
  const transaction = JSON.parse(await fs.readFile(path.join(directory, marker), 'utf8'));
  if (transaction.schemaVersion !== 1 || transaction.serverID !== serverID.toLowerCase()
      || transaction.operationID !== operationID.toLowerCase()
      || !['staged', 'committed', 'rolledBack'].includes(transaction.state)) {
    throw new Error('MCP generation transaction identity is invalid; existing code was preserved.');
  }
  return transaction;
}

export async function finishMCPGeneration({root, serverID, operationID, state}) {
  if (!['committed', 'rolledBack'].includes(state)) throw new Error('Invalid MCP transaction transition.');
  const directory = mcpGenerationDirectory(root, serverID, operationID);
  const previous = transitions.get(directory) ?? Promise.resolve();
  const operation = previous.catch(() => {}).then(async () => {
    const transaction = await readTransaction(directory, serverID, operationID);
    if (transaction.state === state) return;
    if (transaction.state !== 'staged') throw new Error('The MCP transaction already reached another terminal state.');
    const temporary = path.join(directory, marker) + '.' + randomUUID() + '.tmp';
    await fs.writeFile(temporary, JSON.stringify({...transaction, state}), {flag: 'wx', mode: 0o600});
    try {await fs.rename(temporary, path.join(directory, marker));}
    catch (error) {await fs.rm(temporary, {force: true}); throw error;}
    // Retain even rolled-back code: an active validation Worker can still hold
    // this root. Reclamation requires explicit reference-aware maintenance.
  });
  transitions.set(directory, operation);
  try {await operation;} finally {if (transitions.get(directory) === operation) transitions.delete(directory);}
}

export async function resolveMCPPackageRoot(root, serverID, requestedRoot) {
  const legacy = path.resolve(root, 'packages', 'mcp', serverID);
  const requested = path.resolve(requestedRoot);
  if ((await fs.lstat(legacy)).isSymbolicLink()) throw new Error('MCP server directory must not be a symbolic link.');
  const legacyPhysical = await fs.realpath(legacy);
  const physical = await fs.realpath(requested);
  if (physical === legacyPhysical) return physical;
  const operationID = path.basename(requested);
  mcpGenerationDirectory(root, serverID, operationID); // validates the supplied generation identity
  const expected = path.join(legacyPhysical, '.hanlin-generations', operationID.toLowerCase());
  if (physical !== expected) throw new Error('MCP generation escapes its installed server directory.');
  const transaction = await readTransaction(physical, serverID, operationID);
  if (transaction.state === 'rolledBack') throw new Error('This MCP generation was rolled back.');
  return physical;
}
