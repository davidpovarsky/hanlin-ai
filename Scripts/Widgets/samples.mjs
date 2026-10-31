const json = value => JSON.stringify(value, null, 2) + '\n';
const families = ['systemSmall', 'systemMedium', 'systemLarge', 'systemExtraLarge'];
const metadata = (actions, sourceFormat = 'jsx') => ({ abiVersion: 1, sourceFormat, families, actions });
const manifest = (name, engine, actions, entry = 'widget.jsx') => ({ name, version: '1.0.0', entry, kind: 'widget', widgetEngine: engine,
  hanlinRuntime: engine === 'expo' ? 'hanlin-expo' : 'scripting-jsc', hanlinWidget: metadata(actions, entry.endsWith('.tsx') ? 'tsx' : 'jsx') });
const expoPackage = name => json({ name, version: '1.0.0', hanlinRuntime: 'hanlin-expo',
  hanlinExpo: { runtimeVersion: '58.0.3', plugins: { '@expo/ui': '58.0.3' } },
  dependencies: { '@expo/ui': '58.0.3', 'expo-widgets': '58.0.3', react: '19.3.0' } });
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jBqkAAAAASUVORK5CYII=', 'base64');
const counterActions = ['increment', 'decrement', 'status'].map(id => ({ id, kind: 'expoCallback' }));
const scriptActions = [{ id: 'sync', kind: 'function', handler: 'syncNow' }, { id: 'backup', kind: 'setValue', stateKey: 'backup' },
  { id: 'named', kind: 'function', handler: 'setStatus' }, { id: 'reload', kind: 'reload' }];

