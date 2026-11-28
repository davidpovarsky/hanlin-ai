import path from 'node:path';
import {verifyLifecyclePlan} from './lifecycle-planner.mjs';
import {executePortableShell,packageLifecycleEnvironment} from './portable-shell.mjs';
import {pruneOptionalLifecycleFailure} from './optional-lifecycle.mjs';

export async function executeLifecycleAction(action,root) {
  const cwd=path.resolve(root,action.workingDirectory??'.');
  const environment=await packageLifecycleEnvironment({cwd,environment:process.env,
    packageName:action.packageName,packageVersion:action.packageVersion,event:action.script,
    source:action.source,initialCwd:root});
  const exitCode=await executePortableShell(action.source,[],{cwd,environment});
  process.exitCode=exitCode;
  return exitCode;
}

/** Existing durable Node jobs and the Host-lifetime native command pump.
 * There is no second engine or subprocess implementation for installation.
 */
export async function executeLifecycleInJobs({jobs,plan,packageRoot,runtimeRoot,signal,onProgress=()=>{}}) {
  if(!plan.executable||plan.rejected.length)throw new Error('The lifecycle plan contains invalid shell syntax.');
  await verifyLifecyclePlan(packageRoot,plan);
  const omitted=new Set();
  for(const action of plan.actions) {
    if(omitted.has(action.workingDirectory))continue;
    signal?.throwIfAborted();
    const source=`import {executeLifecycleAction} from ${JSON.stringify(import.meta.url)};
      export default await executeLifecycleAction(${JSON.stringify(action)},${JSON.stringify(packageRoot)});`;
    const header=await jobs.start({source,moduleKind:'esm',workspace:path.resolve(packageRoot,action.workingDirectory??'.')});
    const cancel=()=>{void jobs.cancel(header.executionID).catch(()=>{});};
    signal?.addEventListener('abort',cancel,{once:true});
    if(signal?.aborted)cancel();
    try {
      onProgress({executionID:header.executionID,packageName:action.packageName,event:action.script});
      const completed=await jobs.wait(header.executionID);
      signal?.throwIfAborted();
      if(completed.state!=='completed') {
        const error=Object.assign(new Error(`Lifecycle ${action.packageName}:${action.script} failed: ${completed.result?.stderr??completed.error??completed.state}`),
          {code:'lifecycle_failed',executionID:header.executionID,exitCode:completed.result?.exitCode});
        if(action.optional!==true||['cancelled','interrupted'].includes(completed.state)
            ||!Number.isInteger(completed.result?.exitCode)||completed.result.exitCode===0
            ||completed.result.didTimeOut||completed.result.wasCancelled)throw error;
        signal?.throwIfAborted();
        const pruned=await pruneOptionalLifecycleFailure({runtimeRoot,packageRoot,plan,action,error});
        for(const directory of pruned.omittedDirectories)omitted.add(directory);
        onProgress({optionalDependencyOmitted:true,executionID:header.executionID,packageName:action.packageName,
          omittedDirectories:pruned.omittedDirectories});
      }
    }finally{signal?.removeEventListener('abort',cancel);}
  }
}
