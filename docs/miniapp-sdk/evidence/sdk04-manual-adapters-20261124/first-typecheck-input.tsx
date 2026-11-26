import React, { useState } from 'react';
import { View } from 'react-native';
import {
  Host, NavigationStack, VStack, List, Section, Text, Button, TextField,
  TextEditor, Searchable, Focused, LazyVGrid, LazyHGrid, ViewThatFits,
  SafeAreaInset, AsyncImage, Table, Sheet, FullScreenCover, PopoverPresentation, Inspector,
  type TableRow,
} from '@hanlin/expo-ui';
import {
  accessibilityIdentifier, accessibilityLabel, autocorrectionDisabled, textInputAutocapitalization,
  frame, fixedSize, navigationTitle,
} from '@hanlin/expo-ui/modifiers';

// The acceptance runner owns this loopback endpoint. It serves exact PNG bytes
// and a real HTTP 404; it never supplies adapter events or native results.
export const MANUAL_ADAPTER_IMAGE_ORIGIN = 'http://localhost:49173';

type Panel = 'menu' | 'input' | 'search' | 'layout' | 'table' | 'image'
  | 'Sheet' | 'FullScreenCover' | 'Popover' | 'Inspector';
type PresentationKind = 'Sheet' | 'FullScreenCover' | 'Popover';
const inputModifiers = [autocorrectionDisabled(true), textInputAutocapitalization('never')];

function InputPanel({ back }: { back: () => void }) {
  const [text, setText] = useState('');
  const [other, setOther] = useState('');
  const [focused, setFocused] = useState(false);
  const [focusEvents, setFocusEvents] = useState(0);
  return <VStack spacing={12}>
    <Text>INPUT_ADAPTERS</Text>
    <Button label="Focus manual editor" onPress={() => setFocused(true)} />
    <Focused isFocused={focused} onFocusedChange={value => {
      setFocused(value);
      setFocusEvents(count => count + 1);
    }}>
      <TextEditor value={text} onValueChange={setText} placeholder="Enter adapter text"
        modifiers={[...inputModifiers, frame({width: 360, height: 100}), accessibilityIdentifier('manual-editor')]} />
    </Focused>
    <TextField text={other} onTextChange={setOther} placeholder="Other native field"
      modifiers={[...inputModifiers, frame({width: 360}), accessibilityIdentifier('manual-other-field')]} />
    <Text>{'EDITOR_VALUE:' + text}</Text>
    <Text>{'FOCUS_VALUE:' + focused}</Text>
    <Text>{'FOCUS_EVENTS:' + focusEvents}</Text>
    <Button label="Reset editor from React" onPress={() => setText('Reset from React')} />
    <Button label="Adapter menu" onPress={back} />
  </VStack>;
}

function SearchPanel({ back }: { back: () => void }) {
  const [query, setQuery] = useState('');
  const [submits, setSubmits] = useState(0);
  const [submitted, setSubmitted] = useState('');
  const [actions, setActions] = useState(0);
  return <Searchable value={query} defaultPresented prompt="Manual adapter query"
    onValueChange={setQuery} onSubmit={value => {
      setSubmitted(value);
      setSubmits(count => count + 1);
    }}>
    <List>
      <Section title="Search adapter">
        <Text>MANUAL_SEARCH_CONTENT</Text>
        <Button label={'MANUAL_SEARCH_ACTIONS:' + actions} onPress={() => setActions(count => count + 1)} />
        <Text>{'MANUAL_QUERY:' + query}</Text>
        <Text>{'MANUAL_SUBMITS:' + submits}</Text>
        <Text>{'MANUAL_SUBMITTED:' + submitted}</Text>
        <Button label="Adapter menu" onPress={back} />
      </Section>
    </List>
  </Searchable>;
}

