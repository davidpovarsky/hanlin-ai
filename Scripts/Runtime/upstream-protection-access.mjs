// A dedicated repository Administration:read credential is never used for writes.
import {execFileSync} from 'node:child_process';
import {isProtectedAcceptanceBase} from './upstream-run-consumer-policy.mjs';
import {protectionQuery} from './upstream-protection-reader.mjs';

export const PROTECTION_TOKEN_KEY = 'HANLIN_UPSTREAM_PROTECTION_READ_TOKEN';
const credentialKeys = ['GH_TOKEN','GITHUB_TOKEN','GH_ENTERPRISE_TOKEN','GITHUB_ENTERPRISE_TOKEN','RENOVATE_TOKEN',PROTECTION_TOKEN_KEY];

export function ordinaryUpstreamEnvironment(environment = process.env) {
  const result = {...environment};
  delete result[PROTECTION_TOKEN_KEY];
  return result;
}

export function createUpstreamProtectionAccess({
  repository, base, baseSHA, environment = process.env, execute = execFileSync
}) {
  if (repository !== 'davidpovarsky/hanlin-ai' || !isProtectedAcceptanceBase(base)
      || !/^[a-f0-9]{40}$/.test(baseSHA ?? ''))
    throw Error('Protection credential is restricted to an exact owned acceptance base');
  const token = environment[PROTECTION_TOKEN_KEY];
  if (token !== undefined && (typeof token !== 'string' || !token || token.trim() !== token || /[\r\n]/.test(token)))
    throw Error('The dedicated upstream protection read credential is empty or malformed');
  if (environment.GITHUB_ACTIONS === 'true' && !token)
    throw Error('GitHub Actions requires the dedicated repository Administration:read credential');
  const readEnvironment = ordinaryUpstreamEnvironment(environment);
  if (token) {
    for (const key of credentialKeys) delete readEnvironment[key];
    readEnvironment.GH_TOKEN = token;
  }
  readEnvironment.GH_HOST = 'github.com';
  const secrets = credentialKeys.map(key=>environment[key]).filter(value=>typeof value === 'string' && value.length);
  const redact = value => secrets.reduce((text,secret)=>text.replaceAll(secret,'[REDACTED]'),String(value ?? ''));
  const invoke = (args, body) => {
    try {
      return JSON.parse(execute('gh',args,{env:readEnvironment, input:body === undefined ? undefined : JSON.stringify(body),
        encoding:'utf8',stdio:['pipe','pipe','pipe'],timeout:60_000,maxBuffer:2_097_152}));
    } catch (cause) {
      // Do not retain an original error/cause/output object that could carry a credential.
      const error = Error(redact(cause.message));
      if (cause.stdout !== undefined) error.stdout = redact(cause.stdout);
      if (cause.stderr !== undefined) error.stderr = redact(cause.stderr);
      if (Number.isInteger(cause.status)) error.status = cause.status;
      throw error;
    }
  };
  const prefix = 'repos/'+repository+'/';
  const allowedPaths = new Set([
    'branches/'+encodeURIComponent(base)+'/protection',
    'rules/branches/'+encodeURIComponent(base)
  ]);
  return {
    credentialMode:token ? 'DEDICATED_REPOSITORY_ADMINISTRATION_READ' : 'EXISTING_LOCAL_GH_AUTH',
    rest(path) {
      if (!allowedPaths.has(path)) throw Error('Protection credential cannot access this endpoint');
      return invoke(['api','--hostname','github.com',prefix+path,'--method','GET']);
    },
    graphql(body) {
      const [owner,name] = repository.split('/');
      const variables = body?.variables;
      if (!body || Object.keys(body).sort().join(',') !== 'query,variables'
          || body.query !== protectionQuery || !variables
          || Object.keys(variables).sort().join(',') !== 'name,owner,ref'
          || variables.owner !== owner || variables.name !== name || variables.ref !== 'refs/heads/'+base)
        throw Error('Protection credential requires the exact read-only protection query');
      return invoke(['api','--hostname','github.com','graphql','--input','-'],body);
    }
  };
}
