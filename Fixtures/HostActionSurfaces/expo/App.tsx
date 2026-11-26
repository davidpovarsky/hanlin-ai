import React, {useEffect, useState} from 'react';
import {Button, ScrollView, Text, View} from 'react-native';
import {hostServices, type MiniAppJSONValue, type NativeSurfaceNode} from '@hanlin/expo-ui';
import {createSurfaceProof, emptyState, statusLine, type SurfaceState} from './proof';

const appID = 'hanlin.surface.expo';
const filename = 'surface-proof.json';
const proof = createSurfaceProof({
  appID, executeRuntime: (kind, source, options) => hostServices.executeRuntime(kind, source, options),
  readText: async () => {
    const bytes = await hostServices.readFile(filename, 'state');
    return bytes === null ? null : Array.from(bytes, value => String.fromCharCode(value)).join('');
  },
  writeText: async text => {
    // ASCII JSON preserves every Unicode code unit without a separate encoder
    // dependency in the actual embedded Hermes runtime.
    const ascii = text.replace(/[\u007f-\uffff]/g,
      value => '\\u' + value.charCodeAt(0).toString(16).padStart(4, '0'));
    const receipt = await hostServices.writeFile(filename,
      Uint8Array.from(ascii, value => value.charCodeAt(0)), 'state');
    if (!receipt.ok) throw new Error('The actual Host state write did not succeed.');
  }
});
let registrationError = '';
void hostServices.actions.register({
  'surface.run': async invocation => JSON.parse(JSON.stringify(
    await proof.run(invocation.parameters, {id: invocation.id, caller: invocation.caller})
  )) as MiniAppJSONValue
}).catch(error => { registrationError = String(error); console.error(registrationError); });

function activityRoot(challenge: string): NativeSurfaceNode {
  // Existing shared native-node ActivityKit renderer, not the separate
  // original expo-widgets callback API.
  const button: NativeSurfaceNode = {kind: 'button', properties: {
    title: 'Run Expo Surface',
    intent: {__hanlinAppIntent: true, name: 'surface.run',
      parameters: {surface: 'liveActivity', fixture: appID, shownChallenge: challenge}}
  }, children: [{kind: 'text', properties: {text: 'Run Expo Surface'}}]};
  return {kind: 'liveActivityUI', children: [
    {kind: 'liveActivityContent', children: [{kind: 'vStack', children: [
      {kind: 'text', properties: {text: 'Surface Expo'}},
      {kind: 'text', properties: {text: 'Challenge: ' + challenge}}, button
    ]}]},
    {kind: 'liveActivityCompactLeading', children: [{kind: 'text', properties: {text: 'Expo'}}]},
    {kind: 'liveActivityCompactTrailing', children: [{kind: 'text', properties: {text: '5'}}]},
    {kind: 'liveActivityMinimal', children: [{kind: 'text', properties: {text: '5'}}]},
    {kind: 'liveActivityExpandedBottom', children: [button]}
  ]};
}

export default function App() {
  const [state, setState] = useState<SurfaceState>(emptyState(appID));
  const [message, setMessage] = useState('Ready. Prepare a fresh challenge before a real system-surface attempt.');
  const [activityStatus, setActivityStatus] = useState('Live Activity: not started');
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    const stop = proof.observe(setState);
    void proof.read().catch(error => setMessage(String(error)));
    return stop;
  }, []);
  const perform = async (operation: () => Promise<unknown>) => {
    setBusy(true);
    try { const value = await operation(); setMessage(JSON.stringify(value)); }
    catch (error) { setMessage('ERROR: ' + String(error)); }
    finally { setBusy(false); }
  };
  const startActivity = async () => {
    const current = await proof.read();
    if (!current.challenge) throw new Error('Prepare challenge first.');
    const enabled = await hostServices.liveActivities.areEnabled();
    setActivityStatus('Live Activity enabled: ' + enabled);
    if (!enabled) throw new Error('The actual ActivityKit authorization reports disabled.');
    try {
      const result = await hostServices.liveActivities.start({
        title: 'Surface Expo', root: activityRoot(current.challenge),
        state: {challenge: current.challenge, counter: current.counter}, actionEntrypointID: 'surface-intent'
      });
      await proof.setActivityID(result.activityID);
      setActivityStatus('Live Activity ID: ' + result.activityID + ' | enabled: true');
      return result;
    } catch (error) {
      setActivityStatus('Live Activity start error: ' + String(error));
      throw error;
    }
  };
  const endActivity = async () => {
    const current = await proof.read();
    if (!current.activityID) return {ended: false, reason: 'No activity ID was returned to this proof app.'};
    const result = await hostServices.liveActivities.end(current.activityID, {dismissAfterSeconds: 0});
    if (!result.ok) throw new Error('ActivityKit did not confirm the end request.');
    await proof.setActivityID(null);
    setActivityStatus('Live Activity: ended ' + current.activityID);
    return result;
  };
  return <ScrollView contentContainerStyle={{padding: 20, gap: 12}}>
    <Text accessibilityRole="header" style={{fontSize: 24}}>Surface Expo</Text>
    <Text testID="surface-status">{statusLine(state)}</Text>
    <Text>Installed Package / Generation: read the current published Hanlin catalog; not invented by this JavaScript app.</Text>
    <Text>State file: state/surface-proof.json (canonical private Host storage)</Text>
    <Button title="Prepare challenge" testID="surface-prepare" disabled={busy}
      onPress={() => void perform(() => proof.prepare())}/>
    <Button title="Publish widget" testID="surface-widget" disabled={busy}
      onPress={() => void perform(async () => {
        const current = await proof.read();
        return hostServices.publishWidget({engine: 'expo', entrypointID: 'widget',
          props: {challenge: current.challenge, counter: current.counter, title: 'Surface Expo'}});
      })}/>
    <Text>Widget gallery configuration: Surface Expo; visible action: Run Expo Surface.</Text>
    <Button title="Start Live Activity" testID="surface-start-activity" disabled={busy}
      onPress={() => void perform(startActivity)}/>
    <Button title="End Live Activity" testID="surface-end-activity" disabled={busy}
      onPress={() => void perform(endActivity)}/>
    <Text testID="surface-activity-status">{activityStatus}</Text>
    <Button title="Run all five runtimes" testID="surface-run" disabled={busy}
      onPress={() => void perform(() => proof.run({surface: 'foreground', fixture: appID}, {caller: 'proof-ui'}))}/>
    <Button title="Read last result" testID="surface-read" disabled={busy}
      onPress={() => void perform(() => proof.read())}/>
    <Text selectable testID="surface-message">{registrationError ? 'Action registration error: ' + registrationError : message}</Text>
    <View><Text selectable testID="surface-result">Last result JSON: {JSON.stringify(state.lastResult)}</Text></View>
  </ScrollView>;
}
