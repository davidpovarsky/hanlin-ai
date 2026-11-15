#!/usr/bin/env node
import { execFileSync } from 'node:child_process';
import { writeFile } from 'node:fs/promises';
import { evaluateUpdate, dependencyImpact } from './dependency-update-policy.mjs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const [repository, number, output = 'build/upstream-updates/merge-gate.json', proofRun] = process.argv.slice(2);
if (!/^[\w.-]+\/[\w.-]+$/.test(repository ?? '') || !/^\d+$/.test(number ?? '')) throw new Error('Expected repository PR-number [output].');
const api = path => JSON.parse(execFileSync('gh', ['api', `repos/${repository}${path ? '/' + path : ''}`], {encoding:'utf8', stdio:['ignore','pipe','pipe']}));
const pr = api(`pulls/${number}`);
if (pr.head.repo.full_name !== repository) throw new Error('Fork candidates require manual review; never use this trusted maintenance lane.');
const paths = api(`pulls/${number}/files?per_page=100`);
if (paths.length === 100 || pr.changed_files !== paths.length) throw new Error('Incomplete candidate diff; cannot infer impact.');
const head = pr.head.sha;
const runs = api(`commits/${head}/check-runs?filter=latest&per_page=100`).check_runs;
if (runs.length === 100) throw new Error('Incomplete check inventory.');
let protection;
try { protection = api(`branches/${encodeURIComponent(pr.base.ref)}/protection`); }
catch (error) { if (!String(error.stderr).includes('404')) throw error; }
const settings = api('');
let effectiveRules;
try { effectiveRules = api(`rules/branches/${encodeURIComponent(pr.base.ref)}`); }
catch { /* Inaccessible/unsupported effective rules stay unknown, never eligible. */ }
const checks = runs.map(check => ({ name:check.name, head:check.head_sha, app:check.app?.slug, appId:check.app?.id, checkId:check.id,
  status:check.status, conclusion:check.conclusion }));
let receipt;
if (proofRun) {
  if (!/^\d+$/.test(proofRun)) throw new Error('Invalid proof run');
  const run = api(`actions/runs/${proofRun}`);
  if (run.head_sha !== head || run.conclusion !== 'success' || !['.github/workflows/check-runtime-dependency-updates.yml','.github/workflows/validate-app-split.yml'].includes(run.path)) {
    throw new Error('Proof is not a successful current-head run of the canonical updater workflow.');
  }
  const artifacts = api(`actions/runs/${proofRun}/artifacts`).artifacts
    .filter(item => item.name === `upstream-proof-${proofRun}` && !item.expired);
  if (artifacts.length !== 1 || artifacts[0].size_in_bytes > 16_777_216) throw new Error('Missing/ambiguous/oversized proof artifact');
  const bytes = execFileSync('gh', ['api', `repos/${repository}/actions/artifacts/${artifacts[0].id}/zip`], {maxBuffer:16_777_216});
  if ('sha256:'+createHash('sha256').update(bytes).digest('hex') !== artifacts[0].digest) throw new Error('Proof artifact digest mismatch');
  const python = process.platform === 'win32' ? 'py' : 'python3';
  const args = [...(process.platform === 'win32' ? ['-3'] : []), fileURLToPath(new URL('./verify-upstream-proof.py', import.meta.url))];
  receipt = JSON.parse(execFileSync(python,args,{input:bytes,encoding:'utf8',maxBuffer:1_048_576}));
  if (receipt.head !== head || receipt.base !== pr.base.sha || receipt.status !== 'EXECUTED_PASS'
      || JSON.stringify([...receipt.changedPaths].sort()) !== JSON.stringify(paths.map(row=>row.filename).sort())) {
    throw new Error('Receipt source/base/diff mismatch');
  }
}
const decision = evaluateUpdate({ head, evidenceHead:receipt?.head, updateType:receipt?.updateType, impact:dependencyImpact(paths.map(row=>row.filename)),
  checks, required:[['Hanlin upstream acceptance','upstream-validation / Hanlin upstream acceptance']], sourceIntegrity:receipt?.sourceIntegrity === true,
  licensesReviewed:receipt?.licensesReviewed === true, rollback:!!receipt?.rollback,
  protection, effectiveRules, autoMergeEnabled:settings.allow_auto_merge === true && pr.auto_merge != null });
const report = { ...decision, repository, pullRequest:Number(number), head, baseSHA:pr.base.sha,
  requiredChecks:protection?.required_status_checks ?? null, effectiveBranchRules:effectiveRules ?? null, actualChecks:checks,
  evaluatedAt:new Date().toISOString(), scope:'CI-policy snapshot only; no PR review/deployment approval or merge operation',
  mergePerformed:false, evidence:'Authenticated GitHub API snapshot; no merge endpoint is called.' };
await writeFile(output, JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report));
process.exitCode = report.mergeEligible ? 0 : 1;