function LayoutPanel({ back }: { back: () => void }) {
  const [lastAction, setLastAction] = useState('none');
  const [wide, setWide] = useState(false);
  const [insetAtTop, setInsetAtTop] = useState(false);
  const [insetActions, setInsetActions] = useState(0);
  return <VStack spacing={12}>
    <SafeAreaInset edge={insetAtTop ? 'top' : 'bottom'} spacing={8}
      modifiers={[frame({width: 380, height: 510})]}
      inset={<Button label={'INSET_ACTIONS:' + insetActions} onPress={() => setInsetActions(count => count + 1)} />}>
      <VStack spacing={12}>
        <LazyVGrid tracks={[{size: 'fixed', value: 110}, {size: 'fixed', value: 110}]} spacing={8}
          modifiers={[frame({width: 260, height: 100})]}>
          {['V1', 'V2', 'V3', 'V4'].map(label =>
            <Button key={label} label={label} onPress={() => setLastAction(label)}
              modifiers={[frame({width: 100, height: 40})]} />)}
        </LazyVGrid>
        <LazyHGrid tracks={[{size: 'fixed', value: 44}, {size: 'fixed', value: 44}]} spacing={8}
          modifiers={[frame({width: 260, height: 100})]}>
          {['H1', 'H2', 'H3', 'H4'].map(label =>
            <Button key={label} label={label} onPress={() => setLastAction(label)}
              modifiers={[frame({width: 100, height: 40})]} />)}
        </LazyHGrid>
        <ViewThatFits axes="horizontal" modifiers={[frame({width: wide ? 360 : 160, height: 44})]}>
          <Button label="FIT_WIDE" onPress={() => setLastAction('wide')}
            modifiers={[frame({width: 300, height: 40}), fixedSize()]} />
          <Button label="FIT_COMPACT" onPress={() => setLastAction('compact')}
            modifiers={[frame({width: 120, height: 40}), fixedSize()]} />
        </ViewThatFits>
        <Text>{'LAYOUT_ACTION:' + lastAction}</Text>
        <Button label="Expand fit proposal" onPress={() => setWide(true)} />
        <Button label="Move inset to top" onPress={() => setInsetAtTop(true)} />
      </VStack>
    </SafeAreaInset>
    <Button label="Adapter menu" onPress={back} />
  </VStack>;
}

const initialRows: TableRow[] = [
  {id: 'apricot', values: {fruit: 'Apricot', quantity: '12'}},
  {id: 'kiwi', values: {fruit: 'Kiwi', quantity: '7'}},
];
function TablePanel({ back }: { back: () => void }) {
  const [selection, setSelection] = useState<string | undefined>();
  const [selectionEvents, setSelectionEvents] = useState(0);
  const [rows, setRows] = useState(initialRows);
  return <VStack spacing={12}>
    <Table columns={[{key: 'fruit', title: 'Fruit'}, {key: 'quantity', title: 'Quantity'}]}
      rows={rows} selection={selection} modifiers={[frame({width: 380, height: 240})]}
      onSelectionChange={value => {
        setSelection(value);
        setSelectionEvents(count => count + 1);
      }} />
    <Text>{'TABLE_SELECTION:' + (selection ?? 'none')}</Text>
    <Text>{'TABLE_SELECTION_EVENTS:' + selectionEvents}</Text>
    <Button label="Clear table selection" onPress={() => setSelection(undefined)} />
    <Button label="Update table values" onPress={() =>
      setRows(current => current.map(row => row.id === 'kiwi'
        ? {...row, values: {fruit: 'Kiwi updated', quantity: '9'}} : row))} />
    <Button label="Adapter menu" onPress={back} />
  </VStack>;
}

function ImagePanel({ back }: { back: () => void }) {
  const [url, setURL] = useState<string | undefined>();
  const [phase, setPhase] = useState('unreported');
  const [successes, setSuccesses] = useState(0);
  const [failures, setFailures] = useState(0);
  return <VStack spacing={12}>
    <AsyncImage url={url} modifiers={[frame({width: 80, height: 80}), accessibilityLabel('Decoded adapter image')]}
      placeholder={<Text>IMAGE_EMPTY_SLOT</Text>} failure={<Text>IMAGE_FAILURE_SLOT</Text>}
      onPhaseChange={value => {
        setPhase(value);
        if (value === 'success') setSuccesses(count => count + 1);
        if (value === 'failure') setFailures(count => count + 1);
      }} />
    <Text>{'IMAGE_PHASE:' + phase}</Text>
    <Text>{'IMAGE_SUCCESS_EVENTS:' + successes}</Text>
    <Text>{'IMAGE_FAILURE_EVENTS:' + failures}</Text>
    <Button label="Load exact PNG" onPress={() => setURL(MANUAL_ADAPTER_IMAGE_ORIGIN + '/pixel.png')} />
    <Button label="Load real missing image" onPress={() => setURL(MANUAL_ADAPTER_IMAGE_ORIGIN + '/missing.png')} />
    <Button label="Adapter menu" onPress={back} />
  </VStack>;
}

