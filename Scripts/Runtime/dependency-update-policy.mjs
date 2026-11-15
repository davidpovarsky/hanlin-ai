// Read-only CI eligibility, never a merge operation or a review/deployment approval.
const validContext = value => typeof value === 'string' && value.trim().length > 0;
const positiveId = value => Number.isSafeInteger(value) && value > 0;
const sourceGroups = required => required.map(value => Array.isArray(value) ? value : [value]);
const passed = (check, head) => check.head === head && check.status === 'completed'
  && check.conclusion === 'success' && validContext(check.app) && positiveId(check.appId);

export function evaluateBranchRequirements({ head, protection, effectiveRules, checks = [], required = [] }) {
  const reasons = [];
  const gates = new Map();
  let configurationKnown = true;
  if (!protection) {
    configurationKnown = false;
    reasons.push('BRANCH_NOT_PROTECTED');
  } else {
    const config = protection.required_status_checks;
    if (!config || config.strict !== true || (!Array.isArray(config.contexts) && !Array.isArray(config.checks))) {
      configurationKnown = false;
      reasons.push('UNKNOWN_OR_NON_STRICT_REQUIRED_CHECK_CONFIGURATION');
    } else {
      const contexts = config.contexts ?? [];
      const bindings = config.checks ?? [];
      const seenContexts = new Set(), seenBindings = new Set();
      const invalid = () => { configurationKnown = false; };
      if (!Array.isArray(contexts) || !Array.isArray(bindings)) invalid();
      else {
        for (const context of contexts) {
          if (!validContext(context) || seenContexts.has(context)) { invalid(); continue; }
          seenContexts.add(context);
          gates.set(context, { context, appId: null });
        }
        for (const binding of bindings) {
          if (!binding || !validContext(binding.context) || seenBindings.has(binding.context)
              || (binding.app_id != null && binding.app_id !== -1 && !positiveId(binding.app_id))) {
            invalid(); continue;
          }
          seenBindings.add(binding.context);
          // contexts + checks are the REST legacy mirror and app-bound declaration.
          gates.set(binding.context, { context: binding.context, appId: positiveId(binding.app_id) ? binding.app_id : null });
        }
      }
      if (!configurationKnown) reasons.push('AMBIGUOUS_REQUIRED_CHECK_CONFIGURATION');
    }
  }
  // The classic branch-protection endpoint alone cannot prove no additional rules.
  // Rulesets remain manual until their complete CI requirements are supported.
  if (!Array.isArray(effectiveRules)) { configurationKnown = false; reasons.push('EFFECTIVE_BRANCH_RULES_UNKNOWN'); }
  else if (effectiveRules.length) { configurationKnown = false; reasons.push('ADDITIONAL_BRANCH_RULES_REQUIRE_REVIEW'); }
  if (!gates.size) reasons.push('NO_SERVER_REQUIRED_GATES');
  const groups = sourceGroups(required);
  for (const names of groups) {
    if (!names.length || !names.every(validContext) || !names.some(name => gates.has(name))) {
      reasons.push(`UPSTREAM_GATE_NOT_REQUIRED:${names.join('|')}`);
    }
  }
  const results = [...gates.values()].map(gate => {
    // Preserve exact server context: no prefix removal, aliasing or normalization.
    const candidates = checks.filter(check => check.name === gate.context
      && (gate.appId === null || check.appId === gate.appId));
    const upstream = groups.some(names => names.includes(gate.context));
    const success = candidates.length === 1 && passed(candidates[0], head)
      && (!upstream || candidates[0].app === 'github-actions');
    if (!success) reasons.push(`SERVER_REQUIRED_GATE_NOT_PASS:${gate.context}`);
    return { ...gate, matchedCheckIds: candidates.map(check => check.checkId ?? null),
      state: candidates.length !== 1 ? 'MISSING_OR_AMBIGUOUS' : success ? 'PASS' : 'NOT_PASS' };
  });
  return { configurationKnown, eligible: reasons.length === 0, requiredGates: results, reasons };
}

export function evaluateUpdate({ head, evidenceHead, updateType, impact, checks = [], required = [],
  sourceIntegrity, licensesReviewed, rollback, protection, effectiveRules, consumerEvidenceVerified = false, autoMergeEnabled = false }) {
  const reasons = [];
  if (!/^[a-f0-9]{40}$/.test(head ?? '') || evidenceHead !== head) reasons.push('EVIDENCE_HEAD_MISMATCH');
  if (!['patch', 'minor'].includes(updateType)) reasons.push('MANUAL_VERSION_REVIEW');
  if (!['tooling', 'runtime-host'].includes(impact)) reasons.push('NATIVE_OR_UNKNOWN_IMPACT_REQUIRES_REVIEW');
  if (!sourceIntegrity) reasons.push('MISSING_SOURCE_INTEGRITY');
  if (!licensesReviewed) reasons.push('MISSING_LICENSE_REVIEW');
  if (!rollback) reasons.push('MISSING_ROLLBACK');
  if (!consumerEvidenceVerified) reasons.push('UNKNOWN_CONSUMER_EXECUTION_ACCOUNTING');
  if (!required.length) reasons.push('NO_REQUIRED_GATES');
  for (const names of sourceGroups(required)) {
    const candidates = checks.filter(check => names.includes(check.name));
    if (!names.length || !names.every(validContext) || candidates.length !== 1
        || !passed(candidates[0], head) || candidates[0].app !== 'github-actions') {
      reasons.push(`REQUIRED_GATE_NOT_PASS:${names.join('|')}`);
    }
  }
  // This is upstream validation only. Server enforcement is a distinct decision.
  const validationPassed = reasons.length === 0;
  const branchPolicy = evaluateBranchRequirements({ head, protection, effectiveRules, checks, required });
  reasons.push(...branchPolicy.reasons);
  if (!autoMergeEnabled) reasons.push('AUTO_MERGE_DISABLED');
  return { schemaVersion: 1, validationPassed, mergeEligible: reasons.length === 0, reasons, branchPolicy };
}

export function dependencyImpact(paths) {
  if (!paths.length) return 'unknown';
  const tooling = path => /^Scripts\/Runtime\/DependencyUpdates\/(?:package\.json|package-lock\.json)$/.test(path);
  if (paths.every(tooling)) return 'tooling';
  const host = new Set(['RuntimeDependencies.lock.json', 'AI_HLY/Downstream/RuntimeCore/Node/Host/package.json',
    'AI_HLY/Downstream/RuntimeCore/Node/Host/package-lock.json', 'AI_HLY/Downstream/RuntimeCore/Resources/RuntimeManifest.json']);
  if (paths.every(path => host.has(path))) return 'runtime-host';
  return 'native-or-unknown';
}
