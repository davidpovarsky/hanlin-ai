#!/usr/bin/env node
import { execFileSync } from 'node:child_process';
import { writeFile } from 'node:fs/promises';
import { verifiedReceiptAccounting } from './upstream-host-accounting.mjs';
import { selectUpstreamCheckLineage } from './upstream-check-lineage.mjs';
import { evaluateUpdate, dependencyImpact } from './dependency-update-policy.mjs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { readUpstreamProtection } from './upstream-protection-reader.mjs';
import {createUpstreamProtectionAccess, ordinaryUpstreamEnvironment} from './upstream-protection-access.mjs';

const [repository, number, output = 'build/upstream-updates/merge-gate.json', proofRun] = process.argv.slice(2);
if (!/^[\w.-]+\/[\w.-]+$/.test(repository ?? '') || !/^\d+$/.test(number ?? '')) throw new Error('Expected repository PR-number [output].');
const ordinaryEnvironment=ordinaryUpstreamEnvironment();
const api = path => JSON.parse(execFileSync('gh', ['api', `repos/${repository}${path ? '/' + path : ''}`], {env:ordinaryEnvironment,encoding:'utf8', stdio:['ignore','pipe','pipe']}));
const pr = api(`pulls/${number}`);
if (pr.head.repo.full_name !== repository) throw new Error('Fork candidates require manual review; never use this trusted maintenance lane.');
const paths = api(`pulls/${number}/files?per_page=100`);
if (paths.length === 100 || pr.changed_files !== paths.length) throw new Error('Incomplete candidate diff; cannot infer impact.');
const head = pr.head.sha;
const runs = api(`commits/${head}/check-runs?filter=latest&per_page=100`).check_runs;
if (runs.length === 100) throw new Error('Incomplete check inventory.');
const protectionAccess=createUpstreamProtectionAccess({repository,base:pr.base.ref,baseSHA:pr.base.sha});
const {protection,observation} = readUpstreamProtection({
  repository,base:pr.base.ref,baseSHA:pr.base.sha,rest:protectionAccess.rest,graphql:protectionAccess.graphql
});
const branchProtectionObservation={...observation,credentialMode:protectionAccess.credentialMode};
const settings = api('');
let effectiveRules;
try { effectiveRules = protectionAccess.rest(`rules/branches/${encodeURIComponent(pr.base.ref)}`); }
catch { /* Inaccessible/unsupported effective rules stay unknown, never eligible. */ }
const toCheckRows = items => items.map(check => ({ name:check.name, head:check.head_sha, app:check.app?.slug, appId:check.app?.id, checkId:check.id,
  status:check.status, conclusion:check.conclusion }));
let checks=toCheckRows(runs);
let checkLineage=null;
let receipt;
let consumerEvidenceVerified=false;
if (proofRun) {
  if (!/^\d+$/.test(proofRun)) throw new Error('Invalid proof run');
  const run = api(`actions/runs/${proofRun}`);
  if (run.head_sha !== head || run.conclusion !== 'success' || !['.github/workflows/check-runtime-dependency-updates.yml','.github/workflows/validate-app-split.yml'].includes(run.path)) {
    throw new Error('Proof is not a successful current-head run of the canonical updater workflow.');
  }
  const selection=selectUpstreamCheckLineage({rawChecks:runs,repository,head,proofRun:run,prNumber:Number(number),api});
  const {selectedChecks,...lineageSummary}=selection;
  checkLineage=lineageSummary;
  if(!selection.producerMatchesProof)throw Error('Proof run is superseded by a newer authenticated current-head producer');
  checks=toCheckRows(selectedChecks);
  const artifacts = api(`actions/runs/${proofRun}/artifacts`).artifacts
    .filter(item => item.name === `upstream-proof-${proofRun}` && !item.expired);
  if (artifacts.length !== 1 || artifacts[0].size_in_bytes > 16_777_216) throw new Error('Missing/ambiguous/oversized proof artifact');
  const bytes = execFileSync('gh', ['api', `repos/${repository}/actions/artifacts/${artifacts[0].id}/zip`], {env:ordinaryEnvironment,maxBuffer:16_777_216});
  if ('sha256:'+createHash('sha256').update(bytes).digest('hex') !== artifacts[0].digest) throw new Error('Proof artifact digest mismatch');
  const python = process.platform === 'win32' ? 'py' : 'python3';
  const args = [...(process.platform === 'win32' ? ['-3'] : []), fileURLToPath(new URL('./verify-upstream-proof.py', import.meta.url))];
  const proof = JSON.parse(execFileSync(python,args,{env:ordinaryEnvironment,input:bytes,encoding:'utf8',maxBuffer:2_097_152}));
  receipt=proof.receipt;
  consumerEvidenceVerified=verifiedReceiptAccounting(receipt,proof.hostEntries)
    && receipt.hostAccounting.origin.run.runId===proofRun
    && receipt.hostAccounting.origin.run.attempt===String(run.run_attempt);
  if (receipt.head !== head || receipt.base !== pr.base.sha || receipt.status !== 'EXECUTED_PASS'
      || JSON.stringify([...receipt.changedPaths].sort()) !== JSON.stringify(paths.map(row=>row.filename).sort())) {
    throw new Error('Receipt source/base/diff mismatch');
  }
}
const decision = evaluateUpdate({ head, evidenceHead:receipt?.head, updateType:receipt?.updateType, impact:dependencyImpact(paths.map(row=>row.filename)),
  checks, required:[['Hanlin upstream acceptance','upstream-validation / Hanlin upstream acceptance']], sourceIntegrity:receipt?.sourceIntegrity === true,
  licensesReviewed:receipt?.licensesReviewed === true, rollback:!!receipt?.rollback,
  protection, effectiveRules, consumerEvidenceVerified, autoMergeEnabled:settings.allow_auto_merge === true && pr.auto_merge != null });
const report = { ...decision, repository, pullRequest:Number(number), head, baseSHA:pr.base.sha,
  adminEnforced:protection?.enforce_admins?.enabled === true, branchProtectionObservation,
  requiredChecks:protection?.required_status_checks ?? null, effectiveBranchRules:effectiveRules ?? null, actualChecks:checks, rawCheckInventory:toCheckRows(runs), checkLineage,
  consumerAccounting:{status:consumerEvidenceVerified?receipt.hostAccounting.status:'UNKNOWN',
    receiptSchemaVersion:receipt?.schemaVersion??null,origin:consumerEvidenceVerified?receipt.hostAccounting.origin:null,
    legacyNote:receipt?.schemaVersion===1?'Immutable historical receipt needs separate source/log audit; not automatically upgraded to schema2':null},
  evaluatedAt:new Date().toISOString(), scope:'CI-policy snapshot only; no PR review/deployment approval or merge operation',
  mergePerformed:false, evidence:'Authenticated GitHub API snapshot; no merge endpoint is called.' };
await writeFile(output, JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report));
process.exitCode = report.mergeEligible ? 0 : 1;
