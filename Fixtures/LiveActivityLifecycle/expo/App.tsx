import React, {useRef, useState} from 'react';
import {Button, ScrollView, Text, TextInput} from 'react-native';
import {hostServices} from '@hanlin/expo-ui';
import {Text as WidgetText} from '@expo/ui/swift-ui';
import {accessibilityIdentifier, accessibilityLabel, accessibilityValue} from '@expo/ui/swift-ui/modifiers';
import {createLiveActivity, type LiveActivity, type LiveActivityEnvironment, type LiveActivityFactory} from 'expo-widgets';

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

const appID = 'hanlin.activity.lifecycle.expo';
const filename = 'activity-lifecycle.json';
const ActivityLayout = (props: ActivityProps, _environment: LiveActivityEnvironment) => {
  'widget';
  const region = (code: string) => {
    const marker = 'LA|' + props.runUUID + '|' + props.slot + '|' + code + '|R' + props.submittedRevision;
    return <WidgetText modifiers={[
      accessibilityIdentifier('activity-region-' + props.slot + '-' + code),
      accessibilityLabel(marker), accessibilityValue(marker)
    ]}>{props.slot + ' ' + code + ' ' + props.submittedRevision}</WidgetText>;
  };
  return {
    banner: region('banner'), compactLeading: region('compact-leading'),
    compactTrailing: region('compact-trailing'), minimal: region('minimal'),
    expandedLeading: region('expanded-leading'), expandedTrailing: region('expanded-trailing'),
    expandedCenter: region('expanded-center'), expandedBottom: region('expanded-bottom')
  };
};

