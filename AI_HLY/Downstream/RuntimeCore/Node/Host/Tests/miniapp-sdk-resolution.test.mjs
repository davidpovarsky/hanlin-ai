import test from 'node:test';
import assert from 'node:assert/strict';
import {promises as fs} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import {runMiniAppOperation} from '../miniapp-authoring.mjs';

const compilerLocation = process.env.HANLIN_AUTHORING_TYPESCRIPT ?? 'typescript';
const ts = (await import(compilerLocation)).default;
const compilerPackage = path.dirname(createRequire(import.meta.url).resolve(
  compilerLocation.startsWith('file:') ? new URL('../package.json', compilerLocation).pathname : 'typescript/package.json'));
const writeJSON = async (file, value) => fs.writeFile(file, JSON.stringify(value, null, 2));
async function packageAt(root, name, version, declaration, body = '', extra = {}) {
  const directory = path.join(root, 'node_modules', name);
  await fs.mkdir(directory, {recursive: true});
  await writeJSON(path.join(directory, 'package.json'), {name, version, type: 'module', types: './index.d.ts', main: './index.js', ...extra});
  await fs.writeFile(path.join(directory, 'index.d.ts'), declaration);
  await fs.writeFile(path.join(directory, 'index.js'), body);
  return directory;
}
async function fixture(t) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-sdk-resolution-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const sdk = path.join(root, 'sdk');
  const tooling = path.join(sdk, 'original');
  const project = path.join(root, 'workspace', 'project');
  await fs.mkdir(path.join(tooling, 'node_modules'), {recursive: true});
  await fs.mkdir(project, {recursive: true});
  await fs.symlink(compilerPackage, path.join(tooling, 'node_modules', 'typescript'), 'dir');
  await writeJSON(path.join(tooling, 'package.json'), {private: true});
  await writeJSON(path.join(sdk, 'miniapp-sdk.json'), {schemaVersion: 1, engines: {nativescript: {
    toolingRoot: 'original', typescriptPath: 'original/node_modules/typescript/lib/typescript.js',
    tsconfigPath: 'original/tsconfig.json', packageVersions: {typescript: ts.version, 'fixture-canonical': '1.0.0'}
  }}});
  await writeJSON(path.join(tooling, 'tsconfig.json'), {compilerOptions: {
    strict: true, skipLibCheck: false, target: 'ES2022', module: 'ESNext',
    moduleResolution: 'Bundler', types: ['fixture-canonical']
  }});
  const canonical = await packageAt(tooling, 'fixture-canonical', '1.0.0',
    'export {leaf} from "fixture-leaf"; export declare const tag: "sdk";\n',
    'export {leaf} from "fixture-leaf"; export const tag = "sdk";\n',
    {dependencies: {'fixture-leaf': '2.0.0'}, exports: {'.': {types: './index.d.ts', import: './index.js'}, './config': './tsconfig.json'}});
  await writeJSON(path.join(canonical, 'tsconfig.json'), {compilerOptions: {strict: true}});
  await packageAt(canonical, 'fixture-leaf', '2.0.0', 'export declare const leaf: "nested";\n', 'export const leaf = "nested";\n');
  await packageAt(tooling, 'fixture-leaf', '1.0.0', 'export declare const leaf: "root";\n', 'export const leaf = "root";\n');
  const ancestor = await packageAt(root, 'fixture-canonical', '0.0.0',
    'export declare const tag: "ancestor"; export declare const leaf: "ancestor";\n',
    'export const tag = "ancestor"; export const leaf = "ancestor";\n');
  await fs.writeFile(path.join(ancestor, 'private.d.ts'), 'export declare const privateValue: number;\n');
  await writeJSON(path.join(ancestor, 'missing.json'), {compilerOptions: {strict: true}});
  await writeJSON(path.join(project, 'package.json'), {name: 'resolution-project', version: '1.0.0', type: 'module'});
  await writeJSON(path.join(project, 'script.json'), {name: 'Resolution proof', version: '1.0.0', hanlinRuntime: 'hanlin-nativescript'});
  await writeJSON(path.join(project, 'hanlin.authoring.json'), {schemaVersion: 1, engine: 'nativescript', entry: 'index.ts'});
  const config = {compilerOptions: {strict: true, skipLibCheck: false}, include: ['*.ts', 'src/*.ts']};
  await writeJSON(path.join(project, 'tsconfig.json'), config);
  const entry = path.join(project, 'index.ts');
  await fs.writeFile(entry, 'import {tag, leaf} from "fixture-canonical";\nconst original: "sdk" = tag; const nested: "nested" = leaf;\n');
  const run = operation => runMiniAppOperation({operation, engine: 'nativescript', projectRoot: project}, {sdkRoot: sdk, compiler: ts});
  return {root, sdk, tooling, project, canonical, ancestor, entry, config, run};
}

