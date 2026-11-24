import React, { useState, type ReactNode } from 'react';
import { View } from 'react-native';
import {
  Host, VStack, HStack, ZStack, Text, Button, TextField, Slider, Label, Image,
  ScrollView, List, Section, NavigationStack, NavigationLink, NavigationDestination,
  Searchable, Table, Inspector, SwipeActions, Link,
} from '@hanlin/expo-ui';
import * as m from '@hanlin/expo-ui/modifiers';

// Public factories only. Four names use upstream precedence and are not counted
// as generated adapters: navigationBarTitleDisplayMode, preferredColorScheme,
// presentationCornerRadius, sectionIndexLabel.
// A native onAppear event acknowledges the panel's mounted context. It does not
// assert that every OS-dependent modifier effect has been observed.
type Panel = 'menu' | 'Accessibility' | 'Geometry' | 'Input' | 'Containers'
  | 'Search' | 'Navigation' | 'Inspector' | 'Host Context';
type Back = { back: () => void };

function PanelFrame({ name, back, children }: Back & { name: string; children: ReactNode }) {
  const [appeared, setAppeared] = useState(false);
  return <VStack spacing={10} modifiers={[m.padding({ all: 12 }), m.onAppear(() => setAppeared(true))]}>
    <Text modifiers={[m.font({ size: 20, weight: 'bold' })]}>{'Generated modifiers: ' + name}</Text>
    <Text>{'MODIFIER_NATIVE_CONTEXT:' + name + ':' + (appeared ? 'appeared' : 'waiting')}</Text>
    {children}
    <Button label="Generated modifier menu" onPress={back} />
  </VStack>;
}

function AccessibilityPanel({ back }: Back) {
  const [allowance, setAllowance] = useState(7);
  const [actions, setActions] = useState(0);
  const [activationPoint, setActivationPoint] = useState({ x: 0, y: 0 });
  return <PanelFrame name="Accessibility" back={back}>
    <Text modifiers={[m.accessibilityHeading('h2'), m.accessibilitySortPriority(3)]}>Allowance account</Text>
    <Text modifiers={[
      m.accessibilityIdentifier('generated-accessibility-value'), m.accessibility('Allowance ' + allowance),
      m.accessibilityActivationPoint(activationPoint, activationPoint.x > 0),
      m.onGeometryChange(frame => {
        const point = { x: frame.x + frame.width / 2, y: frame.y + frame.height / 2 };
        setActivationPoint(previous => previous.x === point.x && previous.y === point.y ? previous : point);
      }),
      m.accessibilityIgnoresInvertColors(true), m.accessibilityShowsLargeContentViewer(),
      m.speechAdjustedPitch(0.15), m.speechAlwaysIncludesPunctuation(true),
      m.speechAnnouncementsQueued(true), m.speechSpellsOutCharacters(true),
      m.help('Current allowance, read as individual characters'),
    ]}>Generated allowance</Text>
    <Button label="Increase modifier allowance" onPress={() => setAllowance(value => value + 1)} />
    <Button label="Generated accessibility action" onPress={() => setActions(value => value + 1)}
      modifiers={[m.accessibilityDirectTouch(true, ['requiresActivation']),
        m.accessibilityRespondsToUserInteraction(true, true)]} />
    <Text>{'MODIFIER_ACCESSIBILITY_ACTIONS:' + actions}</Text>
    <Text modifiers={[
      m.accessibilityDragPoint({ x: 0.25, y: 0.5 }, 'Move allowance item', true),
      m.accessibilityDropPoint({ x: 0.75, y: 0.5 }, 'Receive allowance item', true),
    ]}>Drag and drop accessibility metadata</Text>
    <ScrollView modifiers={[m.frame({ width: 340, height: 90 }),
      m.accessibilityScrollStatus('Allowance entries 1 through 4', true)]}>
      <VStack>{['Opening balance', 'Travel', 'Lunch', 'Remaining balance'].map(value => <Text key={value}>{value}</Text>)}</VStack>
    </ScrollView>
    <Text>Speech, direct touch and drag/drop effects require their OS accessibility contexts.</Text>
  </PanelFrame>;
}