export const widgetSamples = [
  { name: 'Hanlin-Expo-Widget-Counter', extension: 'hanlinExpo', engine: 'expo', expected: 'IMPORT_AND_NATIVE_TEST_REQUIRED', files: {
    'script.json': json(manifest('Expo Counter Widget', 'expo', counterActions, 'widget.tsx')),
    'package.json': expoPackage('hanlin-expo-widget-counter'),
    'widget.tsx': `import { VStack, HStack, Text, Button } from '@expo/ui/swift-ui';
import { padding, font } from '@expo/ui/swift-ui/modifiers';
export default function Counter(props: { count?: number; status?: string }) {
  'widget';
  const count = props.count ?? 7;
  return <VStack spacing={4} modifiers={[padding({all: 6}), font({textStyle: 'caption'})]}>
    <HStack><Text>Expo Counter</Text><Text modifiers={[font({size: 28})]}>{String(count)}</Text></HStack>
    <Text>{props.status ?? 'Ready'}</Text>
    <HStack><Button label="Increment +1" target="increment" onPress={() => ({count: count + 1})}/>
    <Button label="Decrement -1" target="decrement" onPress={() => ({count: count - 1})}/></HStack>
    <Button label="Set custom status" target="status" onPress={() => ({status: 'Source callback ran', trace: 'status-handler'})}/>
  </VStack>;
}\n`
  } },
  { name: 'Hanlin-Expo-Widget-Visuals', extension: 'hanlinExpo', engine: 'expo', expected: 'IMPORT_AND_NATIVE_TEST_REQUIRED', files: {
    'script.json': json(manifest('Expo Visuals Widget', 'expo', [{ id: 'overlay', kind: 'expoCallback' }])),
    'package.json': expoPackage('hanlin-expo-widget-visuals'),
    'widget.jsx': `import { VStack, Text, Overlay, Background, Mask, Circle, Rectangle, Gauge, Chart, Image, Link, Button } from '@expo/ui/swift-ui';
import { frame, foregroundStyle } from '@expo/ui/swift-ui/modifiers';
export default function Visuals(props) {
 'widget';
 return <VStack spacing={4}>
  <Background><Text>Expo <Text modifiers={[foregroundStyle('blue')]}>native slots</Text></Text><Background.Content><Rectangle modifiers={[foregroundStyle('#e4f3ff')]}/></Background.Content></Background>
  <Overlay><Text>{props.label ?? 'Base content'}</Text><Overlay.Content><Button label="Overlay action" target="overlay" onPress={() => ({label:'Overlay callback'})}/></Overlay.Content></Overlay>
  <Mask><Rectangle modifiers={[frame({width:50,height:30})]}/><Mask.Content><Circle/></Mask.Content></Mask>
  <Gauge value={0.7} min={0} max={1} currentValueLabel={<Text>70%</Text>}><Text>Progress</Text></Gauge>
  <Chart type="bar" data={[{x:'A',y:3},{x:'B',y:7}]} modifiers={[frame({height:60})]}/>
  <Image systemName="book.fill"/><Link destination="https://example.com"><Text>Open link</Text></Link>
 </VStack>;
}\n`
  } },
  { name: 'Hanlin-ScriptWidget-Dashboard', extension: 'scripting', engine: 'scriptwidget', expected: 'IMPORT_AND_NATIVE_TEST_REQUIRED', files: {
    'script.json': json(manifest('ScriptWidget Dashboard', 'scriptwidget', [])), 'assets/pixel.png': png,
    'widget.jsx': `function Heading({children}) { return <text font="headline">{children}</text>; }
$render(<vstack spacing="6"><Heading>ScriptWidget Dashboard</Heading>
 <hgrid columns={JSON.stringify([{type:'flexible'},{type:'flexible'}])}><badge text="Native"/><chip text="JSX"/></hgrid>
 <vgrid columns={JSON.stringify([{type:'flexible'},{type:'flexible'}])}><stat title="Lessons" value="7"/><ring value="0.7" frame="32"/></vgrid>
 <image name="assets/pixel.png" frame="24"/><date date={Date.parse('2026-10-30T12:00:00Z')} style="date"/>
 <chart type="bar" data={JSON.stringify([{label:'A',value:3},{label:'B',value:7}])} frame="80"/>
</vstack>);\n`
  } },
  { name: 'Hanlin-ScriptWidget-Actions', extension: 'scripting', engine: 'scriptwidget', expected: 'IMPORT_AND_NATIVE_TEST_REQUIRED', files: {
    'script.json': json(manifest('ScriptWidget Actions', 'scriptwidget', scriptActions)),
    'widget.jsx': `function syncNow() { $storage.set('syncCount', ($storage.get('syncCount') ?? 0) + 1); }
function setStatus() { $storage.set('status', 'Named source function ran'); }
$render(<vstack spacing="2"><hstack spacing="4"><text font="caption">ScriptWidget Actions</text><text font="caption">{String($storage.get('syncCount') ?? 0)}</text></hstack>
 <text font="caption">{$storage.get('status') ?? 'Ready'}</text>
 <hstack spacing="4"><button actionID="sync"><text font="caption">Sync now</text></button>
 <button onClick="setStatus"><text font="caption">Named function</text></button></hstack>
 <toggle on={$storage.get('backup') ?? false} actionID="backup" stateKey="backup"><text>Backup</text></toggle>
 <button action="reload"><text>Reload</text></button>
</vstack>);\n`
  } },
  { name: 'Hanlin-Mixed-Native-Widget', extension: 'hanlinExpo', engine: 'expo', expected: 'DEFERRED_OPTIONAL', files: {
    'script.json': json({ ...manifest('Mixed subtree — deferred', 'expo', []), hanlinWidget: { ...metadata([]), abiVersion: 0 } }),
    'package.json': expoPackage('hanlin-mixed-native-widget'),
    'widget.jsx': `export default function Deferred(){ 'widget'; throw new Error('Mixed native subtree ABI is deferred'); }`,
    'README.txt': 'DEFERRED_OPTIONAL: no mixed-subtree ABI is registered. Import must reject ABI 0. This archive is not evidence for either standalone engine.\n'
  } },
  { name: 'Hanlin-Widget-Legacy-Regression', extension: 'scripting', engine: 'legacy', expected: 'IMPORT_AND_NATIVE_TEST_REQUIRED', files: {
    'script.json': json({ name:'Widget Legacy Regression',version:'1.0.0',entry:'widget.json',kind:'widget',hanlinRuntime:'scripting-jsc' }),
    'widget.json': json({kind:'text',properties:{text:{type:'string',value:'Legacy HanlinScriptUINode Tree'}},children:[]})
  } },
  { name: 'Hanlin-Widget-Invalid-Cases', extension: 'hanlinExpo', engine: 'foowidget', expected: 'REJECT_IMPORT', files: {
    'script.json': json({...manifest('Invalid widget engine', 'expo', []),widgetEngine:'foowidget'}),
    'package.json': expoPackage('hanlin-widget-invalid-cases'), 'widget.jsx':'export default function Invalid(){ return <broken; }',
    'negative-cases.json': json(['unknown engine','invalid JSX','unsupported ABI','corrupt digest','stale generation','path traversal'])
  } }
];
