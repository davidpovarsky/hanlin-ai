import React, {useEffect, useState} from 'react';
import {Button, ScrollView, Text} from 'react-native';
import {hostServices, type MiniAppJSONValue} from '@hanlin/expo-ui';
import {createLongRunningProof, emptyState, statusLine, type PreparedState} from './proof';

const appID = 'hanlin.longrunning.expo';
const filename = 'surface-proof.json';
async function write(name: string, text: string): Promise<void> {
  const ascii = text.replace(/[\u007f-\uffff]/g,
    value => '\\u' + value.charCodeAt(0).toString(16).padStart(4, '0'));
  const result = await hostServices.writeFile(name,
    Uint8Array.from(ascii, value => value.charCodeAt(0)), 'state');
  if (!result.ok) throw new Error('The actual private state write failed.');
}
const proof = createLongRunningProof({
  appID,
  executeRuntime: (kind, source, options) => hostServices.executeRuntime(kind, source, options),
  reportProgress: async value => { await hostServices.miniapps.reportShortcutProgress(value); },
  readText: async () => {
    const bytes = await hostServices.readFile(filename, 'state');
    return bytes === null ? null : Array.from(bytes, value => String.fromCharCode(value)).join('');
  },
  writeText: text => write(filename, text),
  writeInvocation: async (name, text) => {
    if (!/^surface-invocation-[a-z0-9-]+\.json$/.test(name)) throw new Error('Invalid journal filename.');
    await write(name, text);
  }
});
let registrationError = '';
void hostServices.actions.register({
  'surface.run': async invocation => JSON.parse(JSON.stringify(
    await proof.run(invocation.parameters, {id: invocation.id, caller: invocation.caller})
  )) as MiniAppJSONValue
}).catch(error => { registrationError = String(error); console.error(registrationError); });

export default function App() {
  const [state, setState] = useState<PreparedState>(emptyState(appID));
  const [message, setMessage] = useState('Prepare a fresh challenge, then run the saved system Shortcut.');
  const [busy, setBusy] = useState(false);
  useEffect(() => { void proof.read().then(setState, error => setMessage(String(error))); }, []);
  const prepare = async () => {
    setBusy(true);
    try { setState(await proof.prepare()); setMessage('Challenge saved in actual private Host storage.'); }
    catch (error) { setMessage('ERROR: ' + String(error)); }
    finally { setBusy(false); }
  };
  return <ScrollView contentContainerStyle={{padding: 20, gap: 12}}>
    <Text accessibilityRole="header" style={{fontSize: 24}}>Long Running Expo</Text>
    <Text testID="long-running-status">{statusLine(state)}</Text>
    <Text>State file: state/surface-proof.json (canonical private Host storage)</Text>
    <Text>35 real runtime calls with 34 ten-second pacing intervals. Pacing is not CPU or network work.</Text>
    <Button title="Prepare challenge" testID="long-running-prepare" disabled={busy} onPress={() => void prepare()}/>
    <Text>{message}</Text>
    <Text>{registrationError ? 'ERROR: ' + registrationError : 'Original action registration requested.'}</Text>
  </ScrollView>;
}
