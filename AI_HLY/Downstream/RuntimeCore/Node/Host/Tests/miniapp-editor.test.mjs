import test from 'node:test';
import assert from 'node:assert/strict';
import {promises as fs} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {createRequire} from 'node:module';
import {inspectMiniAppSource} from '../miniapp-authoring.mjs';

const require = createRequire(import.meta.url);
const compiler = require(process.env.HANLIN_AUTHORING_TYPESCRIPT ?? 'typescript');

async function fixture(run) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-editor-query-'));
  const project = path.join(root, 'project');
  const sdkRoot = path.join(root, 'sdk');
  await fs.mkdir(project); await fs.mkdir(path.join(sdkRoot, 'tooling'), {recursive: true});
  await fs.writeFile(path.join(sdkRoot, 'miniapp-sdk.json'), JSON.stringify({
    schemaVersion: 1, engines: {nativescript: {toolingRoot: 'tooling', packageVersions: {}}}
  }));
  const write = (name, value) => fs.writeFile(path.join(project, name),
    typeof value === 'string' ? value : JSON.stringify(value));
  await write('script.json', {name: 'Editor query', version: '1.0.0', hanlinRuntime: 'hanlin-nativescript'});
  await write('hanlin.authoring.json', {schemaVersion: 1, engine: 'nativescript', entry: 'index.ts'});
  await write('tsconfig.json', {compilerOptions: {strict: true, target: 'ES2022'}, files: ['index.ts']});
  await write('index.ts', 'export const saved = true;\n');
  const query = (source, position = source.length, extra = {}) => inspectMiniAppSource({
    projectRoot: project, engine: 'nativescript', file: 'index.ts', source, position, version: 7, ...extra
  }, {sdkRoot, compiler});
  try { await run({query, project, root}); }
  finally { await fs.rm(root, {recursive: true, force: true}); }
}

test('original TypeScript supplies member completion and declaration documentation', () => fixture(async ({query}) => {
  const source = '/** Personal greeting. */\nconst person = {\n/** The display name. */\nname: "David", age: 21};\nperson.';
  const result = await query(source, source.length, {completionName: 'name'});
  assert.equal(result.compilerVersion, compiler.version);
  assert.equal(result.version, 7);
  assert.ok(result.completions.some(item => item.name === 'name'));
  assert.ok(result.completions.some(item => item.name === 'age'));
  assert.match(result.display, /name: string/);
  assert.match(result.documentation, /display name/);
}));

test('original TypeScript provides active parameter hints and UTF-16 positions', () => fixture(async ({query}) => {
  const source = '/** Format a greeting. */\nfunction greet(name: string, count: number) { return name.repeat(count); }\nconst unicode = "😀שלום";\ngreet("D", ';
  const result = await query(source);
  assert.match(result.signature, /name: string, count: number/);
  assert.equal(result.argumentIndex, 1);
  assert.match(result.documentation, /Format a greeting/);
}));

test('unsaved overlay diagnostics use canonical strict compiler and never rewrite source', () => fixture(async ({query, project}) => {
  const source = 'const value: number = "wrong";';
  const result = await query(source);
  assert.ok(result.diagnostics.some(item => item.code === 'TS2322' && item.file === 'index.ts' && item.line === 1));
  assert.equal(await fs.readFile(path.join(project, 'index.ts'), 'utf8'), 'export const saved = true;\n');
}));

test('editor refuses cursor and project path escapes, including symlinks', () => fixture(async ({query, project, root}) => {
  await assert.rejects(query('x', 2), /cursor position/);
  await assert.rejects(query('x', -1), /cursor position/);
  await fs.writeFile(path.join(root, 'outside.ts'), 'const secret = 1;');
  await assert.rejects(query('x', 1, {file: '../outside.ts'}), /leaves/);
  await fs.symlink(path.join(root, 'outside.ts'), path.join(project, 'link.ts'));
  await assert.rejects(query('x', 1, {file: 'link.ts'}), /outside/);
}));
