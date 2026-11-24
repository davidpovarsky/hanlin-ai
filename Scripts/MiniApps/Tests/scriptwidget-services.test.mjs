import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, readFile, writeFile, rm, cp} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {generateScriptWidgetServiceTypes} from '../generate-scriptwidget-service-types.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const sdk = path.join(root, 'Scripts/MiniApps/scriptwidget');
const compilerPath = process.env.HANLIN_AUTHORING_TYPESCRIPT;
assert.ok(compilerPath, 'Set HANLIN_AUTHORING_TYPESCRIPT to the original installed TypeScript compiler.');
const ts = (await import(compilerPath.startsWith('file:') ? compilerPath : pathToFileURL(compilerPath).href)).default;
const definitions = ['components.d.ts', 'host-globals.d.ts'].map(name => path.join(sdk, name));
async function diagnostics(source) {
  const temporary = await mkdtemp(path.join(os.tmpdir(), 'scriptwidget-native-types-'));
  try {
    const file = path.join(temporary, 'consumer.tsx');
    await writeFile(file, source);
    const program = ts.createProgram([...definitions, file], {
      strict: true, skipLibCheck: false, noEmit: true, target: ts.ScriptTarget.ES2023,
      module: ts.ModuleKind.ESNext, moduleResolution: ts.ModuleResolutionKind.Bundler,
      jsx: ts.JsxEmit.Preserve, lib: ['lib.es2023.d.ts'], types: []
    });
    return ts.getPreEmitDiagnostics(program).map(item => ({
      code: item.code, message: ts.flattenDiagnosticMessageText(item.messageText, '\n'),
      file: item.file?.fileName, line: item.file && item.start !== undefined ? item.file.getLineAndCharacterOfPosition(item.start).line + 1 : undefined
    }));
  } finally { await rm(temporary, {recursive: true, force: true}); }
}

test('generated API inventory agrees with actual installed native exports and original catalog provenance', async () => {
  const result = await generateScriptWidgetServiceTypes({root, check: true});
  assert.equal(result.nativeObjects, 24);
  assert.equal(result.nativeMethods, 118);
  const manifest = JSON.parse(await readFile(path.join(sdk, 'native-api.json'), 'utf8'));
  const methods = manifest.bindings.flatMap(binding => binding.methods.map(method => binding.global + '.' + method.name));
  const errors = await diagnostics(methods.map(method => 'void ' + method + ';').join('\n'));
  assert.deepEqual(errors, []);
  assert.ok(manifest.sources.every(file => /^[a-f0-9]{64}$/.test(file.sha256)));
});

test('real TypeScript accepts typed original services, nullable results, native await and JSX', async () => {
  const errors = await diagnostics(`
async function widget() {
  const weather = await $weather.forecast({latitude: 31.8, longitude: 35.2, hours: 6});
  const temperature: number = weather.hours[0].temperatureC;
  const place: string = (await $maps.search({query: "park", latitude: 31.8, longitude: 35.2}))[0].name;
  const status: string = (await $notifications.schedule({key: "daily", title: "Title", body: "Body", daily: {hour: 9, minute: 0}})).status;
  const events = await $calendar.events({calendarIDs: ["calendar"]});
  const allDay: boolean = events.items[0].allDay;
  const completedAt: string | null = (await $reminders.items()).items[0].completedAt;
  const image: string = (await $photos.items({limit: 1})).items[0].image;
  const metric: number | null = (await $health.dailyStatistics({metric: "steps"})).items[0].value;
  const energy: number | null = (await $health.workouts()).items[0].energyKcal;
  const title: string | null = (await $music.current()).title;
  const username: string | null = (await $services.profile("github")).username;
  const document = await $icloud.readJSON("shared");
  await $icloud.writeJSON("shared", {value: 1}, document.revision);
  const object: ScriptWidgetJSONObject | ScriptWidgetJSON[] = await $documents.readJSON("document");
  const body: string = await $fetch("https://example.com");
  const chained: void = $http.get("https://example.com").then(value => value.length, reason => String(reason));
  $storage.set("snapshot", {temperature, place});
  $storage.compareAndSetJSON("value", {}, {number: 1});
  const xml: string = $xml.parse("<root>text</root>").text;
  $render(<vstack><text>{temperature}</text><text>{place}</text></vstack>);
}
void widget;
`);
  assert.deepEqual(errors, []);
});