test('canonical module and type references use the supplied SDK while retaining its nested dependency', async t => {
  const f = await fixture(t);
  const report = await f.run('validate');
  assert.equal(report.succeeded, true, JSON.stringify(report.diagnostics));
  assert.deepEqual(report.diagnostics, []);
  assert.equal(report.typecheck.strict, true);
  assert.equal(report.typecheck.skipLibCheck, false);
});

test('NativeScript emission and copied bodies agree with canonical types and preserve project aliases and extra dependencies', async t => {
  const f = await fixture(t);
  await fs.mkdir(path.join(f.project, 'src'));
  await fs.writeFile(path.join(f.project, 'src/value.ts'), 'export const value = "alias";\n');
  await fs.writeFile(path.join(f.project, 'local-canonical.ts'), 'export const tag = "alias-shadow"; export const leaf = "alias-shadow";\n');
  f.config.compilerOptions.paths = {'fixture-canonical': ['./local-canonical.ts'], '@project/*': ['./src/*']};
  await writeJSON(path.join(f.project, 'tsconfig.json'), f.config);
  const local = await packageAt(f.project, 'fixture-canonical', '0.1.0',
    'export declare const tag: "local"; export declare const leaf: "local";\n',
    'export const tag = "local"; export const leaf = "local";\n');
  const extra = await packageAt(f.project, 'project-extra', '1.0.0',
    'export declare const extra: "project";\n', 'export {leaf as extra} from "fixture-leaf";\n',
    {dependencies: {'fixture-leaf': '3.0.0'}});
  await packageAt(extra, 'fixture-leaf', '3.0.0', 'export declare const leaf: "project";\n', 'export const leaf = "project";\n');
  await writeJSON(path.join(f.project, 'package.json'), {name: 'resolution-project', version: '1.0.0', type: 'module',
    dependencies: {'fixture-canonical': '0.1.0', 'project-extra': '1.0.0'}});
  await fs.writeFile(f.entry, 'import {tag, leaf} from "fixture-canonical";\nimport {extra} from "project-extra";\nimport {value} from "@project/value";\nexport const result = [tag, leaf, extra, value].join(":");\n');
  const report = await f.run('build');
  assert.equal(report.succeeded, true, JSON.stringify(report.diagnostics));
  const app = path.join(report.preparedPackagePath, 'nativescript/app');
  const emitted = await fs.readFile(path.join(app, 'modules/index.mjs'), 'utf8');
  assert.match(emitted, /from "fixture-canonical"/);
  assert.match(emitted, /from "\.\/src\/value.mjs"/);
  assert.doesNotMatch(emitted, /local-canonical.mjs/);
  assert.equal(await fs.readFile(path.join(app, 'node_modules/fixture-canonical/index.js'), 'utf8'),
    await fs.readFile(path.join(f.canonical, 'index.js'), 'utf8'));
  assert.notEqual(await fs.readFile(path.join(app, 'node_modules/fixture-canonical/index.js'), 'utf8'),
    await fs.readFile(path.join(local, 'index.js'), 'utf8'));
  assert.equal((await import(pathToFileURL(path.join(app, 'modules/index.mjs')).href)).result, 'sdk:nested:project:alias');
});

test('missing canonical exports, configs and SDK dependencies never resolve from ancestor packages', async t => {
  const f = await fixture(t);
  await fs.writeFile(f.entry, 'import {privateValue} from "fixture-canonical/private"; export const value = privateValue;\n');
  const missingExport = await f.run('validate');
  assert.equal(missingExport.succeeded, false);
  assert.ok(missingExport.diagnostics.some(d => d.code === 'TS2307' && d.message.includes('fixture-canonical/private')), JSON.stringify(missingExport.diagnostics));
  await fs.writeFile(f.entry, 'export const value: number = 42;\n');
  await writeJSON(path.join(f.project, 'tsconfig.json'), {...f.config, extends: 'fixture-canonical/missing.json'});
  const missingConfig = await f.run('validate');
  assert.equal(missingConfig.succeeded, false);
  assert.ok(missingConfig.diagnostics.some(d => d.code.startsWith('TS') && d.message.includes('missing.json')), JSON.stringify(missingConfig.diagnostics));
  await writeJSON(path.join(f.project, 'tsconfig.json'), f.config);
  await fs.rm(f.ancestor, {recursive: true});
  await packageAt(f.root, 'fixture-absent', '1.0.0', 'export declare const escaped: number;\n');
  await fs.appendFile(path.join(f.canonical, 'index.d.ts'), 'export {escaped} from "fixture-absent";\n');
  await fs.writeFile(f.entry, 'import {tag} from "fixture-canonical"; export const value = tag;\n');
  const missingDependency = await f.run('validate');
  assert.equal(missingDependency.succeeded, false);
  assert.ok(missingDependency.diagnostics.some(d => d.code === 'TS2307' && d.message.includes('fixture-absent')), JSON.stringify(missingDependency.diagnostics));
});
