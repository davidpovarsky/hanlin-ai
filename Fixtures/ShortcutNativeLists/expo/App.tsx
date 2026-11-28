import React from 'react';
import {ScrollView, Text} from 'react-native';
import {hostServices, type MiniAppJSONValue} from '@hanlin/expo-ui';
import {receivedList} from './proof';

const appID = 'hanlin.shortcutlists.expo';
let registrationError = '';
void hostServices.actions.register({
  'native-lists.echo': async invocation => {
    const values = receivedList(invocation.parameters);
    const nonce = Date.now().toString(36) + '-' + Math.random().toString(36).slice(2);
    if (!/^[a-z0-9]+-[a-z0-9]+$/.test(nonce)) throw new Error('Invalid invocation nonce.');
    const stateFile = 'native-list-' + nonce + '.json';
    if (await hostServices.readFile(stateFile, 'state') !== null) {
      throw new Error('A fresh invocation-owned evidence file is required.');
    }
    const result = {
      schema: 1, appID, actionID: 'native-lists.echo', nonce, caller: invocation.caller,
      invocationID: invocation.id, stateFile, values,
      observedTypes: values.map(value => typeof value), observedAt: new Date().toISOString()
    };
    const ascii = JSON.stringify(result).replace(/[\u007f-\uffff]/g,
      value => '\\u' + value.charCodeAt(0).toString(16).padStart(4, '0'));
    const written = await hostServices.writeFile(stateFile,
      Uint8Array.from(ascii, value => value.charCodeAt(0)), 'state');
    if (!written.ok) throw new Error('The actual private state write failed.');
    return JSON.parse(JSON.stringify(result)) as MiniAppJSONValue;
  }
}).catch(error => { registrationError = String(error); console.error(registrationError); });

export default function App() {
  return <ScrollView contentContainerStyle={{padding: 20, gap: 12}}>
    <Text accessibilityRole="header">Native Lists Expo</Text>
    <Text testID="native-lists-ready">{appID}</Text>
    <Text>Actual action results are retained in this installed package's private State directory.</Text>
    <Text>{registrationError ? 'ERROR: ' + registrationError : 'Original action registration requested.'}</Text>
  </ScrollView>;
}
