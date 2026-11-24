import { Page, StackLayout, Label, TextView, Button } from '@nativescript/core';
import { registerWindowFactory } from '@hanlin/window-factory';

registerWindowFactory(({id, services}) => {
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
  let increments = 0;
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
    const text = input.text ?? '';
    const metadata = {windowSessionID: id, requestID: request.text, documentID, counter: String(increments)};
    prepared = () => services.miniapps.complete({
      operation: 'replaceSelection', items: [{kind: 'text', text}],
      metadata
    });
    status.text = 'Prepared';
  });
  const complete = button('Return', 'hanlin-ns-window-return', () => {
    if (!prepared) { status.text = 'Prepare first'; return; }
    const ownCompletion = prepared;
    Promise.resolve().then(ownCompletion).then(() => { status.text = 'Returned'; })
      .catch(error => { status.text = String(error.message ?? error); });
  });
  for (const child of [request, input, status, counter, increment, prepare, complete]) layout.addChild(child);
  page.content = layout;
  services.miniapps.getContext().then(context => {
    request.text = context.id;
    documentID = context.source.documentID ?? '';
    input.text = context.inputs.filter(item => item.kind === 'text').map(item => item.text ?? '').join('\n');
    status.text = 'Ready';
  }).catch(error => { status.text = String(error.message ?? error); });
  return page;
});
