const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'App.tsx'), 'utf8');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'script.json'), 'utf8'));
const client = fs.readFileSync(path.join(root, 'src/engines/sefaria/client.js'), 'utf8');
const transport = fs.readFileSync(path.join(root, 'src/engines/sefaria/nativeTransport.js'), 'utf8');

for (const component of [
  'List', 'Section', 'NavigationStack', 'NavigationLink',
  'NavigationDestination', 'Form', 'DisclosureGroup', 'LabeledContent',
  'ContentUnavailableView', 'Link'
]) {
  assert(new RegExp('\\b' + component + '\\b').test(app),
    component + ' native SwiftUI component is missing');
}

assert(!app.includes('<Searchable'), 'Root search must not swallow the native List');
assert(app.includes('<InputRow label={t(\'searchPrompt\')} value={query}'),
  'Visible native TextField must be part of the root List');
assert(app.includes('Hanlin Expo 1.1.2'), 'Visible version label must confirm package update');
assert(app.includes('<NavigationLink value={'),
  'Search results must be native navigable list rows');
assert(app.includes('<NavigationDestination value="settings">'),
  'Settings must navigate to native Form');
assert(app.includes('<NativeResultDetail group={group}'),
  'Result links must open native detail views');
assert(app.includes('<NativeSettings locale={locale}'),
  'Settings must use native Form');
assert(app.includes('setQuery(value);void search(value);'),
  'Quick examples must search, not only fill the native search field');
assert(!/\b(HStack|VStack|NativeCard|Chip|PillButton)\b/.test(app),
  'Hand-built HStack/VStack cards/chips must not be in the UI');
assert(!app.includes('textFieldStyle('),
  'A manually styled TextField cannot replace the native Searchable bar');
assert(client.includes('from "./nativeTransport.js"'),
  'Native iOS NSURLSession search transport must be preserved');
assert(!client.includes('executeRuntime('),
  'Search engine must not fall back to broken embedded Node fetch');
assert(transport.includes('NSURLSession.sharedSession.dataTaskWithRequestCompletionHandler('),
  'Native iOS URLSession must remain wired');
assert(manifest.version === '1.1.2');
assert.deepEqual(manifest.capabilities, ['ios-native-api', 'network']);

assert(!app.includes('<Toolbar') && !app.includes('<Menu'), 'Nested toolbar/menu wrapper must not be present');
assert(app.includes("import { View } from 'react-native';"), 'Restore working 1.0.3 React Native View host wrapper');
assert(app.includes('<Section title={locale===\'he\'?\'חיפוש\':\'Search\'}>'), 'Direct native List controls missing');
assert(app.includes("setActionStatus(locale==='he'?'לחיצה על בדיקת חיבור התקבלה."), 'Connection button must expose synchronous event acknowledgement');
assert(!app.includes('Alternative search field'), 'Redundant fallback must be removed');
assert(app.includes('void checkConnection();'), 'Connection button must run diagnostic request');
assert(app.includes('void search(query);'), 'Direct native List button must perform search');
console.log('PASS: direct native List root with visible TextField, action buttons and navigation');
console.log('PASS: no HStack/VStack/custom cards; iOS URLSession preserved');
