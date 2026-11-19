import test from 'node:test';
import assert from 'node:assert/strict';
import {createUpstreamProtectionAccess, ordinaryUpstreamEnvironment, PROTECTION_TOKEN_KEY}
  from '../upstream-protection-access.mjs';
import {protectionQuery, readUpstreamProtection} from '../upstream-protection-reader.mjs';

const scope={repository:'davidpovarsky/hanlin-ai',base:'codex/upstream-acceptance-base-20261119-v3',baseSHA:'d6e2e3f062633fe7a55c0f44b922c5b3321aaf4a'};
const original={GITHUB_ACTIONS:'true',GH_TOKEN:'synthetic-actions-write',GITHUB_TOKEN:'synthetic-second-write',
  RENOVATE_TOKEN:'synthetic-renovate-write',GH_ENTERPRISE_TOKEN:'synthetic-enterprise-write',
  GITHUB_ENTERPRISE_TOKEN:'synthetic-enterprise-second',GH_HOST:'untrusted.example',
  [PROTECTION_TOKEN_KEY]:'synthetic-administration-read',PATH:'synthetic-path'};
function client(environment=original, response='{}') {
  const calls=[];
  const access=createUpstreamProtectionAccess({...scope,environment,execute:(file,args,options)=>{
    calls.push({file,args,options});return response;
  }});
  return {access,calls};
}
const protectionPath='branches/'+encodeURIComponent(scope.base)+'/protection';
const rulesPath='rules/branches/'+encodeURIComponent(scope.base);