function GeometryPanel({ back }: Back) {
  const [changed, setChanged] = useState(false);
  return <PanelFrame name="Geometry" back={back}>
    <Text modifiers={[m.accessibilityIdentifier('generated-tracking-text'), m.fixedSize(),
      m.font({ size: 22 }), m.fontDesign('monospaced'), m.monospaced(true), m.tracking(changed ? 6 : 0)]}>
      WIDTH1234
    </Text>
    <ZStack modifiers={[m.frame({ width: 260, height: 64 })]}>
      <Text modifiers={[m.accessibilityIdentifier('generated-position-text'), m.frame({ width: 80, height: 24 }),
        m.position({ x: changed ? 180 : 60, y: 32 })]}>Position</Text>
    </ZStack>
    <HStack alignment="firstTextBaseline">
      <Text>Normal baseline</Text>
      <Text modifiers={[m.baselineOffset(8)]}>Raised baseline</Text>
    </HStack>
    <Label title="Measured label" systemImage="ruler"
      modifiers={[m.labelIconToTitleSpacing(16), m.labelReservedIconWidth(42), m.flipsForRightToLeftLayoutDirection(true)]} />
    <HStack spacing={20}>
      <Image systemName="rectangle.fill" modifiers={[m.resizable(), m.scaledToFit(), m.frame({ width: 90, height: 54 })]} />
      <Image systemName="rectangle.fill" modifiers={[m.resizable(), m.scaledToFill(), m.frame({ width: 90, height: 54 }), m.clipped()]} />
    </HStack>
    <VStack modifiers={[m.colorScheme('dark'), m.background('black'), m.safeAreaPadding({ top: 8, leading: 12, bottom: 4, trailing: 20 }),
      m.scenePadding(['horizontal']), m.backgroundExtensionEffect(), m.containerCornerOffset(['all'], true)]}>
      <Text modifiers={[m.foregroundStyle('primary')]}>Native dark appearance</Text>
      <Image systemName="star.fill" modifiers={[m.foregroundStyle('orange'), m.blendMode('screen'),
        m.compositingGroup(), m.drawingGroup(false, 'linear'), m.symbolEffectsRemoved(true)]} />
    </VStack>
    <HStack>
      <Text modifiers={[m.edgesIgnoringSafeArea(['horizontal'])]}>Horizontal legacy safe area</Text>
      <Text modifiers={[m.ignoresSafeArea(['container'], ['bottom'])]}>Container bottom safe area</Text>
    </HStack>
    <Button label="Change modifier geometry" onPress={() => setChanged(value => !value)} />
    <Text>{'MODIFIER_GEOMETRY_STATE:' + (changed ? 'changed' : 'initial')}</Text>
  </PanelFrame>;
}

function InputPanel({ back }: Back) {
  const [frontEnabled, setFrontEnabled] = useState(false);
  const [frontTaps, setFrontTaps] = useState(0);
  const [backTaps, setBackTaps] = useState(0);
  const [text, setText] = useState('');
  const [blockSubmit, setBlockSubmit] = useState(true);
  const [submits, setSubmits] = useState(0);
  const [level, setLevel] = useState(25);
  const [showLabels, setShowLabels] = useState(true);
  return <PanelFrame name="Input" back={back}>
    <ZStack modifiers={[m.frame({ width: 280, height: 46 })]}>
      <Button label="Generated back target" onPress={() => setBackTaps(value => value + 1)}
        modifiers={[m.frame({ width: 280, height: 46 })]} />
      <Button label="Generated front target" onPress={() => setFrontTaps(value => value + 1)}
        modifiers={[m.accessibilityIdentifier('generated-hit-front'), m.frame({ width: 280, height: 46 }),
          m.background('blue'), m.foregroundStyle('white'), m.allowsHitTesting(frontEnabled), m.focusable(true), m.focusEffectDisabled(true),
          m.hoverEffectDisabled(true), m.interactionActivityTrackingTag('generated-modifier-hit-target')]} />
    </ZStack>
    <Text>{'MODIFIER_HIT_COUNTS:front=' + frontTaps + ';back=' + backTaps}</Text>
    <Button label={frontEnabled ? "Generated front target enabled" : "Enable generated front target"} onPress={() => setFrontEnabled(true)} />
    <VStack modifiers={[m.onSubmit(() => setSubmits(value => value + 1))]}>
      <TextField placeholder="Generated modifier input" onTextChange={setText}
        modifiers={[m.accessibilityIdentifier('generated-modifier-input'), m.frame({ width: 340 }),
          m.disableAutocorrection(true), m.textInputAutocapitalization('never'), m.submitLabel('done'),
          m.findDisabled(true), m.replaceDisabled(true), m.submitScope(blockSubmit),
          m.textInputFormattingControlVisibility('hidden', ['contextMenu', 'inputAssistant']),
          m.textSelectionAffinity('downstream'), m.writingToolsAffordanceVisibility('hidden')]} />
    </VStack>
    <Text>{'MODIFIER_INPUT:' + text}</Text>
    <Text>{'MODIFIER_SUBMITS:' + submits}</Text>
    <Button label={blockSubmit ? "Allow generated submit" : "Generated submit allowed"} onPress={() => setBlockSubmit(false)} />
    <Slider value={level} onValueChange={setLevel} min={0} max={100} step={5}
      label={<Text>Generated level</Text>}
      modifiers={[m.frame({ width: 320 }), m.sliderThumbVisibility('visible'),
        m.labelsVisibility(showLabels ? 'visible' : 'hidden')]} />
    <Text>{'MODIFIER_SLIDER:' + level}</Text>
    <Button label="Toggle generated labels" onPress={() => setShowLabels(value => !value)} />
  </PanelFrame>;
}

