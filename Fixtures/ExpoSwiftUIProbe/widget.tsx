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
