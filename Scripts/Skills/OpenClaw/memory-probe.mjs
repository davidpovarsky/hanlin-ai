// Development probe over the ORIGINAL predicate. No Runtime-05 interface, readiness policy,
// YAML parsing, PATH scan, environment-value transfer, installation or Skill execution.
export function probeOriginalRequirements(original, input) {
  if (!['supported', 'absent', 'unsupported'].includes(input.metadataStatus)) throw Error('Metadata status is required');
  if (input.metadataStatus === 'unsupported') {
    return { scope: 'requirements-only', rawUpstreamResult: null, reason: 'unsupported-metadata', executionVerified: false };
  }
  if (input.metadataStatus === 'supported' && (!input.metadata || typeof input.metadata !== 'object' || Array.isArray(input.metadata))) {
    throw Error('Supported metadata needs an explicit projected object');
  }
  const snapshot = input.snapshot;
  if (!snapshot || typeof snapshot.scope !== 'string' || typeof snapshot.platform !== 'string') throw Error('An explicit single-scope fact snapshot is required');
  const queries = [], unobserved = [];
  const lookup = (kind, key) => {
    const map = snapshot[kind];
    const value = map && Object.hasOwn(map, key) ? map[key] : undefined;
    const known = typeof value === 'boolean';
    queries.push({ scope: snapshot.scope, kind, key, known, satisfied: known ? value : null });
    if (!known) unobserved.push({ kind, key });
    return known ? value : false;
  };
  const rawUpstreamResult = original.evaluateRequirementsFromMetadataWithRemote({
    metadata: input.metadataStatus === 'supported' ? input.metadata : undefined,
    always: input.always === true,
    localPlatform: snapshot.platform,
    hasLocalBin: key => lookup('bins', key),
    isEnvSatisfied: key => lookup('env', key),
    isConfigSatisfied: key => lookup('config', key)
  });
  return {
    scope: 'requirements-only', rawUpstreamResult, queries, unobserved,
    declaredMetadata: input.metadataStatus === 'supported', executionVerified: false,
    outOfScope: ['selection/disabled', 'install hints', 'tool visibility', 'readiness/ExecutionPlan']
  };
}