function ContainersPanel({ back, open }: Back & { open: (panel: Panel) => void }) {
  const [headers, setHeaders] = useState(true);
  const [selectionAllowed, setSelectionAllowed] = useState(false);
  const [tableSelection, setTableSelection] = useState<string | undefined>();
  const [selection, setSelection] = useState<(string | number)[]>([]);
  const [swipes, setSwipes] = useState(0);
  return <PanelFrame name="Containers" back={back}>
    <Table columns={[{ key: 'item', title: 'Generated item header' }, { key: 'amount', title: 'Generated amount header' }]}
      rows={[{ id: 'apples', values: { item: 'Generated apples', amount: '12' } },
        { id: 'pears', values: { item: 'Generated pears', amount: '8' } }]}
      selection={tableSelection} onSelectionChange={setTableSelection}
      modifiers={[m.frame({ width: 500, height: 150 }), m.tableColumnHeaders(headers ? 'visible' : 'hidden')]} />
    <Text>{'MODIFIER_TABLE_SELECTION:' + (tableSelection ?? 'none')}</Text>
    <HStack>
      <Button label="Toggle generated headers" onPress={() => setHeaders(value => !value)} />
      <Button label={selectionAllowed ? "Generated selection allowed" : "Allow generated selection"} onPress={() => setSelectionAllowed(true)} />
    </HStack>
    <List selection={selection} onSelectionChange={setSelection}
      modifiers={[m.frame({ width: 500, height: 100 }), m.environment({ key: 'editMode', value: 'active' }),
        m.listSectionIndexVisibility('visible'), m.scrollEdgeEffectHidden(true, ['top', 'bottom']), m.scrollIndicatorsFlash(true)]}>
      <Section title="Generated selection" modifiers={[m.listSectionSeparator('hidden', ['all']), m.sectionIndexLabel('G')]}>
        <Text modifiers={[m.tag('invoice'), m.selectionDisabled(!selectionAllowed), m.typeSelectEquivalent('invoice')]}>
          Generated selectable row
        </Text>
      </Section>
    </List>
    <Text>{'MODIFIER_LIST_SELECTION:' + (selection.join(',') || 'none')}</Text>
    <List modifiers={[m.frame({ width: 500, height: 85 }), m.swipeActionsContainer()]}>
      <SwipeActions>
        <Text>Generated swipe row</Text>
        <SwipeActions.Actions edge="trailing" allowsFullSwipe={false}>
          <Button label="Record generated swipe" onPress={() => setSwipes(value => value + 1)} />
        </SwipeActions.Actions>
      </SwipeActions>
    </List>
    <Text>{'MODIFIER_SWIPE_ACTIONS:' + swipes}</Text>
    <HStack>
      <Button label="Generated search context" onPress={() => open('Search')} />
      <Button label="Generated navigation context" onPress={() => open('Navigation')} />
      <Button label="Generated inspector context" onPress={() => open('Inspector')} />
    </HStack>
  </PanelFrame>;
}

function SearchPanel({ back }: Back) {
  const [query, setQuery] = useState('');
  const [submitted, setSubmitted] = useState('');
  return <NavigationStack>
    <Searchable value={query} onValueChange={setQuery} defaultPresented prompt="Generated completion query"
      onSubmit={setSubmitted} modifiers={[m.searchSuggestions('visible', ['content'])]}
      suggestions={<Text modifiers={[m.searchCompletion('Isaiah')]}>Generated suggestion Isaiah</Text>}>
      <PanelFrame name="Search" back={back}>
        <Text>{'MODIFIER_SEARCH_QUERY:' + query}</Text>
        <Text>{'MODIFIER_SEARCH_SUBMITTED:' + submitted}</Text>
      </PanelFrame>
    </Searchable>
  </NavigationStack>;
}

