import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as esbuild from 'esbuild';
import ts from 'typescript';

const root = path.dirname(fileURLToPath(import.meta.url));
const pin = JSON.parse(await readFile(path.join(root, 'policy-pin.json'), 'utf8'));
const sourceRoot = path.join(root, '.cache', pin.revision);
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const sourceContracts = new Map(pin.testSources.map(s => [s.path, s]));
const ledger = [];
const all = '*';
const groups = [
  { file: 'src/shared/frontmatter.test.ts', suite: 'shared/frontmatter', cases: all },
  { file: 'src/skills/loading/frontmatter.test.ts', suite: 'resolveSkillManifestMetadata install validation',
    exclude: ['parses Link-style YAML metadata with node install hints'],
    reason: 'The original Markdown/YAML parser is deliberately excluded. Hanlin Yams owns native frontmatter parsing.' },
  { file: 'src/shared/config-eval.test.ts', suite: 'config-eval helpers',
    cases: ['normalizes truthy values across primitive types', 'resolves nested config paths and missing branches safely',
      'blocks prototype keys while resolving config paths', 'uses defaults only when config paths are unresolved',
      'does not use inherited defaults for blocked config paths', 'returns the active runtime platform'] },
  { file: 'src/shared/config-eval.test.ts', suite: 'runtime requirements through eligibility', cases: all },
  { file: 'src/shared/config-eval.test.ts', suite: 'evaluateRuntimeEligibility', cases: all },
  { file: 'src/skills/loading/skills.test.ts', suite: 'shouldIncludeSkill', cases: all,
    helpers: ['withClearedEnv', 'makeSkillEntry', 'rawSkillApiKeyRefConfig'] }
];
const names = [
  'applyOpenClawManifestInstallCommonFields','parseFrontmatterBool','parseOpenClawManifestInstallBase',
  'resolveOpenClawManifestBlock','resolveOpenClawManifestInstall','resolveOpenClawManifestOs','resolveOpenClawManifestRequires',
  'resolveSkillManifestMetadata','resolveSkillInvocationPolicy','evaluateRuntimeEligibility',
  'isConfigPathTruthyWithDefaults','shouldIncludeSkill','setActiveDegradedSecretOwners'
];
const parts = [
  'import { describe, expect, it, test, mockProcessPlatform, expectDefined, results } from "../Tests/policy-upstream-shim.mjs";',
  'import {' + names.join(',') + '} from "./policy.mjs";'
];
const usedHelpers = new Set();
for (const group of groups) {
  const bytes = await readFile(path.join(sourceRoot, group.file));
  const contract = sourceContracts.get(group.file);
  if (!contract || digest(bytes) !== contract.sha256) throw Error('Original test source drift: ' + group.file);
  const text = bytes.toString('utf8');
  const sf = ts.createSourceFile(group.file, text, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
  for (const helper of group.helpers || []) {
    if (usedHelpers.has(helper)) continue;
    const statement = sf.statements.find(s => (ts.isFunctionDeclaration(s) && s.name?.text === helper) ||
      (ts.isVariableStatement(s) && s.declarationList.declarations.some(d => ts.isIdentifier(d.name) && d.name.text === helper)));
    if (!statement) throw Error('Original test helper missing: ' + helper);
    parts.push(statement.getText(sf)); usedHelpers.add(helper);
    ledger.push({ file: group.file, helper, start: statement.getStart(sf), end: statement.end, sha256: digest(statement.getText(sf)) });
  }
  const suite = sf.statements.find(s => ts.isExpressionStatement(s) && ts.isCallExpression(s.expression) &&
    s.expression.expression.getText(sf) === 'describe' && s.expression.arguments[0]?.text === group.suite);
  if (!suite) throw Error('Original test suite missing: ' + group.suite);
  const callback = suite.expression.arguments[1];
  if (!callback || !ts.isBlock(callback.body)) throw Error('Original test suite shape changed');
  const retained = [];
  let count = 0;
  for (const statement of callback.body.statements) {
    if (!ts.isExpressionStatement(statement) || !ts.isCallExpression(statement.expression)) {
      retained.push(statement.getText(sf)); continue;
    }
    const call = statement.expression;
    const label = call.arguments[0]?.text;
    if (typeof label !== 'string') throw Error('Unreviewed original test statement');
    const selected = (group.cases === all || group.cases?.includes(label) || group.exclude) && !group.exclude?.includes(label);
    if (!selected) continue;
    retained.push(statement.getText(sf)); count++;
    ledger.push({ file: group.file, suite: group.suite, case: label, start: statement.getStart(sf), end: statement.end, sha256: digest(statement.getText(sf)) });
  }
  if (!count || (Array.isArray(group.cases) && count !== group.cases.length)) throw Error('Original case selection drift');
  parts.push('describe(' + JSON.stringify(group.suite) + ', () => {\n' + retained.join('\n') + '\n});');
}
parts.push('export { results };');
const compiled = await esbuild.transform(parts.join('\n'), {
  loader: 'ts', target: 'node24.5', format: 'esm', tsconfigRaw: { compilerOptions: { alwaysStrict: true } }
});
await writeFile(path.join(root, 'generated/upstream-policy-tests.mjs'), compiled.code);
await writeFile(path.join(root, 'generated/policy-original-test-selection.json'), JSON.stringify({
  revision: pin.revision, groups, declarations: ledger, transformedArtifactSHA256: digest(compiled.code),
  expectedTestInvocations: 28,
  boundary: 'Unchanged original test statements/helpers. Framework, platform mock and secret-registry cleanup are explicit fixture adapters. Filesystem discovery, workspace loading and the upstream YAML parser are outside this subset.'
}, null, 2) + '\n');
console.log(JSON.stringify({ status: 'ORIGINAL_POLICY_TESTS_SELECTED', statements: ledger.filter(x=>x.case).length, expectedInvocations: 28 }));

const nativeContract = await esbuild.build({
  absWorkingDir: root,
  stdin: { contents: "import './Tests/policy.test.mjs';\nimport './Tests/policy-probe.test.mjs';", resolveDir: root, loader: 'js' },
  bundle: true, write: false, platform: 'node', format: 'esm', target: 'node24.5',
  tsconfigRaw: { compilerOptions: { alwaysStrict: true } },
  plugins: [{ name: 'owned-native-policy-cases', setup(build) {
    build.onResolve({ filter: /^node:test$/ }, () => ({ path: 'case-registry', namespace: 'hanlin-policy-test' }));
    build.onLoad({ filter: /.*/, namespace: 'hanlin-policy-test' }, () => ({
      contents: 'export const test = (name, body) => globalThis.__hanlinPolicyCases.push({name,body});', loader: 'js'
    }));
    build.onResolve({ filter: /^\.\.\/generated\/(?:policy|upstream-policy-tests)\.mjs$/ },
      args => ({ path: args.path, external: true }));
    build.onResolve({ filter: /^\.\.\/policy-probe\.mjs$/ },
      args => ({ path: args.path, external: true }));
  }}]
});
await writeFile(path.join(root, 'generated/native-policy-contract.mjs'), nativeContract.outputFiles[0].contents);
const provenancePath = path.join(root, 'generated/policy-provenance.json');
const provenance = JSON.parse(await readFile(provenancePath));
provenance.nativeResources = {};
for (const file of ['./generated/policy.mjs', './policy-probe.mjs', './generated/native-policy-contract.mjs',
                    './generated/upstream-policy-tests.mjs', './generated/policy-original-test-selection.json',
                    './Tests/policy-upstream-shim.mjs', './native-policy-probe.mjs']) {
  provenance.nativeResources[file] = digest(await readFile(path.join(root, file)));
}
await writeFile(provenancePath, JSON.stringify(provenance, null, 2) + '\n');