export default function App() {
  const [challenge, setChallenge] = useState('');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('Enter a fresh case UUID; no activity has been started.');
  const [snapshot, setSnapshot] = useState<Journal | null>(null);
  const busyRef = useRef(false);
  const journal = useRef<Journal | null>(null);
  const factory = useRef<LiveActivityFactory<ActivityProps> | null>(null);
  const instances = useRef<{A: LiveActivity<ActivityProps> | null; B: LiveActivity<ActivityProps> | null}>({A: null, B: null});

  const ready = (): Journal => {
    if (!journal.current || !factory.current) throw new Error('Prepare challenge first.');
    return journal.current;
  };
  const props = (slot: Slot, submittedRevision: number): ActivityProps => ({
    runUUID: ready().runUUID, slot, submittedRevision
  });
  const persist = async (value: Journal) => {
    const ascii = JSON.stringify(value).replace(/[\u007f-\uffff]/g,
      character => '\\u' + character.charCodeAt(0).toString(16).padStart(4, '0'));
    const receipt = await hostServices.writeFile(filename,
      Uint8Array.from(ascii, character => character.charCodeAt(0)), 'state');
    if (!receipt.ok) throw new Error('The original private State journal write did not succeed.');
  };
  const perform = async (operation: string, body: (observation: Observation) => Promise<void>) => {
    if (busyRef.current) return;
    busyRef.current = true;
    setBusy(true);
    setMessage('RUNNING: ' + operation);
    const observation: Observation = {
      ordinal: (journal.current?.observations.length ?? 0) + 1,
      operation, requestedAtEpochMilliseconds: Date.now(), calls: []
    };
    try {
      try {
        await body(observation);
        observation.outcome = 'returned';
      } catch (error) {
        observation.outcome = 'rejected';
        observation.error = String(error);
      }
      observation.completedAtEpochMilliseconds = Date.now();
      const current = journal.current;
      if (current) {
        current.observations.push(observation);
        setSnapshot(JSON.parse(JSON.stringify(current)) as Journal);
        try { await persist(current); }
        catch (error) {
          setMessage('JOURNAL_WRITE_ERROR: ' + String(error));
          return;
        }
      }
      setMessage(JSON.stringify(observation));
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  };
  const prepare = async (observation: Observation) => {
    if (journal.current || factory.current || instances.current.A || instances.current.B)
      throw new Error('This foreground fixture already owns a run. Do not replace its activity IDs.');
    const runUUID = checkedUUID(challenge);
    const prior = await invoke(observation, 'host.readFile(state)', () => hostServices.readFile(filename, 'state'),
      value => ({exists: value !== null}));
    if (prior !== null) throw new Error('Existing private journal: use a fresh installation/session; this pilot does not claim restoration.');
    const created = await invoke(observation, 'createLiveActivity',
      () => createLiveActivity('HanlinActivityLifecycle.' + runUUID, ActivityLayout));
    const initialIDs = await invoke(observation, 'factory.getInstances/getId',
      () => created.getInstances().map(value => checkedID(value.getId())), value => value);
    if (initialIDs.length !== 0) throw new Error('The new original factory already reports activities.');
    factory.current = created;
    journal.current = {
      schemaVersion: 1, engine: 'expo', appID, runUUID, preparedAtEpochMilliseconds: Date.now(),
      listScope: 'Original owner-qualified factory for this exact run UUID',
      storage: {area: 'state', filename},
      slots: {A: null, B: null}, lastObservedIDs: initialIDs, observations: []
    };
  };
  const start = async (slot: Slot, observation: Observation) => {
    const current = ready();
    const original = factory.current;
    if (!original) throw new Error('The original factory is absent.');
    if (instances.current[slot] || current.slots[slot]) throw new Error('This slot already has an actual activity.');
    if (slot === 'B' && (!current.slots.A || current.slots.A.endRequestReturned))
      throw new Error('Start A before Start B.');
    const activity = await invoke(observation, 'factory.start', () => original.start(props(slot, 0)));
    // Retain the real object immediately, even if a later ID/journal observation fails.
    instances.current[slot] = activity;
    const activityID = checkedID(await invoke(observation, 'activity.getId', () => activity.getId(), value => value));
    current.slots[slot] = {activityID, submittedRevision: 0, endRequestReturned: false};
    const other = current.slots[slot === 'A' ? 'B' : 'A'];
    if (other?.activityID === activityID) throw new Error('Two starts returned the same ActivityKit ID.');
  };
  const list = async (observation: Observation) => {
    const current = ready();
    const original = factory.current;
    if (!original) throw new Error('The original factory is absent.');
    current.lastObservedIDs = await invoke(observation, 'factory.getInstances/getId',
      () => original.getInstances().map(value => checkedID(value.getId())), value => value);
    if (new Set(current.lastObservedIDs).size !== current.lastObservedIDs.length)
      throw new Error('The original list returned duplicate activity IDs.');
  };
  const updateA = async (observation: Observation) => {
    const current = ready();
    const record = current.slots.A;
    const activity = instances.current.A;
    if (!record || !activity || record.endRequestReturned || record.submittedRevision !== 0 ||
        !current.slots.B || current.slots.B.endRequestReturned)
      throw new Error('Update A requires both live case slots and the initial submitted revision.');
    const actualID = checkedID(await invoke(observation, 'activity.getId', () => activity.getId(), value => value));
    if (actualID !== record.activityID) throw new Error('The retained A object changed identity.');
    await invoke(observation, 'activity.update', () => activity.update(props('A', 1)));
    record.submittedRevision = 1;
  };
  const end = async (slot: Slot, observation: Observation) => {
    const current = ready();
    const record = current.slots[slot];
    const activity = instances.current[slot];
    if (!record || !activity || record.endRequestReturned) throw new Error('No unended case-owned slot is available.');
    const actualID = checkedID(await invoke(observation, 'activity.getId', () => activity.getId(), value => value));
    if (actualID !== record.activityID) throw new Error('The retained object changed identity.');
    await invoke(observation, "activity.end('immediate')", () => activity.end('immediate', props(slot, record.submittedRevision)));
    record.endRequestReturned = true;
    // Keep both ID and object. Only a later actual List/system capture can show absence.
  };
  return <ScrollView contentContainerStyle={{padding: 20, gap: 12}}>
    <Text accessibilityRole="header">Original Expo Live Activity lifecycle</Text>
    <Text>Actual installed owner/generation and rendered regions must be observed outside this fixture.</Text>
    <TextInput testID="activity-lifecycle-challenge" accessibilityLabel="Fresh case UUID"
      value={challenge} onChangeText={setChallenge} editable={!busy && snapshot === null}
      autoCapitalize="none" autoCorrect={false}/>
    <Button title="Prepare challenge" testID="activity-lifecycle-prepare" disabled={busy}
      onPress={() => void perform('prepare', prepare)}/>
    <Button title="Start A" testID="activity-lifecycle-start-a" disabled={busy}
      onPress={() => void perform('start-a', observation => start('A', observation))}/>
    <Button title="Start B" testID="activity-lifecycle-start-b" disabled={busy}
      onPress={() => void perform('start-b', observation => start('B', observation))}/>
    <Button title="List" testID="activity-lifecycle-list" disabled={busy}
      onPress={() => void perform('list', list)}/>
    <Button title="Update A" testID="activity-lifecycle-update-a" disabled={busy}
      onPress={() => void perform('update-a', updateA)}/>
    <Button title="End A" testID="activity-lifecycle-end-a" disabled={busy}
      onPress={() => void perform('end-a', observation => end('A', observation))}/>
    <Button title="End B" testID="activity-lifecycle-end-b" disabled={busy}
      onPress={() => void perform('end-b', observation => end('B', observation))}/>
    <Text testID="activity-lifecycle-status">Run: {snapshot?.runUUID ?? 'not prepared'}</Text>
    <Text testID="activity-lifecycle-a-id">Activity ID A: {snapshot?.slots.A?.activityID ?? 'not returned'}</Text>
    <Text testID="activity-lifecycle-b-id">Activity ID B: {snapshot?.slots.B?.activityID ?? 'not returned'}</Text>
    <Text selectable testID="activity-lifecycle-message">{message}</Text>
    <Text selectable testID="activity-lifecycle-journal">{JSON.stringify(snapshot)}</Text>
    <Text>State journal: {filename}, using original package-private Host state storage.</Text>
  </ScrollView>;
}
