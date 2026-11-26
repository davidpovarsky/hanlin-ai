import type { ButtonProps, ToggleProps } from '@expo/ui/swift-ui';

/** Public iOS/iPadOS 27 widget families. WidgetKit exposes only sizes available on the device. */
export type HanlinWidgetFamily =
  | 'systemSmall' | 'systemMedium' | 'systemLarge' | 'systemExtraLarge'
  | 'systemExtraLargePortrait' | 'accessoryCircular' | 'accessoryRectangular' | 'accessoryInline';

/** Widget callbacks run in the original widget VM and return the props to persist.
 * They are synchronous; the same intended Boolean may be delivered repeatedly.
 */
export type WidgetToggleHandler<Props extends object> = (isOn: boolean) => Partial<Props>;
export type WidgetToggleProps<Props extends object> = Omit<ToggleProps, 'onIsOnChange' | 'isOn'> & {
  isOn: boolean;
  /** Use the declared expoCallback action ID in prepared host widgets. */
  target: string;
  onIsOnChange: WidgetToggleHandler<Props>;
};
/** Original Expo Button with a native timeline reload intent. Use as JSX spread props.
 * Reload requests are scheduled by WidgetKit; they do not promise an exact refresh time.
 */
export type WidgetRefreshButtonProps = Omit<ButtonProps, 'onPress'> & {
  widgetRefresh: true;
};
export interface WidgetToggleInteractionEvent {
  source: string;
  target: string;
  timestamp: number;
  type: 'ExpoWidgetsUserInteraction';
  value: boolean;
  isOn: boolean;
}
