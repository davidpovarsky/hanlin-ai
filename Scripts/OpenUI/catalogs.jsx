import React from 'react';
import { z } from 'zod';
import { defineComponent, action, useTriggerAction, useIsStreaming } from '@openuidev/react-lang';
import { openuiLibrary } from '@openuidev/react-ui';

export const nativeComponentNames = [
  'Stack', 'Card', 'CardHeader', 'InlineHeader', 'TextContent', 'MarkDownRenderer',
  'Text', 'BoldText', 'Label', 'CodeBlock', 'Separator', 'Image', 'ImageBlock', 'ImageGallery',
  'Form', 'FormControl', 'Input', 'TextArea', 'Select', 'SelectItem', 'DatePicker', 'Slider',
  'CheckBoxGroup', 'CheckBoxItem', 'RadioGroup', 'RadioItem', 'SwitchGroup', 'SwitchItem',
  'Button', 'Buttons', 'Table', 'Col', 'BarChart', 'LineChart', 'AreaChart', 'HorizontalBarChart',
  'Series', 'PieChart', 'ScatterChart', 'ScatterSeries', 'Point',
  'Tabs', 'TabItem', 'Accordion', 'AccordionItem', 'Carousel', 'Steps', 'StepsItem',
  'TagBlock', 'Tag', 'EntityList', 'ListBlock', 'ListItem', 'TextCallout', 'Callout',
];

const Title = defineComponent({ name: 'Title', description: 'Research title', props: z.object({ text: z.string() }),
  component: ({ props }) => <h2>{props.text}</h2> });
const Paragraph = defineComponent({ name: 'Paragraph', description: 'Research paragraph', props: z.object({ text: z.string() }),
  component: ({ props }) => <p>{props.text}</p> });
const SourceQuote = defineComponent({ name: 'SourceQuote', description: 'A real retrieved source, with exact text and host-provided reference. Do not invent a reference.',
  props: z.object({ reference: z.string(), text: z.string(), action: action().optional() }),
  component: function SourceQuoteView({ props }) {
    const trigger = useTriggerAction(); const streaming = useIsStreaming();
    return <blockquote><p>{props.text}</p>{props.action
      ? <button disabled={streaming} onClick={() => trigger(props.reference, undefined, props.action)}>{props.reference}</button>
      : <cite>{props.reference}</cite>}</blockquote>;
  } });
const Comparison = defineComponent({ name: 'Comparison', description: 'Comparison of named positions',
  props: z.object({ positions: z.array(z.object({ title: z.string(), text: z.string() })) }),
  component: ({ props }) => <div className="torah-comparison">{props.positions.map((p, i) => <section key={i}><h3>{p.title}</h3><p>{p.text}</p></section>)}</div> });
const Conclusion = defineComponent({ name: 'Conclusion', description: 'Conclusion, separate from primary-source quotations',
  props: z.object({ text: z.string() }), component: ({ props }) => <section><h3>Conclusion</h3><p>{props.text}</p></section> });
const Sources = defineComponent({ name: 'Sources', description: 'Source references actually supplied by the host',
  props: z.object({ references: z.array(z.string()) }), component: ({ props }) => <ul>{props.references.map((ref, i) => <li key={i}>{ref}</li>)}</ul> });
const FollowUps = defineComponent({ name: 'FollowUps', description: 'Suggested next questions using real @ToAssistant buttons',
  props: z.object({ items: z.array(openuiLibrary.components.Button.ref) }),
  component: ({ props, renderNode }) => <div>{renderNode(props.items)}</div> });

// Original upstream components are retained; host additions are versioned here.
export const torahLibrary = openuiLibrary.extend({ components: { add: [Title, Paragraph, SourceQuote, Comparison, Conclusion, Sources, FollowUps] } });
export const libraries = { 'openui.original@1': openuiLibrary, 'hanlin.torah@1': torahLibrary };
export { openuiLibrary };
