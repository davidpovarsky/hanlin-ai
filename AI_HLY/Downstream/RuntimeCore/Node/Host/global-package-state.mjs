import { promises as fs } from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';

const commits = new Map();
const metadata = '.hanlin-package-transaction.json';
const published = '.hanlin-package-published.json';
const validID = value => typeof value === 'string' && /^[a-z0-9-]{8,80}$/i.test(value);
const pointer = root => path.join(root,'packages','node-global-current.json');

export function transactionRoot(root,id) {
  if (!validID(id)) throw new Error('Invalid global package transaction ID.');
  return path.join(root,'clients','tools',`npm-lifecycle-${id}`);
}
export async function currentGlobalState(root) {
  let state;
  try { state=JSON.parse(await fs.readFile(pointer(root),'utf8')); }
  catch(error) { if(error.code==='ENOENT')return {revision:'legacy',directory:path.join(root,'packages','node-global')}; throw error; }
  if (state.schemaVersion!==1 || !validID(state.transactionID))throw new Error('Invalid global package registry pointer; existing generations were preserved.');
  const directory=transactionRoot(root,state.transactionID);
  await fs.access(path.join(directory,published));
  return {revision:state.transactionID,directory};
}
export async function globalNodeModules(root) {return path.join((await currentGlobalState(root)).directory,'node_modules');}

export async function prepareGlobalTransaction(root) {
  const base=await currentGlobalState(root);
  const transactionID=randomUUID();
  const directory=transactionRoot(root,transactionID);
  await fs.mkdir(path.dirname(directory),{recursive:true});
  let exists=true;
  try {await fs.access(base.directory);}catch(error){if(error.code!=='ENOENT')throw error;exists=false;}
  if(exists)await fs.cp(base.directory,directory,{recursive:true,dereference:false,verbatimSymlinks:true,errorOnExist:true,force:false});
  else await fs.mkdir(directory,{recursive:true});
  // Build products of unchanged dependencies remain intact. The old immutable
  // generation stays available to running Workers and retained package handles.
  await fs.rm(path.join(directory,published),{force:true});
  // Arborist lock locations must use the physical prefix. Otherwise aliases
  // such as macOS /var -> /private/var create transaction-specific lock keys
  // and unchanged dependencies appear changed during every subsequent update.
  return {transactionID,directory:await fs.realpath(directory),baseRevision:base.revision};
}
export async function saveGlobalTransaction(root,transaction) {
  await fs.writeFile(path.join(transactionRoot(root,transaction.transactionID),metadata),JSON.stringify(transaction),{mode:0o600});
}
export async function loadGlobalTransaction(root,transactionID) {
  const transaction=JSON.parse(await fs.readFile(path.join(transactionRoot(root,transactionID),metadata),'utf8'));
  if(transaction.transactionID!==transactionID)throw new Error('Package transaction identity changed.');
  return transaction;
}
export async function publishGlobalTransaction(root,transactionID) {
  const previous=commits.get(root)??Promise.resolve();
  const commit=previous.catch(()=>{}).then(async()=>{
    const transaction=await loadGlobalTransaction(root,transactionID);
    const current=await currentGlobalState(root);
    if(current.revision===transactionID)return {committed:true};
    if(current.revision!==transaction.baseRevision)throw new Error('Installed packages changed while this transaction was running; retry against the current generation.');
    const directory=transactionRoot(root,transactionID);
    await fs.writeFile(path.join(directory,published),JSON.stringify({committedAt:Date.now()}),{mode:0o600});
    await fs.mkdir(path.dirname(pointer(root)),{recursive:true});
    const temporary=pointer(root)+'.'+randomUUID()+'.tmp';
    await fs.writeFile(temporary,JSON.stringify({schemaVersion:1,transactionID}),{mode:0o600});
    try {await fs.rename(temporary,pointer(root));}
    catch(error){await fs.rm(temporary,{force:true});throw error;}
    return {committed:true};
  });
  commits.set(root,commit);
  try{return await commit;}finally{if(commits.get(root)===commit)commits.delete(root);}
}
export async function discardGlobalTransaction(root,transactionID) {
  const directory=transactionRoot(root,transactionID);
  try {await fs.access(path.join(directory,published));}
  catch(error) {if(error.code!=='ENOENT')throw error;await fs.rm(directory,{recursive:true,force:true});return {rolledBack:true};}
  throw new Error('Published package generations are retained for active Workers; rollback cannot delete them.');
}
