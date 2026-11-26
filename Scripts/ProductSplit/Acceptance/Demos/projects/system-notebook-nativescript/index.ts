import {Application, Button, File, Label, Page, ScrollView, StackLayout, TextView} from '@nativescript/core';
import {createNotebook, notificationForCapture, type NotebookState} from './notebook';
import {scheduleNativeNotice} from './native-notification';

// Existing public Objective-C selectors from HanlinNativeServicesBridge.h. No new bridge API is declared.
declare const HanlinNativeServicesBridge: {
  activeSessionBridge(): {
    stateDirectory(): string | null;
    documentsDirectory(): string | null;
    registerRequestHandlerCapabilityHandler(action: string, capability: string,
      handler: (caller: string, payloadJSON: string, reply: (result: string | null, error: string | null) => void) => void): void;
  } | null;
};
const appID = 'hanlin.demo.system.nativescript';
const bridge = HanlinNativeServicesBridge.activeSessionBridge();
if (!bridge) throw new Error('No actual NativeScript Host session.');
const stateDirectory = bridge.stateDirectory();
const documents = bridge.documentsDirectory();
if (!stateDirectory || !documents) throw new Error('The session did not expose its own storage areas.');
const statePath = stateDirectory + '/system-notebook.json';
const notebook = createNotebook({appID,
  read: () => File.exists(statePath) ? File.fromPath(statePath).readText() : Promise.resolve(null),
  write: text => File.fromPath(statePath).writeText(text),
  readCapture: async file => {
    const data = NSData.dataWithContentsOfFile(documents + '/' + file.path);
    if (!data) throw new Error('The delivered JPEG is not readable in this package Documents area.');
    return data.length;
  }
});
for (const [name, handler] of [['spotlight.open', notebook.spotlight], ['capture.receive', notebook.capture],
  ['notification.open', notebook.notification]] as const) {
  bridge.registerRequestHandlerCapabilityHandler(name, 'inter-app.share', (_caller, raw, reply) => {
    let input: unknown;
    try { input = JSON.parse(raw); } catch (error) { reply(null, String(error)); return; }
    void handler(input).then(value => reply(JSON.stringify(value), null), error => reply(null, String(error)));
  });
}
function createPage(): Page {
  const page = new Page(); const scroll = new ScrollView(); const body = new StackLayout(); body.padding = 20;
  const label = (text: string, id?: string) => { const view = new Label(); view.text = text; view.textWrap = true; view.marginBottom = 10;
    if (id) view.automationText = id; body.addChild(view); return view; };
  label('מחברת המערכת — NativeScript').fontSize = 24;
  const counts = label('טוען נתונים שנשמרו…', 'system-surface-counts');
  const action = label('טרם התקבלה פעולה.');
  label('Spotlight: חפשו את שם החבילה ולחצו על התוצאה. צילום: בחרו בחבילה בפרטי החבילה → Camera, צלמו והמשיכו ליישום.');
  const captured = label('טרם נמסר צילום.');
  label('מקלדת: הפעילו את המקלדת של Hanlin בהגדרות iOS, בחרו בחבילה והקלידו בשדה הבא.');
  const editor = new TextView(); editor.hint = 'טקסט להקלדה באמצעות המקלדת'; editor.height = 120;
  editor.automationText = 'system-keyboard-document'; body.addChild(editor);
  const schedule = new Button(); schedule.text = 'יצירת התראה עשירה בעוד 10 שניות'; schedule.isEnabled = false; body.addChild(schedule);
  label('לאחר התזמון עברו לרקע. לחיצה ממושכת על ההתראה מציגה את התוכן המקורי; ״המשך במחברת״ ממשיך לפעולה המוצהרת.');
  const refresh = new Button(); refresh.text = 'רענון הנתונים שנשמרו'; body.addChild(refresh);
  const status = label('כאן מוצגים רק נתונים שהתקבלו בפועל.', 'system-surface-status');
  let current: NotebookState | undefined;
  const update = (state: NotebookState) => { current = state; counts.text = `Spotlight: ${state.spotlightCount} · צילום: ${state.captureCount} · התראה: ${state.notificationCount}`;
    action.text = state.lastMessage; captured.text = state.lastCapture ? JSON.stringify(state.lastCapture, null, 2) : 'טרם נמסר צילום.';
    schedule.isEnabled = state.lastCapture !== null; };
  const stop = notebook.observe(update); page.on(Page.unloadedEvent, stop);
  const perform = (operation: () => Promise<unknown>) => { schedule.isEnabled = false; refresh.isEnabled = false;
    void operation().then(value => { status.text = JSON.stringify(value); }, error => { status.text = String(error); })
      .finally(() => { schedule.isEnabled = current?.lastCapture != null; refresh.isEnabled = true; }); };
  schedule.on(Button.tapEvent, () => perform(async () => {
    const capture = current?.lastCapture;
    if (!capture) throw new Error('תחילה העבירו צילום כדי לקבל את זהות ההתקנה האמיתית.');
    const request = notificationForCapture(appID, capture);
    return scheduleNativeNotice(request.id, request.userInfoJSON);
  }));
  refresh.on(Button.tapEvent, () => perform(() => notebook.read()));
  void notebook.read().catch(error => { status.text = String(error); });
  scroll.content = body; page.content = scroll; return page;
}
const executionMode = NSProcessInfo.processInfo.environment.objectForKey('HANLIN_EXECUTION_MODE');
if (String(executionMode) !== 'headless-action') Application.run({create: createPage});
