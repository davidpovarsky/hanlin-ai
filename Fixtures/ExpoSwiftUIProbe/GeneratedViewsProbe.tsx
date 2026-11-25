import React, { useState } from 'react';
import { View } from 'react-native';
import {
  Host, NavigationStack, VStack, List, Section, Text, Button, Toolbar,
  GroupBox, EditButton, EmptyView, DefaultDocumentGroupLaunchActions, getInstalledBridgeMetadata,
  HANLIN_EXPO_RUNTIME_VERSION, HANLIN_EXPO_UI_BRIDGE_VERSION, HANLIN_SWIFTUI_SDK_IDENTITY,
} from '@hanlin/expo-ui';
import { accessibilityIdentifier, frame, navigationTitle } from '@hanlin/expo-ui/modifiers';
import fixturePackage from './package.json';

type Panel = 'menu' | 'group' | 'edit' | 'empty' | 'metadata';
type NativeMetadata = ReturnType<typeof getInstalledBridgeMetadata>;

function GroupBoxPanel({ back }: { back: () => void }) {
  const [changes, setChanges] = useState(0);
  return <VStack spacing={16}>
    <GroupBox label={<Text>{'Generated group label ' + changes}</Text>}
      content={<VStack spacing={12}>
        <Text>{'Generated group content ' + changes}</Text>
        <Button label="Change generated group slots" onPress={() => setChanges(value => value + 1)} />
      </VStack>}>
      <Text>GENERATED_GROUP_IGNORED_CHILD</Text>
    </GroupBox>
    <GroupBox label={<Text>Generated ordinary child group</Text>}>
      <Text>{'Generated ordinary child content ' + changes}</Text>
    </GroupBox>
    <GroupBox label={<Text>Generated explicit empty group</Text>} content={null}>
      <Text>GENERATED_GROUP_NULL_CHILD</Text>
    </GroupBox>
    <Button label="Generated view menu" onPress={back} />
  </VStack>;
}

const initialRows = [
  {id: 'alpha', title: 'Generated Alpha'},
  {id: 'beta', title: 'Generated Beta'},
];
function EditButtonPanel({ back }: { back: () => void }) {
  const [rows, setRows] = useState(initialRows);
  const [deletions, setDeletions] = useState(0);
  return <Toolbar>
    <List>
      <Section title="Original editable list">
        <List.ForEach data={rows} keyExtractor={item => item.id} recycling={false}
          onDelete={indices => {
            setRows(current => current.filter((_, index) => !indices.includes(index)));
            setDeletions(count => count + 1);
          }}>
          {({item}) => <Text>{item.title}</Text>}
        </List.ForEach>
      </Section>
      <Section title="Native deletion events">
        <Text>{'EDIT_DELETE_EVENTS:' + deletions}</Text>
        <Text>{'EDIT_ROWS:' + rows.map(row => row.id).join(',')}</Text>
        <Button label="Generated view menu" onPress={back} />
      </Section>
    </List>
    <Toolbar.Content>
      <EditButton modifiers={[accessibilityIdentifier('generated-edit-button')]} />
    </Toolbar.Content>
  </Toolbar>;
}

function MetadataPanel({ back }: { back: () => void }) {
  const [metadata, setMetadata] = useState<NativeMetadata>();
  const [reads, setReads] = useState(0);
  const [error, setError] = useState<string>();
  const read = () => {
    try {
      const actual = getInstalledBridgeMetadata();
      setMetadata(actual);
      setReads(count => count + 1);
      setError(undefined);
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : String(failure));
    }
  };
  const matches = metadata !== undefined
    && metadata.runtimeVersion === fixturePackage.hanlinExpo.runtimeVersion
    && metadata.runtimeVersion === HANLIN_EXPO_RUNTIME_VERSION
    && metadata.bridgeVersion === HANLIN_EXPO_UI_BRIDGE_VERSION
    && metadata.inventoryIdentity === HANLIN_SWIFTUI_SDK_IDENTITY;
  return <VStack spacing={12}>
    <Text>{'METADATA_READS:' + reads}</Text>
    <Text>{'METADATA_STATUS:' + (error ? 'ERROR' : metadata ? (matches ? 'MATCH' : 'MISMATCH') : 'NOT_READ')}</Text>
    <Text>{'METADATA_RUNTIME:' + (metadata?.runtimeVersion ?? 'unread')}</Text>
    <Text>{'METADATA_BRIDGE:' + (metadata?.bridgeVersion ?? 'unread')}</Text>
    <Text>{'METADATA_INVENTORY:' + (metadata?.inventoryIdentity ?? 'unread')}</Text>
    <Text>{'METADATA_EXPECTED_RUNTIME:' + fixturePackage.hanlinExpo.runtimeVersion}</Text>
    {error ? <Text>{'METADATA_ERROR:' + error}</Text> : null}
    <Button label="Read native bridge metadata" onPress={read} />
    <Button label="Generated view menu" onPress={back} />
  </VStack>;
}

