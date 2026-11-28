import {File, Label, Page, StackLayout} from '@nativescript/core';
import {registerWindowFactory} from '@hanlin/window-factory';
import {receivedList, type JSONValue} from './proof';

const appID = 'hanlin.shortcutlists.nativescript';
registerWindowFactory(({id, environment, services: host, storage}) => {
  if (!storage.state) throw new Error('The current native window has no private state directory.');
  const page = new Page();
  const body = new StackLayout(); body.padding = 20;
  const title = new Label(); title.text = appID; title.automationText = 'native-lists-ready';
  title.textWrap = true; body.addChild(title); page.content = body;
  host.registerRequestHandler('native-lists.echo', 'inter-app.share', async ({caller, parameters}) => {
    const values = receivedList(parameters);
    const nonce = Date.now().toString(36) + '-' + Math.random().toString(36).slice(2);
    const statePath = storage.state + '/native-list-' + nonce + '.json';
    if (!/^[a-z0-9]+-[a-z0-9]+$/.test(nonce) || File.exists(statePath)) {
      throw new Error('A fresh invocation-owned evidence file is required.');
    }
    const result = {
      schema: 1, appID, actionID: 'native-lists.echo', nonce, caller,
      values, observedTypes: values.map(value => typeof value),
      windowID: id, statePath,
      executionMode: environment.HANLIN_EXECUTION_MODE ?? 'foreground',
      attached: title.ios?.window != null, observedAt: new Date().toISOString()
    };
    await File.fromPath(statePath).writeText(JSON.stringify(result));
    return JSON.parse(JSON.stringify(result)) as JSONValue;
  });
  return page;
});
