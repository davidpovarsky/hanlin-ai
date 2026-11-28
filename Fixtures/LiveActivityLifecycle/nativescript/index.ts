import {Button, File, Label, Page, ScrollView, StackLayout, TextField, TextView} from '@nativescript/core';
import {registerWindowFactory} from '@hanlin/window-factory';

type JSONValue = null | boolean | number | string | JSONValue[] | {[key: string]: JSONValue};
type Slot = 'A' | 'B';
type ActivityProps = {runUUID: string; slot: Slot; submittedRevision: number};
type NativeCall = {
  method: string; requestedAtEpochMilliseconds: number;
  observedReturnAtEpochMilliseconds?: number; outcome?: 'returned' | 'rejected';
  result?: JSONValue; error?: string;
};
type Observation = {
  ordinal: number; operation: string; requestedAtEpochMilliseconds: number;
  completedAtEpochMilliseconds?: number; outcome?: 'returned' | 'rejected';
  calls: NativeCall[]; error?: string;
};
type SlotRecord = {activityID: string; submittedRevision: number; endRequestReturned: boolean};
type Journal = {
  schemaVersion: 1; engine: 'expo' | 'nativescript'; appID: string; runUUID: string;
  preparedAtEpochMilliseconds: number; listScope: string;
  storage: {area: 'state'; filename: string; literalStatePath?: string; ownerWindowID?: string};
  slots: {A: SlotRecord | null; B: SlotRecord | null};
  lastObservedIDs: string[]; observations: Observation[];
};

async function invoke<T>(
  observation: Observation, method: string, operation: () => T | Promise<T>,
  summarize?: (value: T) => JSONValue
): Promise<T> {
  const call: NativeCall = {method, requestedAtEpochMilliseconds: Date.now()};
  observation.calls.push(call);
  let value: T;
  try {
    value = await operation();
  } catch (error) {
    call.outcome = 'rejected';
    call.observedReturnAtEpochMilliseconds = Date.now();
    call.error = String(error);
    throw error;
  }
  call.outcome = 'returned';
  call.observedReturnAtEpochMilliseconds = Date.now();
  // A returned API is distinct from visible rendering or system dismissal.
  // Native objects are deliberately not serialized or replaced by guessed IDs.
  if (summarize) call.result = summarize(value);
  return value;
}

function checkedID(value: string): string {
  if (typeof value !== 'string' || value.length === 0 || value.length > 512)
    throw new Error('The original API did not return a bounded nonempty activity ID.');
  return value;
}

function checkedUUID(value: string): string {
  const normalized = value.trim().toLowerCase();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(normalized))
    throw new Error('Enter the fresh case UUID before Prepare challenge.');
  return normalized;
}

const appID = 'hanlin.activity.lifecycle.nativescript';
const filename = 'activity-lifecycle.json';

