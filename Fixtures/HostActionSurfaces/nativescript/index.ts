import {Button, File, Label, Page, ScrollView, StackLayout, TextView} from '@nativescript/core';
import {registerWindowFactory} from '@hanlin/window-factory';
import {createSurfaceProof, statusLine, type JSONValue, type SurfaceState} from './proof';

const appID = 'hanlin.surface.nativescript';

// This is the existing cooperating NativeScript window contract. Every handler
// retains its own services and state, including a headless Shortcuts invocation.
registerWindowFactory(({id, environment, services: host, storage}) => {
  if (!storage.state) throw new Error('The actual window has no canonical private state directory.');
  const statePath = storage.state + '/surface-proof.json';
  let observedRoot: Label | undefined;
  const proof = createSurfaceProof({
    appID, executeRuntime: (kind, source, options) => host.executeRuntime(kind, source, options),
    readText: () => File.exists(statePath) ? File.fromPath(statePath).readText() : Promise.resolve(null),
    writeText: text => File.fromPath(statePath).writeText(text),
    writeInvocation: (name, text) => {
      if (!/^surface-invocation-[a-z0-9-]+\.json$/.test(name)) throw new Error('Invalid observation filename.');
      return File.fromPath(storage.state + '/' + name).writeText(text);
    },
    acceptInputChallenge: true,
    reportProgress: async progress => { await host.miniapps.reportShortcutProgress(progress); },
    samplePresentation: (name = 'surface-proof.json') => ({
      windowID: id, statePath: storage.state + '/' + name,
      executionMode: environment.HANLIN_EXECUTION_MODE ?? 'foreground',
      attached: observedRoot?.ios?.window != null
    })
  });

function createPage(): Page {
  const page = new Page();
  const scroll = new ScrollView();
  const body = new StackLayout();
  body.padding = 20;
  const label = (text: string, id?: string) => {
    const view = new Label(); view.text = text; view.textWrap = true;
    if (id) view.automationText = id;
    view.marginBottom = 10; body.addChild(view); return view;
  };
  const title = label('Surface NativeScript'); title.fontSize = 24;
  observedRoot = title;
  const status = label('Loading actual private state…', 'surface-status');
  label('Installed Package / Generation: read the current published Hanlin catalog; not invented by this JavaScript app.');
  label('State file: ' + statePath);
  label('Owner window: ' + id);
  const message = label('Ready. Prepare a fresh challenge before a real system-surface attempt.', 'surface-message');
  const activity = label('Live Activity: not started', 'surface-activity-status');
  const resultView = new TextView();
  resultView.editable = false;
  resultView.height = 260;
  resultView.automationText = 'surface-result';
  const update = (state: SurfaceState) => {
    status.text = statusLine(state);
    resultView.text = 'Last result JSON: ' + JSON.stringify(state.lastResult);
  };
  proof.observe(update);
  void proof.read().catch(error => { message.text = String(error); });
  const buttons: Button[] = [];
  const button = (text: string, id: string, operation: () => Promise<unknown>) => {
    const view = new Button(); view.text = text; view.automationText = id;
    view.on(Button.tapEvent, () => {
      for (const item of buttons) item.isEnabled = false;
      void operation().then(value => { message.text = JSON.stringify(value); },
        error => { message.text = 'ERROR: ' + String(error); })
        .finally(() => { for (const item of buttons) item.isEnabled = true; });
    });
    buttons.push(view); body.addChild(view);
  };
  button('Prepare challenge', 'surface-prepare', () => proof.prepare());
  button('Widget setup', 'surface-widget', async () => ({
    renderer: 'original ScriptWidget',
    instruction: 'Normal installation declares the widget. Add Hanlin Script from the widget gallery, select Surface NativeScript, then tap Run NativeScript Surface.',
    note: 'This instruction is not a claim that the operating system placed or rendered a widget.'
  }));
  button('Start Live Activity', 'surface-start-activity', async () => {
    const current = await proof.read();
    if (!current.challenge) throw new Error('Prepare challenge first.');
    const enabled = await host.liveActivities.areEnabled();
    activity.text = 'Live Activity enabled: ' + enabled;
    if (!enabled) throw new Error('The actual ActivityKit authorization reports disabled.');
    try {
      const value = await host.liveActivities.start({
        scriptWidgetEntrypointID: 'widget', family: 'systemMedium', title: 'Surface NativeScript',
        state: {challenge: current.challenge, counter: current.counter}
      });
      await proof.setActivityID(value.activityID);
      activity.text = 'Live Activity ID: ' + value.activityID + ' | enabled: true';
      return value;
    } catch (error) {
      activity.text = 'Live Activity start error: ' + String(error);
      throw error;
    }
  });
  button('End Live Activity', 'surface-end-activity', async () => {
    const current = await proof.read();
    if (!current.activityID) return {ended: false, reason: 'No activity ID was returned to this proof app.'};
    const value = await host.liveActivities.end(current.activityID, {dismissAfterSeconds: 0});
    if (!value.ok) throw new Error('ActivityKit did not confirm the end request.');
    await proof.setActivityID(null);
    activity.text = 'Live Activity: ended ' + current.activityID;
    return value;
  });
  button('Run all five runtimes', 'surface-run', () =>
    proof.run({surface: 'foreground', fixture: appID}, {caller: 'proof-ui'}));
  button('Read last result', 'surface-read', () => proof.read());
  body.addChild(resultView);
  scroll.content = body; page.content = scroll;
  return page;
}
  const page = createPage();
  host.registerRequestHandler('surface.run', 'inter-app.share', async ({caller, parameters}) =>
    JSON.parse(JSON.stringify(await proof.run(parameters, {caller}))) as JSONValue);
  return page;
});
