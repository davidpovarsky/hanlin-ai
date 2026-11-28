import ts from './node_modules/typescript/lib/typescript.js';
import path from 'node:path';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import './prepare-types.mjs';

const root = path.resolve(import.meta.dirname, '../..');
const nativeAPI = process.argv.includes('--native-api');
const widgets = process.argv.includes('--widgets');
const configPath = path.join(root, widgets ? 'Fixtures/ExpoWidgetsProbe/tsconfig.json' : nativeAPI ? 'Fixtures/ExpoNativeAPIProbe/tsconfig.json' : 'Fixtures/ExpoSwiftUIProbe/tsconfig.json');
const config = ts.readConfigFile(configPath, ts.sys.readFile);
if (config.error) throw new Error(ts.flattenDiagnosticMessageText(config.error.messageText, '\n'));
const parsed = ts.parseJsonConfigFileContent(config.config, ts.sys, path.dirname(configPath));
if (parsed.errors.length || parsed.options.skipLibCheck !== false || parsed.options.strict !== true) {
  throw new Error('The public UI SDK must check all declarations under strict mode.');
}
const format = diagnostics => ts.formatDiagnosticsWithColorAndContext(diagnostics, {
  getCanonicalFileName: f => f, getCurrentDirectory: () => root, getNewLine: () => '\n'});
const valid = ts.getPreEmitDiagnostics(ts.createProgram(parsed.fileNames, {...parsed.options, noEmit: true}));
if (valid.length) throw new Error(format(valid));
const fixture = path.join(path.dirname(configPath), '__sdk_negative__.ts');
const negativeSource = widgets ? `import {createWidget, createLiveActivity, type LiveActivityComponent} from 'expo-widgets';
import type {ReactElement} from 'react';
declare const layout: (props: {count: number}) => ReactElement;
const widget = createWidget('typed', layout);
widget.updateTimeline([{date: 'invalid', props: {count: 1}}]);
widget.imaginaryOperation();
declare const activityLayout: LiveActivityComponent<{count: number}>;
createLiveActivity('typed-activity', activityLayout).start({count: 'invalid'});
` : `import {hostServices, type TextEditorProps} from '@hanlin/expo-ui';
const unknownProperty: TextEditorProps = {imaginaryProperty: true};
const wrongValue: TextEditorProps = {value: 42};
const wrongEvent: TextEditorProps = {onValueChange: (value: number) => {}};
hostServices.methodThatDoesNotExist();
function implicitParameter(value) { return value; }
` + (nativeAPI ? `const actualTimezone: number = timezone;
const actualRanges: dyld_shared_cache_ranges = dyld_shared_cache_ranges;
new timezone();
declare const restriction: UIActivityCollaborationModeRestriction;
const description: string = restriction.description;
restriction.description();
` : '');
const host = ts.createCompilerHost(parsed.options);
const originalSource = host.getSourceFile.bind(host);
const isFixture = file => path.resolve(file) === fixture;
host.getSourceFile = (file, language, ...rest) => isFixture(file)
  ? ts.createSourceFile(file, negativeSource, language, true) : originalSource(file, language, ...rest);
const negative = ts.getPreEmitDiagnostics(ts.createProgram([...parsed.fileNames, fixture], {...parsed.options, noEmit: true}, host));
const codes = negative.map(d => d.code).sort((a, b) => a - b);
const expected = widgets ? [2322,2322,2339] : nativeAPI ? [2322,2322,2339,2349,2351,2353,7006] : [2322,2322,2339,2353,7006];
if (negative.some(d => !d.file || !isFixture(d.file.fileName)) || JSON.stringify(codes) !== JSON.stringify(expected)) {
  throw new Error('The negative cases did not fail exactly as required:\n' + format(negative));
}
const digest = data => createHash('sha256').update(data).digest('hex');
const output = path.join(root, 'build/acceptance', widgets ? 'expo-original-widgets-types' : nativeAPI ? 'expo-native-api-types' : 'expo-ui-types');
await mkdir(output, {recursive: true});
await writeFile(path.join(output, 'result.json'), JSON.stringify({schemaVersion: 1,
  compilerVersion: ts.version, compilerSHA256: digest(await readFile(new URL('./node_modules/typescript/lib/typescript.js', import.meta.url))),
  configSHA256: digest(await readFile(configPath)), negativeSourceSHA256: digest(negativeSource),
  valid: {status: 'EXECUTED_PASS', diagnostics: 0, strict: true, skipLibCheck: false},
  negative: {status: 'EXECUTED_PASS', expectedDiagnostics: codes},
  boundary: 'TypeScript checks only; Metro/native adapter/physical acceptance are separate.'}, null, 2) + '\n');
console.log(`PASS: TypeScript${ts.version} strict ${widgets ? 'original Widgets' : nativeAPI ? 'native API' : 'UI'} declarations, zero valid diagnostics and ${expected.length} exact negative diagnostics.`);
