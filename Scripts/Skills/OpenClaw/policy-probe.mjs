// Thin input/fact adapter. OpenClaw's unchanged functions own every policy decision.
// No imported Skill code, installer, filesystem PATH probe, remote facts or secret values.
const own = (value, key) => Object.prototype.hasOwnProperty.call(value, key);
const record = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const list = value => value == null || typeof value === 'string' ||
  (Array.isArray(value) && value.every(item => typeof item === 'string'));

function supportedBlock(block) {
  if (!record(block)) return false;
  if (own(block, 'always') && typeof block.always !== 'boolean') return false;
  if (!list(block.os)) return false;
  if (block.requires != null) {
    if (!record(block.requires)) return false;
    for (const [key, value] of Object.entries(block.requires)) {
      if (!['bins', 'anyBins', 'env', 'config'].includes(key) || !list(value)) return false;
    }
  }
  return true;
}

function setFact(config, path, value) {
  const parts = path.split('.').filter(Boolean);
  if (!parts.length || parts.some(key => ['__proto__', 'prototype', 'constructor'].includes(key))) return false;
  let cursor = config;
  for (const key of parts.slice(0, -1)) {
    if (!own(cursor, key) || !record(cursor[key])) cursor[key] = Object.create(null);
    cursor = cursor[key];
  }
  cursor[parts.at(-1)] = value;
  return true;
}

export function probeOriginalPolicy(original, input) {
  if (!record(input) || input.scope !== 'native' || typeof input.name !== 'string' ||
      !record(input.frontmatter) || Object.values(input.frontmatter).some(value => typeof value !== 'string') ||
      !['absent', 'present', 'unsupported'].includes(input.metadataPresence)) {
    throw Error('Unsupported original policy input boundary');
  }
  const invocation = original.resolveSkillInvocationPolicy(input.frontmatter);
  const block = original.resolveOpenClawManifestBlock({ frontmatter: input.frontmatter });
  const metadataStatus = input.metadataPresence === 'unsupported' ? 'unsupported' :
    input.metadataPresence === 'absent' ? 'absent' : supportedBlock(block) ? 'supported' : 'unsupported';
  if (metadataStatus === 'unsupported') {
    return { metadataStatus, declaredMetadata: false, rawUpstreamResult: null, known: false,
      invocation, installHints: [], unobserved: ['unsupported-metadata'], factScope: 'native', executionVerified: false };
  }
  const metadata = original.resolveSkillManifestMetadata(input.frontmatter);
  const entry = { skill: { name: input.name, source: input.source ?? 'hanlin-native' }, frontmatter: input.frontmatter, metadata };
  const skillKey = original.resolveSkillKey(entry);
  const configSeed = input.config ?? {};
  if (!record(configSeed) || (input.bins && !record(input.bins)) || (input.configFacts && !record(input.configFacts))) throw Error('Invalid observed fact snapshot');
  if (Object.values(input.bins ?? {}).some(value => typeof value !== 'boolean') ||
      Object.values(input.configFacts ?? {}).some(value => typeof value !== 'boolean')) throw Error('Only observed boolean facts are accepted');
  const selected = original.isSkillEntrySelected(entry, input.skillFilter, input.skillOverrides);
  const unobserved = new Set();
  const evaluate = unknown => {
    const config = JSON.parse(JSON.stringify(configSeed));
    for (const name of metadata?.requires?.config ?? []) {
      const observed = own(input.configFacts ?? {}, name);
      if (!observed) unobserved.add('config:' + name);
      setFact(config, name, observed ? input.configFacts[name] : unknown);
    }
    if (typeof input.enabled === 'boolean') {
      config.skills ??= {};
      config.skills.entries = Object.assign(Object.create(null), config.skills.entries ?? {});
      if (!own(config.skills.entries, skillKey)) config.skills.entries[skillKey] = {};
      config.skills.entries[skillKey].enabled = input.enabled;
    }
    return original.shouldIncludeSkill({
      entry, config, bundledAllowlist: original.resolveBundledAllowlist(config),
      platform: input.platform ?? process.platform,
      hasBin(name) {
        if (own(input.bins ?? {}, name)) return input.bins[name];
        unobserved.add('bins:' + name); return unknown;
      }
    });
  };
  // The original predicate is monotone in these boolean facts. Evaluating the two
  // bounds lets the ORIGINAL short-circuit/always/disabled/any-bin policy determine
  // whether missing observations matter; no replacement eligibility algorithm.
  original.setActiveDegradedSecretOwners(input.degradedOwners ?? []);
  let included, optimistic;
  try { included = evaluate(false); optimistic = evaluate(true); }
  finally { original.setActiveDegradedSecretOwners([]); }
  const known = !selected || included === optimistic;
  return {
    metadataStatus, declaredMetadata: metadataStatus === 'supported', known, invocation,
    rawUpstreamResult: { selected, included, optimisticIncluded: optimistic, eligible: selected && included },
    installHints: metadata?.install ?? [], installPreferences: original.resolveSkillsInstallPreferences(configSeed),
    unobserved: [...unobserved].sort(), factScope: 'native', platform: input.platform ?? process.platform,
    executionVerified: false
  };
}
