// This reports eligibility; it never merges or publishes anything.
export function evaluateUpdate({ head, evidenceHead, updateType, impact, checks = [], required = [],
  sourceIntegrity, licensesReviewed, rollback, protectedBranch, autoMergeEnabled = false }) {
  const reasons = [];
  if (!/^[a-f0-9]{40}$/.test(head ?? '') || evidenceHead !== head) reasons.push('EVIDENCE_HEAD_MISMATCH');
  if (!['patch', 'minor'].includes(updateType)) reasons.push('MANUAL_VERSION_REVIEW');
  if (!['tooling', 'runtime-host'].includes(impact)) reasons.push('NATIVE_OR_UNKNOWN_IMPACT_REQUIRES_REVIEW');
  if (!sourceIntegrity) reasons.push('MISSING_SOURCE_INTEGRITY');
  if (!licensesReviewed) reasons.push('MISSING_LICENSE_REVIEW');
  if (!rollback) reasons.push('MISSING_ROLLBACK');
  if (!required.length) reasons.push('NO_REQUIRED_GATES');
  for (const name of required) {
    const check = checks.find(item => item.name === name);
    if (!check || check.head !== head || check.status !== 'completed' || check.conclusion !== 'success' || check.app !== 'github-actions') {
      reasons.push(`REQUIRED_GATE_NOT_PASS:${name}`);
    }
  }
  const validationPassed = reasons.length === 0;
  if (!protectedBranch) reasons.push('BRANCH_NOT_PROTECTED');
  if (!autoMergeEnabled) reasons.push('AUTO_MERGE_DISABLED');
  return { schemaVersion: 1, validationPassed, mergeEligible: reasons.length === 0, reasons };
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
