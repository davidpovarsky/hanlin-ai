import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(root, '../../..');
const target = path.join(repo, 'AI_HLY/Downstream/AgentSkills/Analysis/Resources');
const resources = {
  'generated/policy.mjs': 'hanlin_openclaw_policy.mjs',
  'policy-probe.mjs': 'hanlin_openclaw_policy_probe.mjs',
  'native-policy-probe.mjs': 'hanlin_openclaw_policy_native_probe.mjs',
  'generated/native-policy-contract.mjs': 'hanlin_openclaw_policy_native_contract.mjs',
  'generated/policy-provenance.json': 'hanlin_openclaw_policy_provenance.json',
  'generated/upstream-policy-tests.mjs': 'hanlin_openclaw_policy_upstream_tests.mjs',
  'generated/policy-original-test-selection.json': 'hanlin_openclaw_policy_test_selection.json',
  'Tests/policy-upstream-shim.mjs': 'hanlin_openclaw_policy_upstream_shim.mjs',
  'generated/LICENSE.json5.txt': 'LICENSE.OpenClaw.JSON5.txt',
  'generated/LICENSE.semver.txt': 'LICENSE.OpenClaw.Semver.txt'
};
const hashes = {};
for (const [source, name] of Object.entries(resources)) {
  const bytes = await readFile(path.join(root, source));
  await writeFile(path.join(target, name), bytes);
  hashes[name] = createHash('sha256').update(bytes).digest('hex');
}
const swift = await readFile(path.join(repo, 'AI_HLY/Downstream/RuntimeCore/Core/Skills/SkillRuntimeOpenClaw.swift'), 'utf8');
const projection = await readFile(path.join(repo, 'AI_HLY/Downstream/RuntimeCore/Core/Skills/SkillOpenClawProjection.swift'), 'utf8');
if (!swift.includes(hashes['hanlin_openclaw_policy.mjs']) || !projection.includes(hashes['hanlin_openclaw_policy_probe.mjs'])) throw Error('Native resource identity has not been reviewed/updated');
await writeFile(path.join(root, 'generated/policy-resource-manifest.json'), JSON.stringify({ resources: hashes }, null, 2) + '\n');
console.log(JSON.stringify({ status: 'ORIGINAL_POLICY_RESOURCES_STAGED', resources: Object.keys(hashes).length }));
