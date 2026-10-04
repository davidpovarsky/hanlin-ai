import React from 'react';
import { requireNativeModule, requireNativeView } from 'expo';
import type { NativeSyntheticEvent } from 'react-native';
import type { CommonViewModifierProps } from '@expo/ui/swift-ui';
import { createViewModifierEventListener } from '@expo/ui/swift-ui/modifiers';

type ValueChangeEvent = NativeSyntheticEvent<{ value: string }>;
type BooleanChangeEvent = NativeSyntheticEvent<{ value: boolean }>;
type PhaseChangeEvent = NativeSyntheticEvent<{ phase: 'empty' | 'success' | 'failure' }>;

interface SlotProps {
  name: string;
  children?: React.ReactNode;
}

const NativeSlot = requireNativeView<SlotProps>('HanlinExpoUI', 'HanlinSlotView');

function Slot({ name, children }: SlotProps) {
  return <NativeSlot name={name}>{children}</NativeSlot>;
}

export interface TextEditorProps extends CommonViewModifierProps {
  value?: string;
  defaultValue?: string;
  placeholder?: string;
  isEditable?: boolean;
  onValueChange?: (value: string) => void;
}

const NativeTextEditor = requireNativeView<Omit<TextEditorProps, 'onValueChange'> & {
  onValueChange?: (event: ValueChangeEvent) => void;
}>('HanlinExpoUI', 'HanlinTextEditorView');

export function TextEditor({ modifiers, onValueChange, ...props }: TextEditorProps) {
  return (
    <NativeTextEditor
      {...props}
      modifiers={modifiers}
      {...(modifiers ? createViewModifierEventListener(modifiers) : undefined)}
      onValueChange={(event) => onValueChange?.(event.nativeEvent.value)}
    />
  );
}

export type GridItem =
  | { size: 'fixed'; value: number; spacing?: number }
  | { size: 'flexible'; minimum?: number; maximum?: number; spacing?: number }
  | { size: 'adaptive'; minimum: number; maximum?: number; spacing?: number };

export interface LazyGridProps extends CommonViewModifierProps {
  tracks?: GridItem[];
  spacing?: number;
  pinnedSectionHeaders?: boolean;
  pinnedSectionFooters?: boolean;
  children?: React.ReactNode;
}

const NativeLazyVGrid = requireNativeView<LazyGridProps>('HanlinExpoUI', 'HanlinLazyVGridView');
const NativeLazyHGrid = requireNativeView<LazyGridProps>('HanlinExpoUI', 'HanlinLazyHGridView');

function gridComponent(NativeComponent: typeof NativeLazyVGrid, displayName: string) {
  function Component({ modifiers, ...props }: LazyGridProps) {
    return (
      <NativeComponent
        {...props}
        modifiers={modifiers}
        {...(modifiers ? createViewModifierEventListener(modifiers) : undefined)}
      />
    );
  }
  Object.defineProperty(Component, 'name', { value: displayName });
  return Component;
}

export const LazyVGrid = gridComponent(NativeLazyVGrid, 'LazyVGrid');
export const LazyHGrid = gridComponent(NativeLazyHGrid, 'LazyHGrid');

export interface ViewThatFitsProps extends CommonViewModifierProps {
  axes?: 'both' | 'horizontal' | 'vertical';
  children?: React.ReactNode;
}

const NativeViewThatFits = requireNativeView<ViewThatFitsProps>('HanlinExpoUI', 'HanlinViewThatFitsView');

export function ViewThatFits({ modifiers, ...props }: ViewThatFitsProps) {
  return (
    <NativeViewThatFits
      {...props}
      modifiers={modifiers}
      {...(modifiers ? createViewModifierEventListener(modifiers) : undefined)}
    />
  );
}

export interface SearchableProps extends CommonViewModifierProps {
  value?: string;
  defaultValue?: string;
  isPresented?: boolean;
  defaultPresented?: boolean;
  prompt?: string;
  placement?: 'automatic' | 'navigationBar' | 'toolbar';
  children: React.ReactNode;
  suggestions?: React.ReactNode;
  onValueChange?: (value: string) => void;
  onPresentedChange?: (value: boolean) => void;
  onSubmit?: (value: string) => void;
}

