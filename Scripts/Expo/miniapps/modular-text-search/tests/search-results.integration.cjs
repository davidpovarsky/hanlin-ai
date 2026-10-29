/**
 * Reproduces the real Sefaria search path used by the Hanlin Expo miniapp:
 * request -> Hanlin Node transport -> normalized results -> UI grouping.
 * Runs on a Windows dev machine, not in the device's native Expo runtime.
 */
const assert=require('node:assert/strict');
const cp=require('node:child_process');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const {pathToFileURL}=require('node:url');
const root=path.resolve(__dirname,'..');
async function load(relative){
  return import(pathToFileURL(path.join(root,relative)).href);
}
(async()=>{
  const utils=await load('src/logic/textUtils.js');
  const payload=await load('src/engines/sefaria/searchPayload.js');
  const constants=await load('src/engines/sefaria/constants.js');
  const grouping=await load('src/logic/searchGrouping.js');
  const clientFile=fs.readFileSync(path.join(root,'src/engines/sefaria/client.js'),'utf8');
  const withoutImports=clientFile.replace(/^import[^\n]*\n/gm,'').replace(/^export /gm,'');
  const calls=[];
  const hostServices={
    async executeRuntime(kind,source,options){
      assert.equal(kind,'node');
      assert(options.limits.maximumOutputBytes>=100000);
      calls.push({kind,source});
      try {
        const stdout=cp.execFileSync(process.execPath,['--input-type=module','--eval',source],{
          encoding:'utf8',timeout:29000,maxBuffer:8*1024*1024
        });
        return {exitCode:0,stdout,stderr:'',didTimeOut:false,wasCancelled:false,outputWasTruncated:false};
      }catch(e){
        return {exitCode:1,stdout:'',stderr:String(e.stderr||e.message),didTimeOut:false,wasCancelled:false,outputWasTruncated:false};
      }
    }
  };
  const env={
    hostServices, JSON, String, Number, Error, URL, URLSearchParams,
    SEFARIA_BASE_URL:constants.SEFARIA_BASE_URL,
    SEARCH_ENDPOINT:constants.SEARCH_ENDPOINT,
    TEXTS_ENDPOINT:constants.TEXTS_ENDPOINT,
    buildSearchPayload:payload.buildSearchPayload,
    versionsForMode:payload.versionsForMode,
    ...utils
  };
  const client=vm.runInNewContext(withoutImports+'\n({search,getText,normalizeSearchResponse})',env,{timeout:1000});
  const search=await client.search({...constants.DEFAULT_SEARCH_OPTIONS,query:'שבת',size:10});
  assert(Array.isArray(search.results));
  assert(search.results.length>0,'Sefaria returned zero normalized results');
  const groups=grouping.groupSearchResults(search.results);
  assert(groups.length>0,'Results were discarded by UI grouping');
  assert(groups.every(g=>g.primary && g.primary.id),'Result card missing primary hit');
  assert(groups[0].primary.ref,'Result card missing reference');
  assert(calls.length>0,'Hanlin Node transport was never called');
  console.log('PASS Sefaria->Node->normalize->group');
  console.log('RESULTS='+search.results.length+' GROUPS='+groups.length+' FIRST_REF='+groups[0].primary.ref);
})().catch(e=>{console.error('FAIL '+(e.stack||e));process.exitCode=1});
