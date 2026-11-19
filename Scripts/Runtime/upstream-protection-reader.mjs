// Read the same classic protection through an authenticated, exact-ref API.
// GraphQL does not prove effective rulesets; the separate REST rules read remains required.
import {isProtectedAcceptanceBase} from './upstream-run-consumer-policy.mjs';
const sha = value => /^[a-f0-9]{40}$/.test(value ?? '');
const text = value => typeof value === 'string' && value.trim().length > 0;
const positiveID = value => Number.isSafeInteger(value) && value > 0;
export const protectionQuery = `query($owner:String!,$name:String!,$ref:String!){
  repository(owner:$owner,name:$name){nameWithOwner ref(qualifiedName:$ref){
    name target{oid} branchProtectionRule{id pattern isAdminEnforced requiresStatusChecks
      requiresStrictStatusChecks requiredStatusCheckContexts
      requiredStatusChecks{context app{databaseId slug}}}
  }}
}`;
function requireExactScope(repository, base, baseSHA) {
  if (repository !== 'davidpovarsky/hanlin-ai' || !isProtectedAcceptanceBase(base) || !sha(baseSHA))
    throw Error('GraphQL protection read is restricted to an exact owned acceptance base');
}
export function projectProtection(response, {repository, base, baseSHA}) {
  requireExactScope(repository, base, baseSHA);
  if (response?.errors !== undefined && (!Array.isArray(response.errors) || response.errors.length))
    throw Error('GraphQL protection response contains errors; configuration remains unknown');
  const repo = response?.data?.repository;
  const ref = repo?.ref;
  const rule = ref?.branchProtectionRule;
  if (repo?.nameWithOwner !== repository || ref?.name !== base || ref?.target?.oid !== baseSHA)
    throw Error('GraphQL protection repository/ref/base SHA does not match the current PR');
  if (!rule || !text(rule.id) || rule.pattern !== base)
    throw Error('Missing exact-base classic protection rule; wildcard rules are not accepted');
  if (![rule.isAdminEnforced,rule.requiresStatusChecks,rule.requiresStrictStatusChecks].every(value=>typeof value === 'boolean'))
    throw Error('Unknown GraphQL protection boolean; configuration remains unknown');
  const contexts = rule.requiredStatusCheckContexts;
  const bindings = rule.requiredStatusChecks;
  if (!Array.isArray(contexts) || !contexts.every(text) || new Set(contexts).size !== contexts.length
      || !Array.isArray(bindings) || !bindings.every(row=>row && text(row.context)
        && (row.app === null || (positiveID(row.app?.databaseId) && text(row.app?.slug))))
      || new Set(bindings.map(row=>row.context)).size !== bindings.length)
    throw Error('Incomplete or ambiguous GraphQL required-check configuration');
  const declaredContexts=new Set(contexts);
  if (bindings.length !== contexts.length || bindings.some(row=>!declaredContexts.has(row.context)))
    throw Error('GraphQL required context and binding declarations disagree');
  return {
    protection:{enforce_admins:{enabled:rule.isAdminEnforced},
      required_status_checks:rule.requiresStatusChecks ? {
        strict:rule.requiresStrictStatusChecks, contexts:[...contexts],
        checks:bindings.map(row=>({context:row.context,app_id:row.app?.databaseId ?? null}))
      } : null},
    observation:{api:'AUTHENTICATED_GRAPHQL_EXACT_REF',repository,base,baseSHA,
      ruleID:rule.id,rulePattern:rule.pattern,adminEnforced:rule.isAdminEnforced,
      effectiveRules:'NOT_PROVEN_BY_GRAPHQL_REQUIRES_SEPARATE_REST_READ'}
  };
}
function restStatus(error) {
  try { const value=JSON.parse(String(error.stdout)).status;
    if (value === 403 || value === '403') return 403;
    if (value === 404 || value === '404') return 404;
  } catch { /* Preserve unknown failures instead of treating them as permission denial. */ }
  const match=String(error.stderr ?? '').match(/\(HTTP (403|404)\)/);
  return match ? Number(match[1]) : null;
}
export function readUpstreamProtection({repository,base,baseSHA,rest,graphql}) {
  try {
    return {protection:rest(`branches/${encodeURIComponent(base)}/protection`),
      observation:{api:'AUTHENTICATED_REST_CLASSIC_PROTECTION',repository,base,baseSHA}};
  } catch (error) {
    const status=restStatus(error);
    if (status === 404) return {protection:undefined,
      observation:{api:'AUTHENTICATED_REST_CLASSIC_PROTECTION',repository,base,baseSHA,status:404}};
    if (status !== 403) throw error;
    requireExactScope(repository,base,baseSHA);
    const [owner,name]=repository.split('/');
    try {
      const result=projectProtection(graphql({query:protectionQuery,
        variables:{owner,name,ref:'refs/heads/'+base}}),{repository,base,baseSHA});
      result.observation.restStatus=403;
      return result;
    } catch (cause) {
      throw Error('REST protection HTTP403; authenticated GraphQL protection could not establish the exact rule: '+cause.message);
    }
  }
}