function PresentationPanel({ kind, back }: { kind: PresentationKind; back: () => void }) {
  const [presented, setPresented] = useState(false);
  const [changes, setChanges] = useState(0);
  const [dismissals, setDismissals] = useState(0);
  const Presentation = kind === 'Sheet' ? Sheet : kind === 'FullScreenCover' ? FullScreenCover : PopoverPresentation;
  return <Presentation isPresented={presented}
    onPresentedChange={value => { setPresented(value); setChanges(count => count + 1); }}
    onDismiss={() => setDismissals(count => count + 1)}
    presented={<VStack spacing={20} modifiers={[frame({minWidth: 300, minHeight: 240})]}>
      <Text>{kind + ' native content'}</Text>
      <Button label={'Close ' + kind + ' from React'} onPress={() => setPresented(false)} />
    </VStack>}>
    <VStack spacing={12}>
      <Button label={'Open ' + kind} onPress={() => setPresented(true)} />
      <Text>{kind + '_CHANGES:' + changes}</Text>
      <Text>{kind + '_DISMISSALS:' + dismissals}</Text>
      <Button label="Adapter menu" onPress={back} />
    </VStack>
  </Presentation>;
}

function InspectorPanel({ back }: { back: () => void }) {
  const [presented, setPresented] = useState(false);
  const [changes, setChanges] = useState(0);
  const [actions, setActions] = useState(0);
  return <Inspector isPresented={presented}
    onPresentedChange={value => { setPresented(value); setChanges(count => count + 1); }}
    inspector={<VStack spacing={20}>
      <Text>Inspector native content</Text>
      <Button label="Inspector native action" onPress={() => setActions(count => count + 1)} />
      <Button label="Close Inspector from React" onPress={() => setPresented(false)} />
    </VStack>}>
    <VStack spacing={12}>
      <Button label="Open Inspector" onPress={() => setPresented(true)} />
      <Text>{'INSPECTOR_CHANGES:' + changes}</Text>
      <Text>{'INSPECTOR_ACTIONS:' + actions}</Text>
      <Button label="Adapter menu" onPress={back} />
    </VStack>
  </Inspector>;
}

export function ManualAdapterProbe({ close }: { close: () => void }) {
  const [panel, setPanel] = useState<Panel>('menu');
  const back = () => setPanel('menu');
  return <View style={{flex: 1}}>
    <Host style={{flex: 1}}>
      <NavigationStack modifiers={[navigationTitle('Manual Native Adapters')]}>
        {panel === 'menu' ? <List>
          <Section title="Input, layout and data">
            <Button label="Input adapters" onPress={() => setPanel('input')} />
            <Button label="Search adapter" onPress={() => setPanel('search')} />
            <Button label="Layout adapters" onPress={() => setPanel('layout')} />
            <Button label="Table adapter" onPress={() => setPanel('table')} />
            <Button label="Image adapter" onPress={() => setPanel('image')} />
          </Section>
          <Section title="Presentation">
            {(['Sheet', 'FullScreenCover', 'Popover', 'Inspector'] as const).map(kind =>
              <Button key={kind} label={kind + ' adapter'} onPress={() => setPanel(kind)} />)}
          </Section>
          <Button label="Close manual adapters" onPress={close} />
        </List> : panel === 'input' ? <InputPanel back={back} />
          : panel === 'search' ? <SearchPanel back={back} />
          : panel === 'layout' ? <LayoutPanel back={back} />
          : panel === 'table' ? <TablePanel back={back} />
          : panel === 'image' ? <ImagePanel back={back} />
          : panel === 'Inspector' ? <InspectorPanel back={back} />
          : <PresentationPanel key={panel} kind={panel} back={back} />}
      </NavigationStack>
    </Host>
  </View>;
}
