#!/usr/bin/env python3
"""Build actual NativeScript package inputs; never synthesize runtime results."""
import json
from pathlib import Path
import zipfile

HERE = Path(__file__).resolve().parent
versions = json.loads((HERE / "dependency-lock.json").read_text())["nativeScript"]
bundle = """import { Page, StackLayout, Label, TextView, Button, File } from '@nativescript/core';
import { registerWindowFactory } from '@hanlin/window-factory';
import { marker as staticModule, increment, readCounter } from './relative.mjs';
import { marker as privateModule } from 'colliding-private-module';

registerWindowFactory(({id, packageID, services, storage, resourcePath}) => {
  const page = new Page();
  page.actionBarHidden = true;
  const layout = new StackLayout();
  layout.padding = 20;
  const request = new Label();
  request.accessibilityIdentifier = 'hanlin-ns-window-request';
  request.text = 'Loading';
  const identity = new Label();
  identity.accessibilityIdentifier = 'hanlin-ns-window-package';
  identity.className = 'package-identity';
  identity.text = packageID;
  const input = new TextView();
  input.accessibilityIdentifier = 'hanlin-ns-window-input';
  input.height = 150;
  const status = new Label();
  status.accessibilityIdentifier = 'hanlin-ns-window-status';
  status.text = 'Loading';
  const counter = new Label();
  counter.accessibilityIdentifier = 'hanlin-ns-window-counter';
  counter.text = String(readCounter());
  const state = File.fromPath(storage.state + '/same-name.txt');
  let documentID = '';
  let prepared;
  const button = (title, identifier, run) => {
    const result = new Button();
    result.text = title;
    result.accessibilityIdentifier = identifier;
    result.on('tap', run);
    return result;
  };
  const increase = button('Increment', 'hanlin-ns-window-increment', () => {
    counter.text = String(increment());
  });
  const prepare = button('Prepare Return', 'hanlin-ns-window-prepare-return', () => {
    input.dismissSoftInput();
    const text = input.text ?? '';
    state.writeTextSync(text);
    const metadata = {
      packageID, staticModule, privateModule, windowSessionID: id,
      requestID: request.text, documentID, counter: String(readCounter())
    };
    prepared = async () => {
      // Executed after the other package loaded (and after it closed for alpha).
      const later = await import('./dynamic.mjs');
      if (later.privateMarker !== privateModule) throw new Error('Private dependency changed');
      const asset = File.fromPath(resourcePath('assets/identity.txt')).readTextSync();
      const storedValue = File.fromPath(storage.state + '/same-name.txt').readTextSync();
      const color = identity.color;
      const styleColor = [color.r, color.g, color.b, color.a].join(',');
      return services.miniapps.complete({
        operation: 'replaceSelection', items: [{kind: 'text', text}],
        metadata: {...metadata, dynamicModule: later.marker, asset, storedValue, styleColor}
      });
    };
    status.text = 'Prepared';
  });
  const complete = button('Return', 'hanlin-ns-window-return', () => {
    if (!prepared) { status.text = 'Prepare first'; return; }
    Promise.resolve().then(prepared).then(() => { status.text = 'Returned'; })
      .catch(error => { status.text = String(error.message ?? error); });
  });
  for (const child of [request, identity, prepare, input, status, counter, increase, complete]) layout.addChild(child);
  page.content = layout;
  services.miniapps.getContext().then(context => {
    request.text = context.id;
    documentID = context.source.documentID ?? '';
    input.text = context.inputs.filter(item => item.kind === 'text').map(item => item.text ?? '').join('\\n');
    status.text = 'Ready';
  }).catch(error => { status.text = String(error.message ?? error); });
  return page;
});
"""
for name in ("alpha", "beta"):
    root = HERE / "Fixtures" / ("package-window-" + name + "-source")
    app = root / "nativescript/app"
    files = {
        "package.json": json.dumps({
            "name": "hanlin-package-window-" + name, "version": "1.0.0", "private": True, "type": "module",
            "main": "bundle.mjs", "hanlinRuntime": "hanlin-nativescript",
            "hanlinNativeScript": {"runtimeVersion": versions["iosRuntimeVersion"], "plugins": {}, "windowFactory": 1},
            "dependencies": {"@nativescript/core": versions["coreVersion"], "colliding-private-module": "1.0.0"},
        }, indent=2) + "\n",
        "relative.mjs": "export const marker = '" + name + ":relative';\nlet counter = 0;\nexport const increment = () => ++counter;\nexport const readCounter = () => counter;\n",
        "dynamic.mjs": "import { marker as privateMarker } from 'colliding-private-module';\nexport const marker = '" + name + ":dynamic';\nexport { privateMarker };\n",
        "node_modules/colliding-private-module/package.json": json.dumps({
            "name": "colliding-private-module", "version": "1.0.0", "type": "module", "main": "index.mjs"
        }, indent=2) + "\n",
        "node_modules/colliding-private-module/index.mjs": "export const marker = '" + name + ":private';\n",
        "assets/identity.txt": name + ":asset",
        "app.css": ".package-identity { color: " + ("#ff3b30" if name == "alpha" else "#007aff") + "; }\n",
        "bundle.mjs": bundle,
    }
    for path, text in files.items():
        file = app / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(text)
    (root / "script.json").write_text(json.dumps({
        "name": "Hanlin NativeScript Package " + name.title() + " E2E",
        "version": "1.0.0", "hanlinAppID": "hanlin.nativescript.package-" + name,
        "description": "Original NativeScript package/window/module/file/style/callback isolation.",
        "entry": "nativescript/app/bundle.mjs", "runInApp": True, "hanlinRuntime": "hanlin-nativescript"
    }, indent=2) + "\n")
    destination = HERE / "Fixtures" / ("package-window-" + name + ".hanlinNativeScript")
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
        for file in sorted(root.rglob("*")):
            if file.is_file():
                info = zipfile.ZipInfo(file.relative_to(root).as_posix(), date_time=(2026, 11, 25, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o100644 << 16
                archive.writestr(info, file.read_bytes())
    print("Prepared original-engine independent package fixture: " + str(destination))