test('real TypeScript reports wrong native options, nullable results, unsupported Promise APIs and missing methods', async () => {
  const cases = [
    ['$weather.forecast({latitude: "north", longitude: 35});', 2322],
    ['$notifications.schedule({key: "daily", title: "Title", body: "Body"});', 2345],
    ['$home.setPower({id: "lamp", on: "yes"});', 2322],
    ['$calendar.events({calenderIDs: ["typo"]});', 2561],
    ['$health.dailyStatistics({metric: "cpu"});', 2322],
    ['$http.get("https://example.com").catch(() => {});', 2339],
    ['console.warn("not an original export");', 2339],
    ['async function weatherNullability() { const precipitation: number = (await $weather.forecast({latitude: 0, longitude: 0})).hours[0].precipitationMM; }', 2322],
    ['$services.profile("imaginary-provider");', 2345],
    ['$icloud.writeJSON("doc", {value: 1}, 42);', 2345],
    ['async function invalid() { const title: string = (await $music.current()).title; }', 2322],
    ['$reminders.setCompleted({requestID: "id", listID: "list", id: "reminder", completed: "yes"});', 2322],
  ];
  const errors = await diagnostics(cases.map(([source]) => source).join('\n'));
  for (let index = 0; index < cases.length; index++)
    assert.ok(errors.some(item => item.code === cases[index][1] && item.line === index + 1),
      'Missing expected real diagnostic for line ' + (index + 1) + ': ' + JSON.stringify(errors));
  assert.equal(errors.length, cases.length);
});

test('a new original native method cannot silently receive a fabricated result schema', async () => {
  const temporary = await mkdtemp(path.join(os.tmpdir(), 'scriptwidget-api-drift-'));
  try {
    for (const relative of ['Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal',
      'Packages/HanlinPlatform/Sources/HanlinScriptExtensions/ScriptWidget',
      'Scripts/MiniApps/scriptwidget']) {
      await cp(path.join(root, relative), path.join(temporary, relative), {recursive: true});
    }
    const file = path.join(temporary, 'Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Widget/API/ScriptWidgetRuntimeWeather.swift');
    const source = await readFile(file, 'utf8');
    await writeFile(file, source.replace('static func forecast(', 'static func newlyAddedNativeOperation() -> ScriptWidgetRuntimePromise\n    static func forecast('));
    await assert.rejects(generateScriptWidgetServiceTypes({root: temporary, output: path.join(temporary, 'generated')}),
      /Missing original native result schema: \$weather.newlyAddedNativeOperation/);
  } finally { await rm(temporary, {recursive: true, force: true}); }
});

test('actual presentation bindings preserve native context, regions, action values and diagnostics', async () => {
  const source = `
const context = $getenv("presentation");
if (context) { const text: string = context.inputText; const kind: "snippet" | "translationUI" = context.kind; }
if ($widget.presentation) { const replacementAllowed: boolean = $widget.presentation.allowsReplacement; }
$presentation.expandSheet();
$presentation.finish("Selected replacement");
$presentation.finish(null);
$component("Caption", (props: {text: string}) => <text>{props.text}</text>);
$dynamic_island({minimal: <text>Ready</text>, expanded: {leading: <text>Leading</text>}});
$render(<button onClick="search" actionParameters={{query: "שלום"}}><text>Search</text></button>);
const event: ScriptWidgetActionEvent<{query: string}> = {parameters: {query: "שלום"}, value: true};
`;
  assert.deepEqual(await diagnostics(source), []);
  const errors = await diagnostics([
    '$dynamic_island({minimal: "not an element"});',
    '$presentation.finish(42);',
    '$render(<button actionParameters={{run: () => 1}}>Invalid</button>);',
    'const contextKind = $getenv("presentation").kind;'
  ].join('\n'));
  assert.ok(errors.some(item => item.code === 2322 && item.line === 1));
  assert.ok(errors.some(item => item.code === 2345 && item.line === 2));
  assert.ok(errors.some(item => item.code === 2322 && item.line === 3));
  assert.ok(errors.some(item => item.code === 2339 && item.line === 4));
  assert.equal(errors.length, 4);
});
