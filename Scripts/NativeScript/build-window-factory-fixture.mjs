import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
const versions = JSON.parse(await readFile(new URL('./dependency-lock.json', import.meta.url), 'utf8')).nativeScript;
const root = resolve(import.meta.dirname, 'Fixtures/window-factory-source');
const app = resolve(root, 'nativescript/app');
await mkdir(app, {recursive: true});
const bundle = `import { Page, StackLayout, Label, TextView, Button, File } from '@nativescript/core';
import { registerWindowFactory } from '@hanlin/window-factory';

// Module state must also be isolated for two windows of this same package.
let increments = 0;
registerWindowFactory(({id, services, storage}) => {
  const page = new Page();
  page.actionBarHidden = true;
  const layout = new StackLayout();
  layout.padding = 20;
  const request = new Label();
  request.accessibilityIdentifier = 'hanlin-ns-window-request';
  request.text = 'Loading';
  const input = new TextView();
  input.accessibilityIdentifier = 'hanlin-ns-window-input';
  input.height = 150;
  const status = new Label();
  status.accessibilityIdentifier = 'hanlin-ns-window-status';
  status.text = 'Loading';
  const counter = new Label();
  counter.accessibilityIdentifier = 'hanlin-ns-window-counter';
  counter.text = '0';
  let documentID = '';
  let prepared;
  const button = (title, id, run) => {
    const result = new Button();
    result.text = title;
    result.accessibilityIdentifier = id;
    result.on('tap', run);
    return result;
  };
  const increment = button('Increment', 'hanlin-ns-window-increment', () => {
    counter.text = String(++increments);
  });
  const prepare = button('Prepare Return', 'hanlin-ns-window-prepare-return', () => {
    input.dismissSoftInput();
    const text = input.text ?? '';
    File.fromPath(storage.state + '/same-name.txt').writeTextSync(text);
    const metadata = {windowSessionID: id, requestID: request.text, documentID, counter: String(increments)};
    prepared = () => services.miniapps.complete({
      operation: 'replaceSelection', items: [{kind: 'text', text}],
      metadata: {...metadata, storedValue: File.fromPath(storage.state + '/same-name.txt').readTextSync()}
    });
    status.text = 'Prepared';
  });
  const complete = button('Return', 'hanlin-ns-window-return', () => {
    if (!prepared) { status.text = 'Prepare first'; return; }
    const ownCompletion = prepared;
    Promise.resolve().then(ownCompletion).then(() => { status.text = 'Returned'; })
      .catch(error => { status.text = String(error.message ?? error); });
  });
  for (const child of [request, prepare, input, status, counter, increment, complete]) layout.addChild(child);
  page.content = layout;
  services.miniapps.getContext().then(context => {
    request.text = context.id;
    documentID = context.source.documentID ?? '';
    input.text = context.inputs.filter(item => item.kind === 'text').map(item => item.text ?? '').join('\\n');
    status.text = 'Ready';
  }).catch(error => { status.text = String(error.message ?? error); });
  return page;
});
`;
await writeFile(resolve(app, 'bundle.mjs'), bundle);
await writeFile(resolve(app, 'package.json'), JSON.stringify({
  name: 'hanlin-window-factory', version: '1.0.0', private: true, type: 'module',
  main: 'bundle.mjs', hanlinRuntime: 'hanlin-nativescript',
  hanlinNativeScript: {runtimeVersion: versions.iosRuntimeVersion, plugins: {}, windowFactory: 1},
  dependencies: {'@nativescript/core': versions.coreVersion}
}, null, 2) + '\n');
await writeFile(resolve(root, 'script.json'), JSON.stringify({
  name: 'Hanlin NativeScript Window Factory E2E', version: '1.0.0',
  hanlinAppID: 'hanlin.nativescript.window-factory',
  description: 'Two fresh NativeScript roots with window-bound MiniApps contexts and callbacks.',
  entry: 'nativescript/app/bundle.mjs', runInApp: true, hanlinRuntime: 'hanlin-nativescript'
}, null, 2) + '\n');
const destination = resolve(import.meta.dirname, 'Fixtures/window-factory.hanlinNativeScript');
execFileSync('python3', ['-c', 'import pathlib,sys,zipfile; root=pathlib.Path(sys.argv[1]); z=zipfile.ZipFile(sys.argv[2],"w",zipfile.ZIP_DEFLATED); [z.write(p,p.relative_to(root)) for p in sorted(root.rglob("*")) if p.is_file()]; z.close()', root, destination]);
console.log('Prepared cooperating window factory fixture: ' + destination);
