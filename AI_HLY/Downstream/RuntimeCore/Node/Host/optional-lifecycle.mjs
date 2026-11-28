import {promises as fs} from 'node:fs';
import path from 'node:path';
import {lifecycleFingerprint,verifyLifecyclePlan} from './lifecycle-planner.mjs';
import {loadGlobalTransaction,saveGlobalTransaction} from './global-package-state.mjs';

const failureFile='.hanlin-optional-build-failures.json';
const key=(root,file)=>path.relative(root,file).split(path.sep).join('/');
const inside=(root,file)=>{const relative=path.relative(root,file);return relative!==''&&relative!=='..'&&!relative.startsWith('..'+path.sep)&&!path.isAbsolute(relative);};

/** A failed optional install is absent on disk even when its lock entry remains.
 * On a later transaction, reify may restore it. It must run its hooks again,
 * rather than treating the unchanged lock entry as a previously built product.
 */
export async function prepareOptionalBuildRetry(directory,previousPackages) {
  const file=path.join(directory,failureFile);
  let receipt;
  try{receipt=JSON.parse(await fs.readFile(file,'utf8'));}
  catch(error){if(error.code==='ENOENT')return;throw error;}
  if(receipt.schemaVersion!==1||!Array.isArray(receipt.omittedDirectories))throw new Error('Invalid optional-build receipt; staging was preserved.');
  for(const name of receipt.omittedDirectories)delete previousPackages[name];
  await fs.rm(file);
}

/** Only a private install transaction can omit failed optional branches.
 * The public Arborist graph owns optional classification. Never trust a caller
 * flag to remove a required dependency, a published generation or user source.
 */
export async function pruneOptionalLifecycleFailure({runtimeRoot,packageRoot,plan,action,error}) {
  const runtime=await fs.realpath(runtimeRoot),root=await fs.realpath(packageRoot);
  const relative=key(runtime,root);
  const globalMatch=relative.match(/^clients\/tools\/npm-lifecycle-([0-9a-f-]{36})$/i);
  const mcp= /^staging\/[0-9a-f-]{36}\/package$/i.test(relative);
  if(!globalMatch&&!mcp)throw new Error('Optional omission requires a private package-install transaction.');
  try{await fs.access(path.join(root,'.hanlin-package-published.json'));throw new Error('A published package generation cannot be pruned.');}
  catch(problem){if(problem.code!=='ENOENT')throw problem;}
  const transaction=globalMatch?await loadGlobalTransaction(runtime,globalMatch[1]):null;
  const planFile=path.join(root,'.hanlin-runtime','lifecycle-plan.json');
  const currentPlan=transaction?.plan??JSON.parse(await fs.readFile(planFile,'utf8'));
  if(plan.scriptHash!==lifecycleFingerprint(plan)||currentPlan.scriptHash!==lifecycleFingerprint(currentPlan)
      ||!currentPlan.actions.some(item=>lifecycleFingerprint({...currentPlan,actions:[item]})===lifecycleFingerprint({...currentPlan,actions:[action]}))||action.optional!==true)
    throw new Error('Optional lifecycle action identity changed.');
  await verifyLifecyclePlan(root,currentPlan);
  const {default:Arborist}=await import('@npmcli/arborist');
  const arborist=new Arborist({path:root,ignoreScripts:true,binLinks:true,audit:false,fund:false});
  const tree=await arborist.loadActual();
  const directory=await fs.realpath(path.resolve(root,action.workingDirectory));
  const failed=[...tree.inventory.values()].find(node=>node.optional===true&&path.resolve(node.realpath)===directory);
  if(!failed||failed.package.name!==action.packageName||failed.package.version!==action.packageVersion)
    throw new Error('The failed lifecycle is not an actual optional dependency.');

  // Follow required incoming edges to the optional boundary, then compute the
  // dependency closure which has no surviving outside consumers. Public graph
  // semantics match npm's optional-set behavior, including shared deps/cycles.
  const boundary=new Set([failed]);
  for(const node of boundary)for(const edge of node.edgesIn)if(!edge.optional&&edge.from)boundary.add(edge.from);
  const removed=new Set(boundary);
  for(const node of removed)for(const edge of node.edgesOut.values())if(edge.to)removed.add(edge.to);
  let changed=true;
  while(changed){changed=false;for(const node of removed){
    if([...node.edgesIn].some(edge=>!removed.has(edge.from)&&!boundary.has(node))){removed.delete(node);changed=true;}
  }}
  for(const node of removed)if(node===tree||node.optional!==true||!inside(root,node.path)||!inside(root,node.realpath))
    throw new Error('Optional omission would affect a required package or escape staging.');
  for(const survivor of tree.inventory.values())if(!removed.has(survivor)
      &&[...removed].some(node=>inside(node.path,survivor.realpath)))
    throw new Error('An optional parent contains a surviving dependency; staging was preserved.');
  const omittedDirectories=[...removed].map(node=>key(root,node.realpath));
  const deletePaths=new Set([...removed].flatMap(node=>[node.path,...node.binPaths]));
  // Validate every final target before any removal. Remove links themselves;
  // fs.rm never recursively follows a node_modules symlink into its target.
  for(const file of deletePaths){
    if(!inside(root,path.resolve(file)))throw new Error('Optional package/bin path escapes staging.');
    try{const parent=await fs.realpath(path.dirname(file));if(parent!==root&&!inside(root,parent))throw new Error('Optional package/bin parent escapes staging.');}
    catch(problem){if(problem.code!=='ENOENT')throw problem;}
  }
  for(const file of deletePaths)await fs.rm(file,{recursive:true,force:true});
  for(const node of removed)node.parent=null;
  // Restore any surviving command-link collision with scripts explicitly off.
  await arborist.rebuild({nodes:[...tree.inventory.values()].filter(node=>node!==tree&&!removed.has(node))});
  let prior={omittedDirectories:[],failures:[]};
  try{prior=JSON.parse(await fs.readFile(path.join(root,failureFile),'utf8'));}
  catch(problem){if(problem.code!=='ENOENT')throw problem;}
  const receipt={schemaVersion:1,omittedDirectories:[...new Set([...prior.omittedDirectories,...omittedDirectories])],
    failures:[...prior.failures,{packageName:action.packageName,event:action.script,executionID:error?.executionID??null,
      exitCode:error?.exitCode??null,message:String(error?.message??error)}]};
  await fs.writeFile(path.join(root,failureFile),JSON.stringify(receipt));
  const next={...currentPlan,actions:currentPlan.actions.filter(item=>!omittedDirectories.includes(item.workingDirectory))};
  next.scriptHash=lifecycleFingerprint(next);
  if(transaction)await saveGlobalTransaction(runtime,{...transaction,plan:next});
  else await fs.writeFile(planFile,JSON.stringify(next));
  return {omittedDirectories,plan:next,receipt};
}
