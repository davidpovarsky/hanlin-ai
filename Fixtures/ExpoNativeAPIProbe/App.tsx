import React, { useState, useEffect } from 'react';
import { View, StyleSheet } from 'react-native';
import {
  init,
  runOnUI,
  defineUIKitView,
  defineUIViewController
} from '@hanlin/expo-native-api';
import {
  Host,
  NavigationStack,
  VStack,
  HStack,
  Text,
  Button,
  RNHostView
} from '@hanlin/expo-ui';
import {
  font,
  foregroundStyle,
  padding
} from '@hanlin/expo-ui/modifiers';

export interface AppProps {
  variant?: 'A' | 'B';
}

interface UILabelProps {
  text: string;
}

const NativeUILabel = defineUIKitView<UILabelProps, UILabel>({
  name: 'NativeUILabel',
  create(context) {
    'worklet';
    const label = UILabel.alloc().init();
    label.text = context.props.text;
    label.textColor = UIColor.labelColor;
    label.textAlignment = NSTextAlignment.Center;
    label.numberOfLines = 0;
    label.isAccessibilityElement = true;
    label.accessibilityLabel = context.props.text;
    return label;
  },
  update(view, props) {
    'worklet';
    view.text = props.text;
    view.accessibilityLabel = props.text;
  }
});

interface UISwitchProps {
  isOn: boolean;
  onValueChange?: (value: boolean) => void;
}

const NativeUISwitch = defineUIKitView<UISwitchProps, UISwitch>({
  name: 'NativeUISwitch',
  create(context) {
    'worklet';
    const toggle = UISwitch.alloc().init();
    toggle.on = context.props.isOn;
    toggle.isAccessibilityElement = true;
    toggle.accessibilityLabel = 'Native Switch';
    context.targetAction(toggle, UIControlEvents.ValueChanged, () => {
      'worklet';
      context.emit('onValueChange', toggle.on);
    });
    return toggle;
  },
  update(view, props) {
    'worklet';
    view.setOnAnimated(props.isOn, true);
  }
});

const NativeSheetViewController = defineUIViewController<{ title: string }, UIViewController>({
  name: 'NativeSheetViewController',
  createController(context) {
    'worklet';
    const vc = UIViewController.alloc().init();
    vc.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    const label = UILabel.alloc().init();
    label.text = context.props.title;
    label.isAccessibilityElement = true;
    label.accessibilityLabel = context.props.title;
    label.textAlignment = NSTextAlignment.Center;
    label.frame = CGRectMake(20, 20, 260, 40);
    vc.view.addSubview(label);
    return vc;
  }
});

export default function App({ variant = 'A' }: AppProps) {
  const [initialized, setInitialized] = useState<boolean>(false);
  const [deviceSystemVersion, setDeviceSystemVersion] = useState<string>('Loading...');
  const [isSwitchOn, setIsSwitchOn] = useState<boolean>(false);
  const [showController, setShowController] = useState<boolean>(false);

  useEffect(() => {
    try {
      const ok = init();
      setInitialized(ok);
      if (ok) {
        runOnUI(() => {
          'worklet';
          return UIDevice.currentDevice.systemVersion;
        })
          .then((version) => {
            setDeviceSystemVersion(String(version));
          })
          .catch((err) => {
            setDeviceSystemVersion(`Error: ${err.message}`);
          });
      } else {
        setDeviceSystemVersion('Native API not available');
      }
    } catch (e: any) {
      setDeviceSystemVersion(`Init failed: ${e?.message}`);
    }
  }, []);

  const variantText = variant === 'A'
    ? 'Native UIKit Label: Probe Variant A (Hebrew RTL Ready)'
    : 'Native UIKit Label: Probe Variant B (Dynamic UIKit Switch Demo)';

  return (
    <View style={styles.container}>
      <Host style={styles.host}>
        <NavigationStack>
          <VStack>
            <Text modifiers={[font({ textStyle: 'headline' }), foregroundStyle('#111827')]}>
              Hanlin Expo + NativeScript Hybrid
            </Text>

            <Text modifiers={[font({ textStyle: 'subheadline' }), foregroundStyle('#6B7280')]}>
              {`Probe Variant ${variant} | Initialized: ${initialized ? 'YES' : 'NO'}`}
            </Text>

            <Text modifiers={[font({ textStyle: 'body' }), foregroundStyle('#111827')]}>
              {`iOS System Version: ${deviceSystemVersion}`}
            </Text>

            <Text modifiers={[font({ textStyle: 'callout' }), foregroundStyle(isSwitchOn ? '#10B981' : '#6B7280')]}>
              {`Native Switch Status: ${isSwitchOn ? 'ENABLED (ON)' : 'DISABLED (OFF)'}`}
            </Text>

            {/* Real Fabric component inside SwiftUI layout via RNHostView */}
            {initialized && (
              <RNHostView>
                <View style={styles.nativeLabelContainer}>
                  <NativeUILabel style={styles.nativeLabel} text={variantText} />
                </View>
              </RNHostView>
            )}

            {/* Real UIKit UISwitch mounted as child with two-way target-action */}
            {initialized && (
              <HStack>
                <Text modifiers={[font({ textStyle: 'body' })]}>UIKit UISwitch:</Text>
                <RNHostView>
                  <View style={styles.nativeSwitchContainer}>
                    <NativeUISwitch
                      style={styles.nativeSwitch}
                      isOn={isSwitchOn}
                      onValueChange={(val: boolean) => setIsSwitchOn(val)}
                    />
                  </View>
                </RNHostView>
              </HStack>
            )}

            {initialized && (
              <Button
                label={showController ? 'Hide Native Controller' : 'Mount Native UIViewController'}
                onPress={() => setShowController(!showController)}
              />
            )}

            {initialized && showController && (
              <RNHostView>
                <View style={styles.nativeControllerContainer}>
                  <NativeSheetViewController style={styles.nativeController} title="Hosted Native UIViewController" />
                </View>
              </RNHostView>
            )}
          </VStack>
        </NavigationStack>
      </Host>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  host: {
    flex: 1,
  },
  nativeLabelContainer: {
    height: 60,
    width: 320,
    justifyContent: 'center',
    alignItems: 'center',
    marginVertical: 8,
  },
  nativeLabel: {
    width: 320,
    height: 60,
  },
  nativeSwitchContainer: {
    width: 60,
    height: 40,
    justifyContent: 'center',
    alignItems: 'center',
  },
  nativeSwitch: {
    width: 51,
    height: 31,
  },
  nativeControllerContainer: {
    width: 300,
    height: 100,
    marginVertical: 8,
    borderRadius: 8,
    overflow: 'hidden',
  },
  nativeController: {
    width: 300,
    height: 100,
  },
});