registerWindowFactory(({id, services: host, storage}) => {
  const stateDirectory = storage.state;
  if (!stateDirectory) throw new Error('The actual window has no canonical private State directory.');
  // Preserve the actual native storage representation, including a possible trailing separator.
  const statePath = stateDirectory + '/' + filename;
  let journal: Journal | null = null;
  let busy = false;

  const page = new Page();
  const scroll = new ScrollView();
  const body = new StackLayout();
  body.padding = 20;
  const label = (text: string, identifier?: string) => {
    const view = new Label();
    view.text = text; view.textWrap = true; view.marginBottom = 10;
    if (identifier) view.automationText = identifier;
    body.addChild(view);
    return view;
  };
  label('Original NativeScript Live Activity lifecycle').fontSize = 22;
  label('Actual installed owner/generation and rendered regions must be observed outside this fixture.');
  label('Fresh case UUID:');
  const challenge = new TextField();
  challenge.text = '';
  challenge.automationText = 'activity-lifecycle-challenge';
  body.addChild(challenge);
  const status = label('Run: not prepared', 'activity-lifecycle-status');
  const aID = label('Activity ID A: not returned', 'activity-lifecycle-a-id');
  const bID = label('Activity ID B: not returned', 'activity-lifecycle-b-id');
  const message = label('Enter a fresh case UUID; no activity has been started.', 'activity-lifecycle-message');
  const resultView = new TextView();
  resultView.editable = false; resultView.height = 220;
  resultView.automationText = 'activity-lifecycle-journal';
  const buttons: Button[] = [];

  const ready = (): Journal => {
    if (!journal) throw new Error('Prepare challenge first.');
    return journal;
  };
  const props = (slot: Slot, submittedRevision: number): ActivityProps => ({
    runUUID: ready().runUUID, slot, submittedRevision
  });
  const show = () => {
    status.text = 'Run: ' + (journal?.runUUID ?? 'not prepared');
    aID.text = 'Activity ID A: ' + (journal?.slots.A?.activityID ?? 'not returned');
    bID.text = 'Activity ID B: ' + (journal?.slots.B?.activityID ?? 'not returned');
    resultView.text = JSON.stringify(journal);
  };
  const perform = async (operation: string, operationBody: (observation: Observation) => Promise<void>) => {
    if (busy) return;
    busy = true;
    for (const item of buttons) item.isEnabled = false;
    message.text = 'RUNNING: ' + operation;
    const observation: Observation = {
      ordinal: (journal?.observations.length ?? 0) + 1,
      operation, requestedAtEpochMilliseconds: Date.now(), calls: []
    };
    try {
      try {
        await operationBody(observation);
        observation.outcome = 'returned';
      } catch (error) {
        observation.outcome = 'rejected';
        observation.error = String(error);
      }
      observation.completedAtEpochMilliseconds = Date.now();
      if (journal) {
        journal.observations.push(observation);
        show();
        try { await File.fromPath(statePath).writeText(JSON.stringify(journal)); }
        catch (error) {
          message.text = 'JOURNAL_WRITE_ERROR: ' + String(error);
          return;
        }
      }
      message.text = JSON.stringify(observation);
    } finally {
      busy = false;
      for (const item of buttons) item.isEnabled = true;
    }
  };
  const prepare = async (observation: Observation) => {
    if (journal) throw new Error('This foreground fixture already owns a run. Do not replace its activity IDs.');
    const runUUID = checkedUUID(challenge.text || '');
    const priorExists = await invoke(observation, 'File.exists(private State journal)', () => File.exists(statePath), value => value);
    if (priorExists) throw new Error('Existing private journal: use a fresh installation/session; this pilot does not claim restoration.');
    const initialIDs = await invoke(observation, 'host.liveActivities.list', () => host.liveActivities.list(), value => value);
    for (const value of initialIDs) checkedID(value);
    if (initialIDs.length !== 0) throw new Error('This installed owner already reports activities.');
    journal = {
      schemaVersion: 1, engine: 'nativescript', appID, runUUID, preparedAtEpochMilliseconds: Date.now(),
      listScope: 'Original current installed-owner ActivityKit list',
      storage: {area: 'state', filename, literalStatePath: statePath, ownerWindowID: id},
      slots: {A: null, B: null}, lastObservedIDs: initialIDs, observations: []
    };
  };
  const start = async (slot: Slot, observation: Observation) => {
    const current = ready();
    if (current.slots[slot]) throw new Error('This slot already has an actual activity.');
    if (slot === 'B' && (!current.slots.A || current.slots.A.endRequestReturned))
      throw new Error('Start A before Start B.');
    const enabled = await invoke(observation, 'host.liveActivities.areEnabled', () => host.liveActivities.areEnabled(), value => value);
    if (!enabled) throw new Error('The actual ActivityKit authorization reports disabled.');
    const value = await invoke(observation, 'host.liveActivities.start', () => host.liveActivities.start({
      scriptWidgetEntrypointID: 'widget', family: 'systemMedium',
      title: 'NativeScript lifecycle ' + slot, state: props(slot, 0)
    }), result => ({activityID: result.activityID}));
    const activityID = checkedID(value.activityID);
    current.slots[slot] = {activityID, submittedRevision: 0, endRequestReturned: false};
    const other = current.slots[slot === 'A' ? 'B' : 'A'];
    if (other?.activityID === activityID) throw new Error('Two starts returned the same ActivityKit ID.');
  };
  const list = async (observation: Observation) => {
    const current = ready();
    current.lastObservedIDs = await invoke(observation, 'host.liveActivities.list', () => host.liveActivities.list(), value => value);
    for (const value of current.lastObservedIDs) checkedID(value);
    if (new Set(current.lastObservedIDs).size !== current.lastObservedIDs.length)
      throw new Error('The original list returned duplicate activity IDs.');
  };
  const updateA = async (observation: Observation) => {
    const current = ready();
    const record = current.slots.A;
    if (!record || record.endRequestReturned || record.submittedRevision !== 0 ||
        !current.slots.B || current.slots.B.endRequestReturned)
      throw new Error('Update A requires both live case slots and the initial submitted revision.');
    const result = await invoke(observation, 'host.liveActivities.update', () => host.liveActivities.update(
      record.activityID, {state: props('A', 1)}
    ), value => ({ok: value.ok}));
    if (!result.ok) throw new Error('The original API did not confirm the update request.');
    record.submittedRevision = 1;
  };
  const end = async (slot: Slot, observation: Observation) => {
    const record = ready().slots[slot];
    if (!record || record.endRequestReturned) throw new Error('No unended case-owned slot is available.');
    const result = await invoke(observation, 'host.liveActivities.end', () => host.liveActivities.end(
      record.activityID, {dismissAfterSeconds: 0}
    ), value => ({ok: value.ok}));
    if (!result.ok) throw new Error('The original API did not confirm the end request.');
    record.endRequestReturned = true;
    // Keep the actual ID. Only a later actual List/system capture can show absence.
  };
  const button = (title: string, identifier: string, operation: string,
                  action: (observation: Observation) => Promise<void>) => {
    const view = new Button();
    view.text = title; view.automationText = identifier;
    view.on(Button.tapEvent, () => { void perform(operation, action); });
    buttons.push(view); body.addChild(view);
  };
  button('Prepare challenge', 'activity-lifecycle-prepare', 'prepare', prepare);
  button('Start A', 'activity-lifecycle-start-a', 'start-a', observation => start('A', observation));
  button('Start B', 'activity-lifecycle-start-b', 'start-b', observation => start('B', observation));
  button('List', 'activity-lifecycle-list', 'list', list);
  button('Update A', 'activity-lifecycle-update-a', 'update-a', updateA);
  button('End A', 'activity-lifecycle-end-a', 'end-a', observation => end('A', observation));
  button('End B', 'activity-lifecycle-end-b', 'end-b', observation => end('B', observation));
  body.addChild(resultView);
  label('Actual State journal: ' + statePath);
  label('Actual owner window: ' + id);
  scroll.content = body; page.content = scroll;
  return page;
});