type NativeSearchableProps = Omit<
  SearchableProps,
  'children' | 'suggestions' | 'onValueChange' | 'onPresentedChange' | 'onSubmit'
> & {
  children?: React.ReactNode;
  onValueChange?: (event: ValueChangeEvent) => void;
  onPresentedChange?: (event: BooleanChangeEvent) => void;
  onSubmit?: (event: ValueChangeEvent) => void;
};

const NativeSearchable = requireNativeView<NativeSearchableProps>('HanlinExpoUI', 'HanlinSearchableView');

export function Searchable({
  modifiers,
  children,
  suggestions,
  onValueChange,
  onPresentedChange,
  onSubmit,
  ...props
}: SearchableProps) {
  return (
    <NativeSearchable
      {...props}
      modifiers={modifiers}
      {...(modifiers ? createViewModifierEventListener(modifiers) : undefined)}
      onValueChange={(event) => onValueChange?.(event.nativeEvent.value)}
      onPresentedChange={(event) => onPresentedChange?.(event.nativeEvent.value)}
      onSubmit={(event) => onSubmit?.(event.nativeEvent.value)}>
      <Slot name="content">{children}</Slot>
      {suggestions === undefined ? null : <Slot name="suggestions">{suggestions}</Slot>}
    </NativeSearchable>
  );
}

export interface PresentationProps extends CommonViewModifierProps {
  isPresented?: boolean;
  defaultPresented?: boolean;
  children: React.ReactNode;
  presented: React.ReactNode;
  onPresentedChange?: (value: boolean) => void;
  onDismiss?: () => void;
}

type NativePresentationProps = Omit<PresentationProps, 'children' | 'presented' | 'onPresentedChange' | 'onDismiss'> & {
  kind: 'sheet' | 'fullScreenCover' | 'popover';
  children?: React.ReactNode;
  onPresentedChange?: (event: BooleanChangeEvent) => void;
  onDismiss?: () => void;
};

const NativePresentation = requireNativeView<NativePresentationProps>('HanlinExpoUI', 'HanlinPresentationView');

function presentationComponent(kind: NativePresentationProps['kind']) {
  return function Presentation({
    modifiers,
    children,
    presented,
    onPresentedChange,
    onDismiss,
    ...props
  }: PresentationProps) {
    return (
      <NativePresentation
        {...props}
        kind={kind}
        modifiers={modifiers}
        {...(modifiers ? createViewModifierEventListener(modifiers) : undefined)}
        onPresentedChange={(event) => onPresentedChange?.(event.nativeEvent.value)}
        onDismiss={onDismiss}>
        <Slot name="content">{children}</Slot>
        <Slot name="presented">{presented}</Slot>
      </NativePresentation>
    );
  };
}

export const Sheet = presentationComponent('sheet');
export const FullScreenCover = presentationComponent('fullScreenCover');
export const PopoverPresentation = presentationComponent('popover');

export interface InspectorProps extends CommonViewModifierProps {
  isPresented?: boolean;
  defaultPresented?: boolean;
  children: React.ReactNode;
  inspector: React.ReactNode;
  onPresentedChange?: (value: boolean) => void;
}

type NativeInspectorProps = Omit<InspectorProps, 'children' | 'inspector' | 'onPresentedChange'> & {
  children?: React.ReactNode;
  onPresentedChange?: (event: BooleanChangeEvent) => void;
};

const NativeInspector = requireNativeView<NativeInspectorProps>('HanlinExpoUI', 'HanlinInspectorView');

export function Inspector({ modifiers, children, inspector, onPresentedChange, ...props }: InspectorProps) {
  return (
    <NativeInspector
      {...props}
      modifiers={modifiers}
      {...(modifiers ? createViewModifierEventListener(modifiers) : undefined)}
      onPresentedChange={(event) => onPresentedChange?.(event.nativeEvent.value)}>
      <Slot name="content">{children}</Slot>
      <Slot name="inspector">{inspector}</Slot>
    </NativeInspector>
  );
}

export interface FocusedProps extends CommonViewModifierProps {
  isFocused?: boolean;
  defaultFocused?: boolean;
  children: React.ReactNode;
  onFocusedChange?: (value: boolean) => void;
}

