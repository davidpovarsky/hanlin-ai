import { Text, VStack } from '@expo/ui/swift-ui';

/** The installed prepared Expo program consumes the instance props published by
 * the typed host facade. The compatibility helper below stays unchanged. */
export default function HostServicesWidget(props: {counter?: number; title?: string}) {
  'widget';
  return <VStack spacing={8}>
    <Text>{props.title ?? 'Prepared Expo widget'}</Text>
    <Text>{`Counter: ${props.counter ?? 0}`}</Text>
  </VStack>;
}

export interface WidgetState {
  counter: number;
  title?: string;
}

export function renderWidget(state: WidgetState, family: string) {
  const title = state.title ?? 'Expo SwiftUI Probe';
  const counterText = `Counter: ${state.counter}`;
  const subtitle = `Family: ${family}`;

  return {
    kind: 'vStack',
    properties: {
      spacing: 8,
    },
    children: [
      {
        kind: 'text',
        properties: {
          content: title,
          font: 'headline',
        },
        children: [],
      },
      {
        kind: 'text',
        properties: {
          content: counterText,
          font: 'body',
        },
        children: [],
      },
      {
        kind: 'text',
        properties: {
          content: subtitle,
          font: 'caption',
        },
        children: [],
      },
    ],
  };
}
