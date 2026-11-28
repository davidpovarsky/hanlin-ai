// Eligibility for the trusted workflow-run consumer. The canonical checker still
// authenticates the raw schema2 artifact and every configured server check.
export const PROOF_CHECK = 'Hanlin upstream schema2 proof';
export const ACTIONS_APP_ID = 15368;
const protectedAcceptanceBases = new Set([
  'codex/upstream-acceptance-base-20261119',
  'codex/upstream-acceptance-base-20261119-v2',
  'codex/upstream-acceptance-base-20261119-v3'
]);
export const isProtectedAcceptanceBase = value => protectedAcceptanceBases.has(value);
const sourceChecks = new Set(['Hanlin upstream acceptance', 'upstream-validation / Hanlin upstream acceptance']);
const sha = value => /^[a-f0-9]{40}$/.test(value ?? '');

export function candidateForRun(run, pulls, repository, allowedBase) {
  if (!isProtectedAcceptanceBase(allowedBase)) throw Error('Unrecognized protected acceptance base');
  if (run.repository?.full_name !== repository || run.head_repository?.full_name !== repository)
    throw Error('Foreign run repository');
  if (run.path !== '.github/workflows/check-runtime-dependency-updates.yml'
      || run.event !== 'workflow_dispatch' || run.status !== 'completed'
      || !sha(run.head_sha)) throw Error('Not a completed canonical dispatch');
  if (!Array.isArray(pulls) || pulls.length >= 100) throw Error('Incomplete pull-request inventory');
  const candidates = pulls.filter(pr => pr.state === 'open' && pr.base?.ref === allowedBase
    && pr.base?.repo?.full_name === repository && pr.head?.repo?.full_name === repository
    && pr.head?.ref === run.head_branch && pr.head?.sha === run.head_sha);
  if (candidates.length > 1) throw Error('Ambiguous current-head candidate');
  const pr = candidates[0];
  if (!pr) return null;
  if (!pr.head.ref.startsWith('codex/renovate/')) throw Error('Not an owned Renovate proposal');
  if (pr.draft || !sha(pr.base.sha)) throw Error('Draft or unbound candidate base');
  return pr;
}

export function requireCandidateProof(report, pr, run) {
  if (run.conclusion !== 'success') throw Error('Original candidate workflow did not pass');
  if (report.pullRequest !== pr.number || report.head !== pr.head.sha || report.head !== run.head_sha
      || report.baseSHA !== pr.base.sha || report.repository !== pr.base.repo.full_name)
    throw Error('Candidate source identity moved or mismatched');
  if (report.validationPassed !== true || report.consumerAccounting?.receiptSchemaVersion !== 2
      || report.consumerAccounting?.status !== 'EXECUTED_PASS')
    throw Error('No authenticated schema2 execution proof');
  const config = report.requiredChecks;
  const bindings = config?.checks;
  if (report.adminEnforced !== true || config?.strict !== true || !Array.isArray(bindings)
      || bindings.filter(row => row.context === PROOF_CHECK && row.app_id === ACTIONS_APP_ID).length !== 1
      || bindings.filter(row => sourceChecks.has(row.context) && row.app_id === ACTIONS_APP_ID).length !== 1
      || report.branchPolicy?.configurationKnown !== true)
    throw Error('Missing admin-enforced strict app-bound source/proof protection');
  return true;
}

export function mayEnableAutoMerge(report, pr, run) {
  requireCandidateProof(report, pr, run);
  // The proof check must already be published and every other server-required
  // check must pass. AUTO_MERGE_DISABLED is the only remaining activation reason.
  return report.branchPolicy?.eligible === true
    && Array.isArray(report.reasons)
    && report.reasons.every(reason => reason === 'AUTO_MERGE_DISABLED')
    && pr.state === 'open' && pr.draft === false;
}
