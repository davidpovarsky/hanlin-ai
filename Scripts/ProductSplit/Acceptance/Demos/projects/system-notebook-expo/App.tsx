import React, {useEffect, useState} from 'react';
import {Button, ScrollView, Text, TextInput} from 'react-native';
import {hostServices} from '@hanlin/expo-ui';
import {init, runOnUI} from '@hanlin/expo-native-api';
import {createNotebook, emptyState, notificationForCapture, type NotebookState} from './notebook';
import {scheduleNativeNotice} from './native-notification';

const appID = 'hanlin.demo.system.expo';
const filename = 'system-notebook.json';
const notebook = createNotebook({appID,
  read: async () => { const bytes = await hostServices.readFile(filename, 'state');
    return bytes === null ? null : Array.from(bytes, value => String.fromCharCode(value)).join(''); },
  write: async text => {
    const ascii = text.replace(/[\u007f-\uffff]/g,
      value => '\\u' + value.charCodeAt(0).toString(16).padStart(4, '0'));
    const receipt = await hostServices.writeFile(filename, Uint8Array.from(ascii, value => value.charCodeAt(0)), 'state');
    if (!receipt.ok) throw new Error('Host state write was not acknowledged.');
  },
  readCapture: async file => {
    const bytes = await hostServices.readFile(file.path, file.area);
    if (bytes === null || bytes[0] !== 0xff || bytes[1] !== 0xd8) throw new Error('Saved capture is missing or not a JPEG.');
    return bytes.length;
  }
});
let registrationError = '';
void hostServices.actions.register({
  'spotlight.open': async invocation => ({...await notebook.spotlight(invocation.parameters)}),
  'capture.receive': async invocation => ({...await notebook.capture(invocation.parameters)}),
  'notification.open': async invocation => ({...await notebook.notification(invocation.parameters)})
}).catch(error => { registrationError = String(error); });

export default function App() {
  const [state, setState] = useState<NotebookState>(emptyState(appID));
  const [draft, setDraft] = useState('');
  const [message, setMessage] = useState('כאן מוצגים רק נתונים שהתקבלו בפועל.');
  const [busy, setBusy] = useState(false);
  useEffect(() => { const stop = notebook.observe(setState); void notebook.read().catch(error => setMessage(String(error))); return stop; }, []);
  const perform = async (operation: () => Promise<unknown>) => {
    setBusy(true); try { setMessage(JSON.stringify(await operation())); } catch (error) { setMessage(String(error)); } finally { setBusy(false); }
  };
  return <ScrollView contentContainerStyle={{padding: 20, gap: 12}}>
    <Text accessibilityRole="header" style={{fontSize: 24}}>מחברת המערכת — Expo</Text>
    <Text testID="system-surface-counts">Spotlight: {state.spotlightCount} · צילום: {state.captureCount} · התראה: {state.notificationCount}</Text>
    <Text>{state.lastMessage}</Text>
    <Text>Spotlight: חפשו את שם החבילה ולחצו על התוצאה. אין כאן כפתור שמדמה פעולה מהמערכת.</Text>
    <Text>צילום: בחרו בחבילה בפרטי החבילה → Camera, צלמו והמשיכו ליישום. הנתיבים למטה הם הקבצים שנקראו בפועל.</Text>
    <Text selectable>{state.lastCapture ? JSON.stringify(state.lastCapture, null, 2) : 'טרם נמסר צילום.'}</Text>
    <Text>מקלדת: הפעילו את המקלדת של Hanlin בהגדרות iOS, בחרו בחבילה ואז הקלידו כאן.</Text>
    <TextInput multiline value={draft} onChangeText={setDraft} placeholder="טקסט להקלדה באמצעות המקלדת"
      style={{minHeight: 100, borderWidth: 1, borderColor: '#999', padding: 10}} testID="system-keyboard-document"/>
    <Button title="יצירת התראה עשירה בעוד 10 שניות" disabled={busy || !state.lastCapture}
      onPress={() => void perform(async () => {
        if (!state.lastCapture) throw new Error('תחילה העבירו צילום כדי לקבל את זהות ההתקנה האמיתית.');
        if (!init()) throw new Error('Original Native API is unavailable; check the ios-native-api grant.');
        const request = notificationForCapture(appID, state.lastCapture);
        return runOnUI(scheduleNativeNotice, request.id, request.userInfoJSON);
      })}/>
    <Text>לאחר התזמון עברו לרקע. לחיצה ממושכת על ההתראה מציגה את התוכן המקורי; ״המשך במחברת״ מפעיל את הפעולה המוצהרת.</Text>
    <Button title="רענון הנתונים שנשמרו" disabled={busy} onPress={() => void perform(() => notebook.read())}/>
    <Text selectable testID="system-surface-status">{registrationError || message}</Text>
  </ScrollView>;
}