type NativeFocusedProps = Omit<FocusedProps, 'children' | 'onFocusedChange'> & {
  children?: React.ReactNode;
  onFocusedChange?: (event: BooleanChangeEvent) => void;
};

const NativeFocused = requireNativeView<NativeFocusedProps>('HanlinExpoUI', 'HanlinFocusedView');

export function Focused({ modifiers, children, onFocusedChange, ...props }: FocusedProps) {
  return (
    <NativeFocused
      {...props}
      modifiers={modifiers}
      {...(modifiers ? createViewModifierEventListener(modifiers) : undefined)}
      onFocusedChange={(event) => onFocusedChange?.(event.nativeEvent.value)}>
      <Slot name="content">{children}</Slot>
    </NativeFocused>
  );
}

export interface SafeAreaInsetProps extends CommonViewModifierProps {
  edge?: 'top' | 'bottom' | 'leading' | 'trailing';
  spacing?: number;
  children: React.ReactNode;
  inset: React.ReactNode;
}

type NativeSafeAreaInsetProps = Omit<SafeAreaInsetProps, 'children' | 'inset'> & {
  children?: React.ReactNode;
};

const NativeSafeAreaInset = requireNativeView<NativeSafeAreaInsetProps>('HanlinExpoUI', 'HanlinSafeAreaInsetView');

export function SafeAreaInset({ modifiers, children, inset, ...props }: SafeAreaInsetProps) {
  return (
    <NativeSafeAreaInset
      {...props}
      modifiers={modifiers}
      {...(modifiers ? createViewModifierEventListener(modifiers) : undefined)}>
      <Slot name="content">{children}</Slot>
      <Slot name="inset">{inset}</Slot>
    </NativeSafeAreaInset>
  );
}

export interface AsyncImageProps extends CommonViewModifierProps {
  url?: string;
  scale?: number;
  placeholder?: React.ReactNode;
  failure?: React.ReactNode;
  onPhaseChange?: (phase: 'empty' | 'success' | 'failure') => void;
}

type NativeAsyncImageProps = Omit<AsyncImageProps, 'placeholder' | 'failure' | 'onPhaseChange'> & {
  children?: React.ReactNode;
  onPhaseChange?: (event: PhaseChangeEvent) => void;
};

const NativeAsyncImage = requireNativeView<NativeAsyncImageProps>('HanlinExpoUI', 'HanlinAsyncImageView');

export function AsyncImage({ modifiers, placeholder, failure, onPhaseChange, ...props }: AsyncImageProps) {
  return (
    <NativeAsyncImage
      {...props}
      modifiers={modifiers}
      {...(modifiers ? createViewModifierEventListener(modifiers) : undefined)}
      onPhaseChange={(event) => onPhaseChange?.(event.nativeEvent.phase)}>
      {placeholder === undefined ? null : <Slot name="placeholder">{placeholder}</Slot>}
      {failure === undefined ? null : <Slot name="failure">{failure}</Slot>}
    </NativeAsyncImage>
  );
}

export interface TableColumn {
  key: string;
  title: string;
}

export interface TableRow {
  id: string;
  values: Record<string, string>;
}

export interface TableProps extends CommonViewModifierProps {
  columns: TableColumn[];
  rows: TableRow[];
  selection?: string;
  onSelectionChange?: (value: string | undefined) => void;
}

type TableSelectionEvent = NativeSyntheticEvent<{ value?: string }>;
type NativeTableProps = Omit<TableProps, 'onSelectionChange'> & {
  onSelectionChange?: (event: TableSelectionEvent) => void;
};

const NativeTable = requireNativeView<NativeTableProps>('HanlinExpoUI', 'HanlinTableView');

export function Table({ modifiers, onSelectionChange, ...props }: TableProps) {
  return (
    <NativeTable
      {...props}
      modifiers={modifiers}
      {...(modifiers ? createViewModifierEventListener(modifiers) : undefined)}
      onSelectionChange={(event) => onSelectionChange?.(event.nativeEvent.value)}
    />
  );
}

type BridgeMetadata = {
  runtimeVersion: string;
  bridgeVersion: string;
  inventoryIdentity: string;
};

export function getInstalledBridgeMetadata(): BridgeMetadata {
  return requireNativeModule('HanlinExpoUI').getBridgeMetadata();
}
