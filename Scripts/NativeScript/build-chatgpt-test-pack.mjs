import { cp, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const scriptRoot = resolve(import.meta.dirname);
const repositoryRoot = resolve(scriptRoot, '..', '..');
const generatedRoot = resolve(scriptRoot, 'Fixtures', 'GeneratedChatGPT');
const buildRoot = resolve(scriptRoot, '.chatgpt-ns-build');
const outputRoot = resolve(repositoryRoot, 'build', 'ChatGPTNativeScriptTestPack');
const packageJSONPath = resolve(scriptRoot, 'package.json');
const originalPackageJSON = await readFile(packageJSONPath, 'utf8');
const dependencyLock = JSON.parse(await readFile(resolve(scriptRoot, 'dependency-lock.json'), 'utf8'));

const sources = {
  'rich-dashboard.ts': `import {
  Application,
  Button,
  Label,
  Page,
  ScrollView,
  StackLayout,
  View,
  knownFolders
} from '@nativescript/core';

declare global { var __HANLIN_NATIVESCRIPT_PACKAGE_NAME__: string | undefined; }
const packageName = globalThis.__HANLIN_NATIVESCRIPT_PACKAGE_NAME__ ?? 'NativeScript-Rich-Dashboard';
let taps = 0;
const stateFile = knownFolders.documents().getFile('hanlin-dashboard-state.json');

function add(parent: StackLayout, child: View): void { parent.addChild(child); }
function text(value: string, size = 16): Label {
  const label = new Label();
  label.text = value;
  label.fontSize = size;
  label.textWrap = true;
  label.marginBottom = 10;
  return label;
}
function saveState(): void {
  stateFile.writeTextSync(JSON.stringify({ packageName, taps, savedAt: new Date().toISOString() }));
}

console.log('HANLIN_NS_DASHBOARD_STARTED');
Application.run({
  create: () => {
    const page = new Page();
    const scroll = new ScrollView();
    const root = new StackLayout();
    root.padding = 24;

    add(root, text('Hanlin Native Dashboard', 30));
    add(root, text('A native NativeScript dashboard exercising scrolling, nested layouts, live state and persistent package data.', 16));

    const metrics = new StackLayout();
    metrics.padding = 16;
    metrics.marginBottom = 18;
    add(metrics, text('TODAY', 13));
    add(metrics, text('24 active sessions', 24));
    add(metrics, text('92% completion rate', 20));
    add(metrics, text('7 pending actions', 20));
    add(root, metrics as unknown as View);

    const state = text('Interaction count: 0', 20);
    state.accessibilityIdentifier = 'hanlin-dashboard-state';
    add(root, state);

    const increment = new Button();
    increment.text = 'Run dashboard action';
    increment.accessibilityIdentifier = 'hanlin-dashboard-action';
    increment.on('tap', () => {
      taps += 1;
      state.text = 'Interaction count: ' + taps;
      saveState();
      console.log('HANLIN_NS_DASHBOARD_ACTION count=' + taps);
    });
    add(root, increment as unknown as View);

    const reset = new Button();
    reset.text = 'Reset state';
    reset.on('tap', () => {
      taps = 0;
      state.text = 'Interaction count: 0';
      saveState();
    });
    add(root, reset as unknown as View);

    add(root, text('Recent activity', 24));
    for (let index = 1; index <= 14; index += 1) {
      add(root, text(index + '. Native event successfully rendered inside the scrolling dashboard surface.'));
    }

    scroll.content = root;
    page.content = scroll;
    console.log('HANLIN_NS_DASHBOARD_READY');
    return page;
  }
});
`,
  'interactive-forms.ts': `import {
  Application,
  Button,
  Label,
  Page,
  ScrollView,
  StackLayout,
  Switch,
  TextField,
  View,
  knownFolders
} from '@nativescript/core';

declare global { var __HANLIN_NATIVESCRIPT_PACKAGE_NAME__: string | undefined; }
const stateFile = knownFolders.documents().getFile('hanlin-form-state.json');
function add(parent: StackLayout, child: View): void { parent.addChild(child); }
function label(value: string, size = 16): Label {
  const item = new Label(); item.text = value; item.fontSize = size; item.textWrap = true; item.marginBottom = 8; return item;
}

console.log('HANLIN_NS_FORMS_STARTED');
Application.run({
  create: () => {
    const page = new Page();
    const scroll = new ScrollView();
    const root = new StackLayout(); root.padding = 24;
    add(root, label('Interactive Native Form', 30));
    add(root, label('Exercises editable text, boolean state, validation, reset and persistence.'));

    add(root, label('Name'));
    const name = new TextField(); name.hint = 'Your name'; name.accessibilityIdentifier = 'hanlin-form-name'; name.marginBottom = 14; add(root, name as unknown as View);
    add(root, label('Email'));
    const email = new TextField(); email.hint = 'name@example.com'; email.accessibilityIdentifier = 'hanlin-form-email'; email.marginBottom = 14; add(root, email as unknown as View);
    add(root, label('Enable updates'));
    const updates = new Switch(); updates.checked = true; updates.accessibilityIdentifier = 'hanlin-form-updates'; updates.marginBottom = 18; add(root, updates as unknown as View);

    const status = label('Ready to submit.', 18); status.accessibilityIdentifier = 'hanlin-form-status'; add(root, status);
    const submit = new Button(); submit.text = 'Validate and save'; submit.accessibilityIdentifier = 'hanlin-form-submit';
    submit.on('tap', () => {
      const nameValue = (name.text ?? '').trim();
      const emailValue = (email.text ?? '').trim();
      if (!nameValue || !emailValue.includes('@')) {
        status.text = 'Please enter a name and a valid email address.';
        console.log('HANLIN_NS_FORMS_INVALID');
        return;
      }
      const payload = { name: nameValue, email: emailValue, updates: updates.checked, savedAt: new Date().toISOString() };
      stateFile.writeTextSync(JSON.stringify(payload));
      status.text = 'Saved: ' + nameValue + ' / updates ' + (updates.checked ? 'on' : 'off');
      console.log('HANLIN_NS_FORMS_SAVED ' + JSON.stringify(payload));
    });
    add(root, submit as unknown as View);

    const reset = new Button(); reset.text = 'Reset form';
    reset.on('tap', () => { name.text = ''; email.text = ''; updates.checked = false; status.text = 'Form reset.'; });
    add(root, reset as unknown as View);

    scroll.content = root; page.content = scroll;
    console.log('HANLIN_NS_FORMS_READY');
    return page;
  }
});
`,
  'navigation-catalog.ts': `import {
  Application,
  Button,
  Frame,
  Label,
  Page,
  StackLayout,
  View
} from '@nativescript/core';

function add(parent: StackLayout, child: View): void { parent.addChild(child); }
function heading(value: string, size = 28): Label { const item = new Label(); item.text = value; item.fontSize = size; item.textWrap = true; item.marginBottom = 12; return item; }

function detailsPage(frame: Frame, depth: number): Page {
  const page = new Page();
  const root = new StackLayout(); root.padding = 24;
  add(root, heading('Navigation destination ' + depth));
  add(root, heading('This page is a real NativeScript Frame destination with independent controls.', 17));
  const deeper = new Button(); deeper.text = 'Push next destination'; deeper.accessibilityIdentifier = 'hanlin-nav-deeper-' + depth;
  deeper.on('tap', () => frame.navigate({ create: () => detailsPage(frame, depth + 1) })); add(root, deeper as unknown as View);
  const back = new Button(); back.text = 'Go back'; back.accessibilityIdentifier = 'hanlin-nav-back-' + depth;
  back.on('tap', () => frame.goBack()); add(root, back as unknown as View);
  page.content = root; return page;
}

function homePage(frame: Frame): Page {
  const page = new Page();
  const root = new StackLayout(); root.padding = 24;
  add(root, heading('Native Navigation Catalog'));
  add(root, heading('Exercises a persistent Frame, push navigation, nested destinations and back navigation.', 17));
  const first = new Button(); first.text = 'Open destination 1'; first.accessibilityIdentifier = 'hanlin-nav-open';
  first.on('tap', () => { console.log('HANLIN_NS_NAV_PUSH depth=1'); frame.navigate({ create: () => detailsPage(frame, 1) }); });
  add(root, first as unknown as View);
  page.content = root; return page;
}

console.log('HANLIN_NS_NAV_STARTED');
Application.run({
  create: () => {
    const frame = new Frame();
    frame.navigate({ create: () => homePage(frame) });
    console.log('HANLIN_NS_NAV_READY');
    return frame;
  }
});
`,
  'rtl-state-stress.ts': `import {
  Application,
  Button,
  Label,
  Page,
  ScrollView,
  StackLayout,
  TextField,
  View,
  knownFolders
} from '@nativescript/core';

const stateFile = knownFolders.documents().getFile('hanlin-rtl-stress-state.json');
let counter = 0;
try {
  const saved = stateFile.readTextSync().trim();
  if (saved) counter = Number(JSON.parse(saved).counter ?? 0) || 0;
} catch {}
function add(parent: StackLayout, child: View): void { parent.addChild(child); }
function hebrew(value: string, size = 17): Label { const item = new Label(); item.text = value; item.fontSize = size; item.textWrap = true; item.textAlignment = 'right'; item.marginBottom = 10; return item; }
function persist(): void { stateFile.writeTextSync(JSON.stringify({ counter, savedAt: new Date().toISOString(), locale: 'he-IL' })); }

console.log('HANLIN_NS_RTL_STRESS_STARTED');
Application.run({
  create: () => {
    const page = new Page(); const scroll = new ScrollView(); const root = new StackLayout(); root.padding = 24;
    add(root, hebrew('בדיקת עברית, RTL ומצב מתמשך', 30));
    add(root, hebrew('המסך הזה בודק טקסט עברי ארוך, יישור לימין, קלט, גלילה, מאות שינויי מצב ושחזור מצב מהאחסון המקומי.'));
    const input = new TextField(); input.hint = 'כתוב כאן טקסט בעברית'; input.textAlignment = 'right'; input.accessibilityIdentifier = 'hanlin-rtl-input'; input.marginBottom = 16; add(root, input as unknown as View);
    const state = hebrew('מונה מתמשך: ' + counter, 21); state.accessibilityIdentifier = 'hanlin-rtl-counter'; add(root, state);
    const mutate = new Button(); mutate.text = 'בצע 250 שינויי מצב'; mutate.accessibilityIdentifier = 'hanlin-rtl-stress';
    mutate.on('tap', () => { for (let i = 0; i < 250; i += 1) counter += 1; persist(); state.text = 'מונה מתמשך: ' + counter; console.log('HANLIN_NS_RTL_STRESS_MUTATED counter=' + counter); });
    add(root, mutate as unknown as View);
    const saveText = new Button(); saveText.text = 'שמור גם את הטקסט';
    saveText.on('tap', () => { stateFile.writeTextSync(JSON.stringify({ counter, text: input.text ?? '', savedAt: new Date().toISOString(), locale: 'he-IL' })); state.text = 'נשמר. מונה מתמשך: ' + counter; });
    add(root, saveText as unknown as View);
    for (let i = 1; i <= 18; i += 1) add(root, hebrew(i + '. פסקת בדיקה ארוכה בעברית כדי לוודא גלילה, עטיפת שורות ויציבות תצוגה גם בתוכן רב. זהו טקסט בדיקה מקומי של החבילה.'));
    scroll.content = root; page.content = scroll; console.log('HANLIN_NS_RTL_STRESS_READY counter=' + counter); return page;
  }
});
`
};

const packages = [
  { slug: 'rich-dashboard', archive: 'NativeScript-Rich-Dashboard.hanlinNativeScript', displayName: 'NativeScript Rich Dashboard', description: 'Native scrolling dashboard with live controls and persistent state.', entry: 'Fixtures/GeneratedChatGPT/rich-dashboard.ts' },
  { slug: 'interactive-forms', archive: 'NativeScript-Interactive-Forms.hanlinNativeScript', displayName: 'NativeScript Interactive Forms', description: 'Native editable form controls, validation, reset and persistence.', entry: 'Fixtures/GeneratedChatGPT/interactive-forms.ts' },
  { slug: 'navigation-catalog', archive: 'NativeScript-Navigation-Catalog.hanlinNativeScript', displayName: 'NativeScript Navigation Catalog', description: 'Native Frame push and back navigation across multiple pages.', entry: 'Fixtures/GeneratedChatGPT/navigation-catalog.ts' },
  { slug: 'rtl-state-stress', archive: 'NativeScript-RTL-State-Stress.hanlinNativeScript', displayName: 'NativeScript RTL State Stress', description: 'Hebrew RTL, long scrolling content, input and persistent state stress.', entry: 'Fixtures/GeneratedChatGPT/rtl-state-stress.ts' },
  { slug: 'swiftui-showcase', archive: 'NativeScript-SwiftUI-Showcase.hanlinNativeScript', displayName: 'NativeScript SwiftUI Showcase', description: 'Official @nativescript/swift-ui bridge using Hanlin compiled provider support.', entry: 'Fixtures/Source/swiftui-app.ts', swiftUI: true }
];

await rm(generatedRoot, { recursive: true, force: true });
await rm(buildRoot, { recursive: true, force: true });
await rm(outputRoot, { recursive: true, force: true });
await mkdir(generatedRoot, { recursive: true });
await mkdir(outputRoot, { recursive: true });
for (const [name, source] of Object.entries(sources)) await writeFile(resolve(generatedRoot, name), source);

async function buildOne(definition) {
  const packageJSON = JSON.parse(originalPackageJSON);
  packageJSON.main = definition.entry;
  await writeFile(packageJSONPath, JSON.stringify(packageJSON, null, 2) + '\n');
  const result = spawnSync(
    process.execPath,
    [resolve(scriptRoot, 'node_modules', 'vite', 'bin', 'vite.js'), 'build', '--mode', 'production', '--', '--env.ios'],
    { cwd: scriptRoot, env: { ...process.env, NS_VITE_DIST_DIR: `.chatgpt-ns-build/${definition.slug}` }, stdio: 'inherit', shell: false }
  );
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`Build failed for ${definition.slug}: ${result.status ?? 1}`);

  const sourceBuild = resolve(buildRoot, definition.slug);
  const packageRoot = resolve(outputRoot, definition.slug);
  const destinationApp = resolve(packageRoot, 'nativescript', 'app');
  await mkdir(destinationApp, { recursive: true });
  await cp(sourceBuild, destinationApp, { recursive: true });

  const appPackage = {
    name: `hanlin-${definition.slug}`,
    version: '1.0.0',
    main: 'bundle.mjs',
    hanlinRuntime: 'hanlin-nativescript',
    ...(definition.swiftUI ? { hanlinNativeScript: { runtimeVersion: '9.1.0', plugins: { '@nativescript/swift-ui': '4.0.2' } } } : {})
  };
  await writeFile(resolve(destinationApp, 'package.json'), JSON.stringify(appPackage, null, 2) + '\n');

  if (definition.swiftUI) {
    await writeFile(resolve(destinationApp, 'hanlin-native-plugin-runtime.json'), JSON.stringify({
      schemaVersion: 1,
      package: dependencyLock.swiftUI.package,
      version: dependencyLock.swiftUI.version,
      integrity: dependencyLock.swiftUI.integrity,
      runtimeFiles: dependencyLock.swiftUI.runtimeFiles,
      disposition: 'Bundled JavaScript with provider support precompiled into Hanlin'
    }, null, 2) + '\n');
  }

  await writeFile(resolve(packageRoot, 'script.json'), JSON.stringify({
    name: definition.displayName,
    version: '1.0.0',
    description: definition.description,
    entry: 'nativescript/app/bundle.mjs',
    runInApp: true,
    hanlinRuntime: 'hanlin-nativescript'
  }, null, 2) + '\n');

  const bundleFiles = (await readdir(destinationApp)).filter((name) => name.endsWith('.mjs'));
  if (!bundleFiles.includes('bundle.mjs')) throw new Error(`${definition.slug} is missing bundle.mjs`);
  const bundleText = (await Promise.all(bundleFiles.map((name) => readFile(resolve(destinationApp, name), 'utf8')))).join('\n');
  if (definition.swiftUI) {
    for (const proof of ['HanlinNativeScriptSwiftUIFixtureProvider', 'swiftUIEvent', 'swiftId', 'HANLIN_NS_SWIFTUI_MODULE_OK']) {
      if (!bundleText.includes(proof)) throw new Error(`SwiftUI bundle is missing ${proof}`);
    }
  }

  const archivePath = resolve(outputRoot, definition.archive);
  const zip = spawnSync('zip', ['-qry', archivePath, '.'], { cwd: packageRoot, stdio: 'inherit', shell: false });
  if (zip.error) throw zip.error;
  if (zip.status !== 0) throw new Error(`zip failed for ${definition.slug}`);
}

try {
  for (const definition of packages) await buildOne(definition);
} finally {
  await writeFile(packageJSONPath, originalPackageJSON);
}

await writeFile(resolve(outputRoot, 'README.txt'), `Hanlin NativeScript Test Pack\nBuilt from repository NativeScript tooling.\nRuntime: @nativescript/core 9.1.0\nSwiftUI plugin: @nativescript/swift-ui 4.0.2\nPackages: Rich Dashboard, Interactive Forms, Navigation Catalog, SwiftUI Showcase, RTL State Stress.\n`);

console.log(`Built NativeScript test pack at ${outputRoot}`);