function NavigationPanel({ back }: Back) {
  const [path, setPath] = useState<string[]>([]);
  const [hideBar, setHideBar] = useState(false);
  const [hideBack, setHideBack] = useState(true);
  return <NavigationStack path={path} onPathChange={setPath}>
    <PanelFrame name="Navigation" back={back}>
      <VStack modifiers={[m.navigationBarTitle('Generated native title'), m.navigationSubtitle('Generated native subtitle'),
        m.navigationBarHidden(hideBar)]}>
        <NavigationLink value="generated-detail" modifiers={[m.navigationLinkIndicatorVisibility('hidden')]}>
          <Text>Open generated detail</Text>
        </NavigationLink>
        <Button label="Toggle generated navigation bar" onPress={() => setHideBar(value => !value)} />
        <Text>{'MODIFIER_NAVIGATION_PATH:' + path.join('/')}</Text>
      </VStack>
    </PanelFrame>
    <NavigationDestination value="generated-detail">
      <VStack modifiers={[m.navigationTitle('Generated detail'), m.navigationBarBackButtonHidden(hideBack)]}>
        <Text>GENERATED_MODIFIER_DETAIL</Text>
        <Button label="Show generated native back" onPress={() => setHideBack(false)} />
        <Button label="Close generated detail" onPress={() => setPath([])} />
      </VStack>
    </NavigationDestination>
  </NavigationStack>;
}

function InspectorPanel({ back }: Back) {
  const [presented, setPresented] = useState(false);
  return <Inspector isPresented={presented} onPresentedChange={setPresented}
    inspector={<VStack modifiers={[m.inspectorColumnWidth(240, 280, 320)]}>
      <Text>GENERATED_MODIFIER_INSPECTOR</Text>
      <Button label="Close generated inspector" onPress={() => setPresented(false)} />
    </VStack>}>
    <PanelFrame name="Inspector" back={back}>
      <Button label="Open generated inspector" onPress={() => setPresented(true)} />
      <Text>{'MODIFIER_INSPECTOR_PRESENTED:' + presented}</Text>
    </PanelFrame>
  </Inspector>;
}

function HostContextPanel({ back }: Back) {
  return <PanelFrame name="Host Context" back={back}>
    <VStack modifiers={[m.allowsWindowActivationEvents(false), m.defersSystemGestures(['bottom']),
      m.persistentSystemOverlays('visible'), m.statusBar(false), m.statusBarHidden(false)]}>
      <Text>Window and system presentation policies</Text>
    </VStack>
    <VStack modifiers={[m.documentLaunchTitle('Generated draft'), m.documentLaunchSubtitle('Local draft documents'),
      m.fileDialogBrowserOptions(['displayFileExtensions', 'enumeratePackages']), m.fileDialogConfirmationLabel('Import draft'),
      m.fileDialogCustomizationID('hanlin.generated-modifier-import'), m.fileDialogImportsUnresolvedAliases(false),
      m.fileDialogMessage('Choose a local draft'), m.fileExporterFilenameLabel('Draft filename'),
      m.previewDisplayName('Generated document settings')]}>
      <Text>Document and file-dialog settings forwarded to SwiftUI.</Text>
      <Text>No document scene or file presenter is created by this probe.</Text>
    </VStack>
    <Link destination="https://example.invalid/generated-modifier-probe" label="Configured in-app URL preference"
      modifiers={[m.onOpenURL(true), m.assistiveAccessNavigationIcon('doc.text')]} />
    <Text>URL, Assistive Access, window and system effects require their real OS contexts.</Text>
    <Text>Preview display names apply to previews, not running MiniApp UI.</Text>
  </PanelFrame>;
}

export function GeneratedModifiersProbe({ close }: { close: () => void }) {
  const [panel, setPanel] = useState<Panel>('menu');
  const back = () => setPanel('menu');
  return <View style={{ flex: 1 }}><Host style={{ flex: 1 }}>
    {panel === 'menu' && <VStack spacing={14} modifiers={[m.padding({ all: 20 })]}>
      <Text>Generated modifier contexts</Text>
      <Text>Native observations and OS-context limits are recorded separately.</Text>
      {(['Accessibility', 'Geometry', 'Input', 'Containers', 'Host Context'] as const).map(name =>
        <Button key={name} label={'Modifiers: ' + name} onPress={() => setPanel(name)} />)}
      <Button label="Exit Generated Modifiers Probe" onPress={close} />
    </VStack>}
    {panel === 'Accessibility' && <AccessibilityPanel back={back} />}
    {panel === 'Geometry' && <GeometryPanel back={back} />}
    {panel === 'Input' && <InputPanel back={back} />}
    {panel === 'Containers' && <ContainersPanel back={back} open={setPanel} />}
    {panel === 'Search' && <SearchPanel back={back} />}
    {panel === 'Navigation' && <NavigationPanel back={back} />}
    {panel === 'Inspector' && <InspectorPanel back={back} />}
    {panel === 'Host Context' && <HostContextPanel back={back} />}
  </Host></View>;
}
