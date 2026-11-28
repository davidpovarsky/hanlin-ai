// Runs against the exact EXISTING Host lock's TypeScript, materialized only for proof.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFileSync, existsSync, mkdtempSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {analyzeTypeScriptSource} from '../../../AI_HLY/Downstream/AgentSkills/Analysis/Resources/hanlin_typescript_ast.mjs';

const root = new URL('../../../', import.meta.url);
const require = createRequire(new URL('../../../build/ast-ts-proof/package.json', import.meta.url));
const ts = require('typescript');
const fixtures = JSON.parse(readFileSync(new URL('Tests/Fixtures/mixed.json', import.meta.url), 'utf8'));
const scan = (file, source, options = {}, cancel) => analyzeTypeScriptSource(ts,
  {file, utf8: Buffer.from(source), ...options}, cancel);
console.log(JSON.stringify({actual_node: process.versions.node, actual_typescript: ts.version,
  embedded_node_jitless: 'NOT_RUN', compiler_origin: 'existing Host package-lock exact6.0.3/integrity'}));

test('thirteen original TypeScript Compiler API fixtures preserve literal/type/conditional/unknown facts', () => {
  const selected = fixtures.filter(f => f.language === 'typescript');
  assert.equal(selected.length, 13);
  assert.equal(ts.version, '6.0.3');
  for (const fixture of selected) {
    const report = scan(fixture.file, fixture.source);
    const modules = new Set(report.findings.filter(f => f.kind === 'moduleReference').map(f => f.value));
    for (const value of fixture.modules) assert.ok(modules.has(value), JSON.stringify({fixture, report}));
    assert.equal(report.findings.some(f => f.kind === 'unknown'), fixture.unknown, JSON.stringify({fixture, report}));
    assert.ok(!modules.has(fixture.absent));
    assert.equal(report.sourceSHA256, createHash('sha256').update(fixture.source).digest('hex'));
    assert.equal(report.provenance.engineVersion, process.versions.node);
    if (fixture.conditional) assert.ok(report.findings.some(f => f.value === fixture.conditional && f.confidence === 'conditionalSyntax'));
    if (fixture.typeOnly) assert.ok(report.findings.every(f => f.reason === 'typeOnlyImportNotRuntimeRequirement'));
  }
});

test('UTF16 compiler positions convert to original UTF8 bytes across Hebrew emoji and CRLF', () => {
  const source = "const x='שלום🙂'; const y=require('PIL');\r\nimport z from 'other';\r\n";
  const report = scan('עברית.ts', source);
  const first = report.findings.find(f => f.value === 'PIL');
  const position = source.indexOf('require');
  assert.equal(first.source.byteOffset, Buffer.byteLength(source.slice(0, position)));
  assert.equal(first.source.utf8Column, first.source.byteOffset + 1);
  assert.equal(report.findings.find(f => f.value === 'other').source.line, 2);
});

test('untrusted source is never run and original compiler sys IO hooks are unused', () => {
  const directory = mkdtempSync(path.join(tmpdir(), 'hanlin-passive-ast-'));
  const marker = path.join(directory, 'must-not-exist');
  const source = `require('node:fs').writeFileSync(${JSON.stringify(marker)},'executed'); import('unmet_921');`;
  const names = ['readFile', 'writeFile', 'fileExists', 'directoryExists', 'getDirectories', 'readDirectory'];
  const originals = Object.fromEntries(names.map(name => [name, ts.sys[name]]));
  try {
    for (const name of names) ts.sys[name] = () => { throw new Error('Unexpected compiler IO: ' + name); };
    const report = scan('canary.js', source);
    assert.ok(report.findings.some(f => f.value === 'unmet_921'));
    const manifest = scan('package.json', '{"dependencies":{"unmet_921":"^1"}}');
    assert.ok(manifest.findings.some(f => f.kind === 'dependencyDeclaration' && f.value === 'unmet_921@^1'));
    assert.ok(!existsSync(marker));
  } finally {
    for (const name of names) ts.sys[name] = originals[name];
    rmSync(directory, {recursive: true, force: true});
  }
});

test('invalid UTF8 cancellation and hostile budgets stay explicitly unknown', () => {
  const invalid = analyzeTypeScriptSource(ts, {file: 'x.ts', utf8: Buffer.from([0xff])});
  assert.equal(invalid.completion, 'unknown');
  assert.equal(scan('x.ts', 'import x from "y";', {}, () => true).completion, 'unknown');
  assert.equal(scan('x.ts', 'import x from "y";', {maximumBytes: 1}).findings[0].reason, 'sourceBudget');
  for (const options of [{maximumNodes: 3}, {maximumFindings: 3}, {maximumDepth: 1}]) {
    const report = scan('large.ts', 'import x from "y";\n'.repeat(100), options);
    assert.equal(report.completion, 'partial');
    assert.ok(report.findings.some(f => f.kind === 'unknown'));
  }
});

test('original strict JSON/compiler AST preserve declarations and duplicates without executing lifecycle scripts', () => {
  const source = '{"dependencies":{"@scope/pkg":"^2.0","alias":"npm:other@~1"},'
    + '"optionalDependencies":{"native":"file:./native"},"engines":{"node":">=24"},'
    + '"bin":{"cli":"./bin/importable.sh"},"scripts":{"install":"touch DO_NOT_EXECUTE"},"gypfile":true}';
  const report = scan('package.json', source);
  const declarations = report.findings.filter(f => f.kind === 'dependencyDeclaration');
  assert.deepEqual(declarations.map(f => f.value), ['@scope/pkg@^2.0', 'alias@npm:other@~1', 'native@file:./native', 'node@>=24']);
  assert.equal(declarations[2].reason, 'declaredNpmOptionalConstraintNotInstalled');
  assert.ok(report.findings.some(f => f.kind === 'scriptReference' && f.value === './bin/importable.sh'));
  assert.ok(report.findings.some(f => f.reason === 'lifecycleNativeOrPlatformMetadataNotResolved'));
  for (const fact of report.findings) assert.ok(fact.source.byteOffset + fact.source.byteLength <= Buffer.byteLength(source));
  const duplicate = scan('package.json', '{"dependencies":{"x":"1","x":"2"}}');
  assert.equal(duplicate.completion, 'partial');
  assert.ok(duplicate.findings.some(f => f.reason === 'duplicateManifestKey'));
  assert.equal(duplicate.findings.filter(f => f.kind === 'dependencyDeclaration').length, 2);
  for (const source of ['{"dependencies":null}', '{"dependencies":[]}', '{"dependencies":{"x":1}}', '{bad}', '[1]']) {
    const result = scan('package.json', source);
    assert.notEqual(result.completion, 'complete', JSON.stringify(result));
    assert.ok(result.findings.some(f => f.kind === 'unknown'));
  }
});
