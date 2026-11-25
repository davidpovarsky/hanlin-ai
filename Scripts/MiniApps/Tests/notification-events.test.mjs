import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, mkdir, cp, writeFile, rm} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import os from 'node:os';
import path from 'node:path';

// The original locked compiler used by Expo authoring, including its npm alias.
const require = createRequire(new URL('../../Expo/package.json', import.meta.url));
const ts = require('typescript');
const contract = fileURLToPath(new URL('../notification-events/', import.meta.url));

test('original TypeScript accepts notification data and rejects invalid wire fields', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'hanlin-notification-types-'));
  try {
    const packageRoot = path.join(root, 'node_modules/@hanlin/notification-events');
    await mkdir(path.dirname(packageRoot), {recursive:true});
    await cp(contract, packageRoot, {recursive:true});
    const valid = [
      "import type { HanlinNotificationEventV1 } from '@hanlin/notification-events';",
      'export const event: HanlinNotificationEventV1 = {',
      '  schemaVersion: 1,',
      '  id: "67adf9f7-6e42-4a80-8383-923b60a11c73",',
      '  createdAtUnixMilliseconds: 1795579200000,',
      '  expiresAtUnixMilliseconds: 1795579260000,',
      '  appID: "notification.demo",',
      '  identity: {installedPackageID: "installed.notification.demo", packageID: "notification.demo", generation: 1, entrypointID: "notify"},',
      '  actionID: "receiveNotification",',
      '  parameters: {text: "שלום", nested: [null, true, 3]},',
      '};',
      '',
    ].join('\n');
    const cases = [
      {name:'valid', source:valid, codes:[]},
      {name:'version', source:valid.replace('schemaVersion: 1', 'schemaVersion: 2'), codes:[2322]},
      {name:'generation', source:valid.replace('generation: 1', 'generation: "1"'), codes:[2322]},
      {name:'action', source:valid.replace('  actionID: "receiveNotification",\n', ''), codes:[2741]},
      {name:'code', source:valid.replace('parameters: {text: "שלום", nested: [null, true, 3]}', 'parameters: () => "executable source is not JSON"'), codes:[2322]},
      {name:'unknown', source:valid.replace('  schemaVersion: 1,', '  schemaVersion: 1, runtimeSource: "not a wire field",'), codes:[2353]},
    ];
    const files = [];
    for (const item of cases) {
      const file = path.join(root, item.name + '.ts');
      files.push(file);
      await writeFile(file, item.source);
    }
    // One real compiler program, with no diagnostic suppression or fake types.
    const program = ts.createProgram(files, {target:ts.ScriptTarget.ES2023, module:ts.ModuleKind.ESNext,
      moduleResolution:ts.ModuleResolutionKind.Bundler, strict:true, skipLibCheck:false, noEmit:true});
    const diagnostics = ts.getPreEmitDiagnostics(program);
    const outside = diagnostics.filter(item => !item.file || !files.includes(item.file.fileName));
    assert.equal(outside.length, 0, ts.formatDiagnosticsWithColorAndContext(outside, {
      getCanonicalFileName:file=>file, getCurrentDirectory:()=>root, getNewLine:()=>'\n',
    }));
    for (const item of cases) {
      const actual = diagnostics.filter(diagnostic => diagnostic.file?.fileName === path.join(root, item.name + '.ts'));
      assert.deepEqual(actual.map(diagnostic => diagnostic.code), item.codes, item.name);
    }
  } finally {
    await rm(root, {recursive:true, force:true});
  }
});
