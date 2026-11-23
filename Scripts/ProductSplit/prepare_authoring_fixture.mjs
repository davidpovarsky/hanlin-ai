import {promises as fs} from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {runMiniAppOperation} from '../../AI_HLY/Downstream/RuntimeCore/Node/Host/miniapp-authoring.mjs';

const [sdkRoot, output] = process.argv.slice(2);
if (!sdkRoot || !output) throw new Error('Usage: prepare_authoring_fixture.mjs <actual extracted SDK> <new output directory>');
await fs.mkdir(output, {recursive: false});
const project = path.join(output, 'project');
await fs.mkdir(project);
const source = [
  'export const answer: number = 42;',
  'import {Application, Page, Label} from "@nativescript/core";',
  'Application.run({create: () => {',
  '  const page = new Page();',
  '  page.actionBar.title = "MiniApp Authoring Acceptance";',
  '  const label = new Label();',
  '  label.text = "MiniApp repair result " + answer;',
  '  label.accessibilityIdentifier = "miniapp-authoring-result";',
  '  page.content = label;',
  '  return page;',
  '}});',
  ''
].join('\n');
const files = {
  'script.json': {name: 'MiniApp Authoring Acceptance', version: '1.0.0',
    entry: 'nativescript/app/bundle.mjs', runInApp: true, hanlinRuntime: 'hanlin-nativescript'},
  'package.json': {name: 'hanlin-miniapp-authoring-acceptance', version: '1.0.0', type: 'module'},
  'hanlin.authoring.json': {schemaVersion: 1, engine: 'nativescript', entry: 'index.ts'},
  'tsconfig.json': {compilerOptions: {strict: true, module: 'ESNext', moduleResolution: 'Bundler',
    target: 'ES2022', noEmit: true}, include: ['index.ts']}
};
for (const [name, value] of Object.entries(files))
  await fs.writeFile(path.join(project, name), JSON.stringify(value, null, 2) + '\n');
await fs.writeFile(path.join(project, 'index.ts'), source);
const built = await runMiniAppOperation({operation: 'build', engine: 'nativescript', projectRoot: project}, {sdkRoot});
if (!built.succeeded) throw new Error('Actual original SDK fixture build failed:\n' + JSON.stringify(built, null, 2));
const negative = source.replace('answer: number = 42', 'answer: number = "wrong"');
await fs.writeFile(path.join(built.preparedPackagePath, 'source', 'index.ts'), negative);
// Keep the original output and original successful report. The shipping importer
// must discover both the actual TS2322 and changed retained-source identity.
const checked = await runMiniAppOperation({operation: 'validate', engine: 'nativescript',
  projectRoot: built.preparedPackagePath}, {sdkRoot});
if (checked.succeeded || !checked.diagnostics.some(item => item.code === 'TS2322' && item.file === 'index.ts' && item.line === 1))
  throw new Error('Negative fixture did not expose the real source diagnostic: ' + JSON.stringify(checked));
const sha = value => createHash('sha256').update(value).digest('hex');
const receipt = {schemaVersion: 1, sdk: built.sdk, preparedPackagePath: built.preparedPackagePath,
  sourceSHA256: sha(source), negativeSourceSHA256: sha(negative),
  build: built, negativeValidation: checked, scope: 'Actual original SDK build, followed by an intentionally invalid retained source. No installed state or success receipt is seeded.'};
await fs.writeFile(path.join(output, 'fixture.json'), JSON.stringify(receipt, null, 2) + '\n');
console.log(JSON.stringify(receipt));
