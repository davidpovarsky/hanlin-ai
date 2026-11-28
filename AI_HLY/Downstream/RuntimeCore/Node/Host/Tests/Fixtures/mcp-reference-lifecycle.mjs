import path from 'node:path';
import {promises as fs} from 'node:fs';
import {ExecutionJobs} from '../../execution-jobs.mjs';
import {executeLifecycleInJobs} from '../../lifecycle-executor.mjs';

/** Actual Node-to-Node reference receipt pump. No subprocess or iOS claim. */
export async function referenceMCPLifecycle(root) {
  const jobs=new ExecutionJobs({root:path.join(root,'jobs','node'),workerURL:new URL('../../execution-worker.mjs',import.meta.url)});
  await jobs.initialize();
  return async options=>{
    let settled=false;
    const work=executeLifecycleInJobs({...options,jobs,runtimeRoot:root});
    work.then(()=>{settled=true;},()=>{settled=true;});
    const owners=new Map();
    while(!settled) {
      for(const request of await jobs.allCommandRequests()) {
        if(owners.has(request.id))continue;
        owners.set(request.id,(async()=>{
          try {
            if(request.engine!=='node'&&!['node','nodejs'].includes(request.command))
              throw new Error('Reference fixture has only the real Node CLI adapter: '+request.command);
            const script=request.entryPoint??request.arguments[0];
            if(!script||script.startsWith('-'))throw new Error('The linked Node CLI accepts a script file; unsupported flags are not simulated.');
            const child=await jobs.start({executionID:request.id,executionMode:'cli',entryPoint:path.resolve(request.cwd,script),
              workspace:request.cwd,moduleKind:'commonjs',arguments:request.entryPoint?request.arguments:request.arguments.slice(1),
              environment:request.environment,standardInputPath:request.standardInputPath});
            const completed=await jobs.wait(child.executionID),result=completed.result;
            if(!result?.outputFiles)throw new Error(completed.error??'Missing actual Node command output.');
            const response=path.join(path.dirname(request.standardInputPath),'response.json');
            await fs.writeFile(response+'.tmp',JSON.stringify({executionID:child.executionID,exitCode:result.exitCode,
              stdoutPath:result.outputFiles.stdout.path,stderrPath:result.outputFiles.stderr.path}));
            await fs.rename(response+'.tmp',response);
          }catch(error){await jobs.failCommand(request.parentExecutionID,request.id,error.message);}
        })());
      }
      await new Promise(resolve=>setTimeout(resolve,10));
    }
    await Promise.all(owners.values());
    return work;
  };
}
