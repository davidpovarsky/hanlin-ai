import React from 'react';
import { requireNativeModule, requireNativeView } from 'expo';
import type { NativeSyntheticEvent } from 'react-native';
import type { CommonViewModifierProps } from '@expo/ui/swift-ui';
import { createViewModifierEventListener } from '@expo/ui/swift-ui/modifiers';

type ValueChangeEvent = NativeSyntheticEvent<{ value: string }>;

export interface TextEditorProps extends CommonViewModifierProps {
  value?: string;
  defaultValue?: string;
  placeholder?: string;
  isEditable?: boolean;
  onValueChange?: (value: string) => void;
}

const NativeTextEditor = requireNativeView<TextEditorProps & {
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

type BridgeMetadata = {
  runtimeVersion: string;
  bridgeVersion: string;
  inventoryIdentity: string;
};

export function getInstalledBridgeMetadata(): BridgeMetadata {
  return requireNativeModule('HanlinExpoUI').getBridgeMetadata();
}
