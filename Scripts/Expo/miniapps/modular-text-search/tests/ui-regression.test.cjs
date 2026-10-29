const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'App.tsx'), 'utf8');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'script.json'), 'utf8'));
const client = fs.readFileSync(path.join(root, 'src/engines/sefaria/client.js'), 'utf8');
const transport = fs.readFileSync(path.join(root, 'src/engines/sefaria/nativeTransport.js'), 'utf8');

for (const component of [
  'Searchable', 'List', 'Section', 'NavigationStack', 'NavigationLink',
  'NavigationDestination', 'Form', 'DisclosureGroup', 'LabeledContent',
  'ContentUnavailableView', 'Menu', 'Toolbar', 'Link'
]) {
  assert(new RegExp('\\b' + component + '\\b').test(app),
    component + ' native SwiftUI component is missing');
}

assert(app.includes('<Searchable value={query} onValueChange={setQuery}'),
  'Native SwiftUI search input must be restored');
assert(app.includes('onSubmit={(submitted)=>{setQuery(submitted);void search(submitted);}}'),
  'Native search keyboard submit must run actual search with submitted text');
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
assert(manifest.version === '1.1.0');
assert.deepEqual(manifest.capabilities, ['ios-native-api', 'network']);

console.log('PASS: native Searchable submit, List rows, Navigation destinations, Form settings');
console.log('PASS: no HStack/VStack/custom cards; iOS URLSession preserved');