interface NativeMeasurement {
  width: number;
  height: number;
  events: number;
}
function EmptyViewPanel({ back }: { back: () => void }) {
  const [empty, setEmpty] = useState(false);
  const [measurement, setMeasurement] = useState<NativeMeasurement>();
  // These are sibling original Hosts in React Native, never a Host nested in
  // another SwiftUI tree. Only onLayoutContent supplies the measured dimensions.
  return <View style={{flex: 1, alignItems: 'flex-start'}}>
    <Host style={{height: 260, alignSelf: 'stretch'}}>
      <VStack spacing={12}>
        <Text>Generated EmptyView native measurement</Text>
        <Text>{'EMPTY_LAYOUT_EVENTS:' + (measurement?.events ?? 0)}</Text>
        <Text>{'EMPTY_NATIVE_SIZE:' + (measurement
          ? measurement.width.toFixed(1) + 'x' + measurement.height.toFixed(1) : 'pending')}</Text>
        <Button label={empty ? 'Restore measured content' : 'Replace measured content with EmptyView'}
          onPress={() => setEmpty(value => !value)} />
        <Button label="Generated view menu" onPress={back} />
      </VStack>
    </Host>
    <Host matchContents style={{alignSelf: 'flex-start'}}
      onLayoutContent={({nativeEvent}) => setMeasurement(current => ({
        width: nativeEvent.width, height: nativeEvent.height, events: (current?.events ?? 0) + 1,
      }))}>
      {empty ? <EmptyView /> : <Text
        modifiers={[frame({width: 120, height: 44}), accessibilityIdentifier('generated-empty-control')]}>
        Visible measurement control
      </Text>}
    </Host>
  </View>;
}

export function GeneratedViewsProbe({ close }: { close: () => void }) {
  const [panel, setPanel] = useState<Panel>('menu');
  const back = () => setPanel('menu');
  if (panel === 'empty') return <EmptyViewPanel back={back} />;
  return <View style={{flex: 1}}>
    <Host style={{flex: 1}}>
      <NavigationStack modifiers={[navigationTitle('Generated Native Views')]}>
        {panel === 'menu' ? <List>
          <Section title="Native behavior">
            <Button label="Generated GroupBox slots" onPress={() => setPanel('group')} />
            <Button label="Generated EditButton list" onPress={() => setPanel('edit')} />
            <Button label="Generated EmptyView measurement" onPress={() => setPanel('empty')} />
            <Button label="Installed bridge metadata" onPress={() => setPanel('metadata')} />
          </Section>
          <Button label="Close generated views" onPress={close} />
        </List> : panel === 'group' ? <GroupBoxPanel back={back} />
          : panel === 'edit' ? <EditButtonPanel back={back} />
          : <MetadataPanel back={back} />}
      </NavigationStack>
    </Host>
  </View>;
}

// Type-checked generated leaf only. The current embedded MiniApp host has no
// DocumentLaunchView/DocumentGroupLaunchScene or document-browser configuration.
// This fragment is deliberately not mounted in an ordinary VStack, and no
// document-creation or native UI pass is claimed for it.
export function DocumentLaunchActionsForDocumentHost() {
  return <DefaultDocumentGroupLaunchActions />;
}
