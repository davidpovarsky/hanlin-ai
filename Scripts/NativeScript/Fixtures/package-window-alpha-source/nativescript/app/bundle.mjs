import { Page, StackLayout, Label, TextView, Button, File } from '@nativescript/core';
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
    input.text = context.inputs.filter(item => item.kind === 'text').map(item => item.text ?? '').join('\n');
    status.text = 'Ready';
  }).catch(error => { status.text = String(error.message ?? error); });
  return page;
});
