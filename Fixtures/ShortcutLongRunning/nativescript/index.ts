import {Button, File, Label, NativeWindowEvents, Page, ScrollView, StackLayout, Trace} from '@nativescript/core';
import {registerWindowFactory} from '@hanlin/window-factory';
import {createLongRunningProof, statusLine, type JSONValue} from './proof';

const appID = 'hanlin.longrunning.nativescript';
registerWindowFactory(({id, window, environment, services: host, storage}) => {
  if (!storage.state) throw new Error('The current native window has no private state directory.');
  const statePath = storage.state + '/surface-proof.json';
  let title: Label | undefined;
  let active: {token: string; nonce: string; journalFile: string} | undefined;
  // The original adapter emits this event only for an actual native close.
  // Observe it in this window's own storage; never request or synthesize close.
  window.on(NativeWindowEvents.close, () => {
    if (!active) return;
    const filename = 'long-running-close-' + active.token + '-' + active.nonce + '.json';
    try {
      File.fromPath(storage.state + '/' + filename).writeTextSync(JSON.stringify({
        schema: 1, event: 'close', appID, windowID: id, token: active.token,
        nonce: active.nonce, journalFile: active.journalFile,
        statePath: storage.state + '/' + filename, at: new Date().toISOString()
      }));
    } catch (error) {
      // A failed evidence write remains missing evidence; do not alter teardown.
      Trace.write('Long-running close observation failed: ' + String(error), Trace.categories.Error, Trace.messageType.error);
    }
  });
  const proof = createLongRunningProof({
    appID, executeRuntime: (kind, source, options) => host.executeRuntime(kind, source, options),
    readText: () => File.exists(statePath) ? File.fromPath(statePath).readText() : Promise.resolve(null),
    writeText: text => File.fromPath(statePath).writeText(text),
    writeInvocation: (name, text) => {
      if (!/^surface-invocation-[a-z0-9-]+\.json$/.test(name)) throw new Error('Invalid journal filename.');
      return File.fromPath(storage.state + '/' + name).writeText(text);
    },
    invocationStarted: value => {
      if (active) throw new Error('This window already admitted a real action.');
      active = value;
    },
    reportProgress: async value => { await host.miniapps.reportShortcutProgress(value); },
    samplePresentation: name => ({windowID: id, statePath: storage.state + '/' + name,
      executionMode: environment.HANLIN_EXECUTION_MODE ?? 'foreground', attached: title?.ios?.window != null})
  });
  const page = new Page();
  const body = new StackLayout(); body.padding = 20;
  const label = (text: string) => {
    const value = new Label(); value.text = text; value.textWrap = true;
    value.marginBottom = 10; body.addChild(value); return value;
  };
  title = label('Long Running NativeScript'); title.fontSize = 24;
  const status = label('Loading actual private state…'); status.automationText = 'long-running-status';
  label('State file: ' + statePath); label('Owner window: ' + id);
  label('35 real runtime calls with 34 ten-second pacing intervals. Pacing is not CPU or network work.');
  const message = label('Prepare a fresh challenge, then run the saved system Shortcut.');
  const prepare = new Button(); prepare.text = 'Prepare challenge'; prepare.automationText = 'long-running-prepare';
  prepare.on(Button.tapEvent, () => {
    prepare.isEnabled = false;
    void proof.prepare().then(value => {
      status.text = statusLine(value); message.text = 'Challenge saved in this native window.';
    }, error => { message.text = 'ERROR: ' + String(error); })
      .finally(() => { prepare.isEnabled = true; });
  });
  body.addChild(prepare);
  void proof.read().then(value => { status.text = statusLine(value); },
    error => { message.text = 'ERROR: ' + String(error); });
  const scroll = new ScrollView(); scroll.content = body; page.content = scroll;
  host.registerRequestHandler('surface.run', 'inter-app.share', async ({caller, parameters}) =>
    JSON.parse(JSON.stringify(await proof.run(parameters, {caller}))) as JSONValue);
  return page;
});