test('CI missing or empty protection credentials fail before any API call',()=>{
  for(const value of [undefined,'',' ','token\nsuffix',' token']){
    const env={...original,[PROTECTION_TOKEN_KEY]:value};
    let called=false;
    assert.throws(()=>createUpstreamProtectionAccess({...scope,environment:env,execute:()=>{called=true;}}),
      /dedicated|credential/);
    assert.equal(called,false);
  }
});
test('ordinary API, proof publication, merge and archive child environments omit the read credential',()=>{
  const actual=ordinaryUpstreamEnvironment(original);
  assert.equal(actual[PROTECTION_TOKEN_KEY],undefined);
  assert.equal(actual.GH_TOKEN,original.GH_TOKEN);
  assert.equal(actual.GITHUB_TOKEN,original.GITHUB_TOKEN);
  assert.equal(actual.RENOVATE_TOKEN,original.RENOVATE_TOKEN);
  assert.equal(actual.PATH,original.PATH);
  assert.equal(original[PROTECTION_TOKEN_KEY],'synthetic-administration-read');
});
test('dedicated REST protection read uses fixed GitHub host, GET and only the read token',()=>{
  const {access,calls}=client();
  assert.deepEqual(access.rest(protectionPath),{});
  assert.equal(access.credentialMode,'DEDICATED_REPOSITORY_ADMINISTRATION_READ');
  assert.deepEqual(calls[0].args,['api','--hostname','github.com','repos/'+scope.repository+'/'+protectionPath,'--method','GET']);
  const env=calls[0].options.env;
  assert.equal(env.GH_TOKEN,original[PROTECTION_TOKEN_KEY]);
  for(const key of ['GITHUB_TOKEN','RENOVATE_TOKEN','GH_ENTERPRISE_TOKEN','GITHUB_ENTERPRISE_TOKEN',PROTECTION_TOKEN_KEY])
    assert.equal(env[key],undefined,key);
  assert.equal(env.GH_HOST,'github.com'); assert.equal(env.PATH,original.PATH);
  assert.equal(calls[0].options.input,undefined);
  assert.equal(original.GH_TOKEN,'synthetic-actions-write');
});
test('separate effective-rules request uses the same exact repository/base read access',()=>{
  const {access,calls}=client(original,'[]');
  assert.deepEqual(access.rest(rulesPath),[]);
  assert.equal(calls[0].args[3],'repos/'+scope.repository+'/'+rulesPath);
  assert.equal(calls[0].args.at(-1),'GET');
  assert.equal(calls[0].options.env.GH_TOKEN,original[PROTECTION_TOKEN_KEY]);
});
test('write endpoints, other refs and added query strings are rejected before execution',()=>{
  const {access,calls}=client();
  for(const path of ['check-runs','pulls/15/merge','branches/main/protection',rulesPath+'?extra=1',
    protectionPath+'/enforce_admins',protectionPath.replace('-v3','-v2'),'../'+protectionPath])
    assert.throws(()=>access.rest(path),/cannot access/);
  assert.equal(calls.length,0);
});
test('foreign repository, unapproved base and malformed SHA cannot receive the credential',()=>{
  for(const extra of [{repository:'elsewhere/hanlin-ai'},{base:'main'},
    {base:'codex/upstream-acceptance-base-20261119-v4'},{base:scope.base+'/child'},{baseSHA:'not-a-sha'}])
    assert.throws(()=>createUpstreamProtectionAccess({...scope,...extra,environment:original}),/restricted/);
});
test('exact original GraphQL projection is permitted with the separate read token',()=>{
  const {access,calls}=client(original,'{"data":{"repository":null}}');
  const body={query:protectionQuery,variables:{owner:'davidpovarsky',name:'hanlin-ai',ref:'refs/heads/'+scope.base}};
  assert.deepEqual(access.graphql(body),{data:{repository:null}});
  assert.deepEqual(calls[0].args,['api','--hostname','github.com','graphql','--input','-']);
  assert.deepEqual(JSON.parse(calls[0].options.input),body);
  assert.equal(calls[0].options.env.GH_TOKEN,original[PROTECTION_TOKEN_KEY]);
});
test('GraphQL mutations, aliases, different refs and extra fields cannot use the read credential',()=>{
  const {access,calls}=client();
  const body={query:protectionQuery,variables:{owner:'davidpovarsky',name:'hanlin-ai',ref:'refs/heads/'+scope.base}};
  for(const candidate of [{...body,query:'mutation{deleteBranchProtectionRule}'},
    {...body,query:protectionQuery+' query{viewer{login}}'},
    {...body,variables:{...body.variables,ref:'refs/heads/main'}},
    {...body,variables:{...body.variables,unused:'x'}},{...body,operationName:'Anything'},null])
    assert.throws(()=>access.graphql(candidate),/exact read-only/);
  assert.equal(calls.length,0);
});
test('read errors redact credentials while preserving structured HTTP status diagnostics',()=>{
  const access=createUpstreamProtectionAccess({...scope,environment:original,execute:()=>{
    throw Object.assign(Error('denied '+original[PROTECTION_TOKEN_KEY]),{
      stdout:JSON.stringify({status:403,message:original.GH_TOKEN}),
      stderr:'HTTP 403 '+original[PROTECTION_TOKEN_KEY]+' '+original.GITHUB_TOKEN,status:1,
      output:[original[PROTECTION_TOKEN_KEY]],env:original
    });
  }});
  assert.throws(()=>access.rest(protectionPath),error=>{
    assert.equal(JSON.parse(error.stdout).status,403);
    assert.match(error.message,/\[REDACTED\]/);
    assert.match(error.stderr,/HTTP 403/);
    assert.equal(error.output,undefined);assert.equal(error.cause,undefined);assert.equal(error.env,undefined);
    const serialized=error.message+JSON.stringify(error);
    for(const value of [original[PROTECTION_TOKEN_KEY],original.GH_TOKEN,original.GITHUB_TOKEN])
      assert.equal(serialized.includes(value),false);
    return true;
  });
});
test('dedicated REST authorization failure does not silently retry with an ordinary write credential',()=>{
  const calls=[];
  const access=createUpstreamProtectionAccess({...scope,environment:original,execute:(file,args,options)=>{
    calls.push(options.env.GH_TOKEN);
    throw Object.assign(Error('denied'),{stdout:'{"status":403}',stderr:'HTTP 403'});
  }});
  assert.throws(()=>readUpstreamProtection({...scope,rest:access.rest,graphql:access.graphql}),
    /GraphQL protection could not establish/);
  assert.deepEqual(calls,[original[PROTECTION_TOKEN_KEY],original[PROTECTION_TOKEN_KEY]]);
});
test('local authenticated read-only inspection preserves existing gh authorization when no dedicated token is supplied',()=>{
  const env={GH_TOKEN:'synthetic-local-auth',PATH:'local'};
  const {access,calls}=client(env);
  access.rest(protectionPath);
  assert.equal(access.credentialMode,'EXISTING_LOCAL_GH_AUTH');
  assert.equal(calls[0].options.env.GH_TOKEN,env.GH_TOKEN);
  assert.equal(calls[0].options.env[PROTECTION_TOKEN_KEY],undefined);
  assert.deepEqual(env,{GH_TOKEN:'synthetic-local-auth',PATH:'local'});
});
test('malformed API JSON remains a rejection, not an empty successful protection',()=>{
  const {access}=client(original,'not json');
  assert.throws(()=>access.rest(protectionPath),/JSON|Unexpected token/);
});
