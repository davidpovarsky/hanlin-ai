# Hanlin Expo Native API Hybrid: Code Examples

This document provides concrete, type-safe examples for authoring MiniApps with `@hanlin/expo-native-api` inside the Hanlin Expo runtime.

---

## 1. Hosting a Native UIKit View inside SwiftUI

Use `defineUIKitView` to wrap any Apple UIKit view, then mount it inside SwiftUI using `RNHostView` from `@hanlin/expo-ui`:

```tsx
import React, { useState } from 'react';
import { View, StyleSheet } from 'react-native';
import { defineUIKitView, type UIKitViewContext } from '@hanlin/expo-native-api';
import { Host, VStack, HStack, Text, RNHostView } from '@hanlin/expo-ui';

interface UILabelProps {
  text: string;
}

// 1. Define the native UIKit component
const NativeUILabel = defineUIKitView<UILabelProps, UILabel>({
  name: 'NativeUILabel',
  create(context: UIKitViewContext<UILabelProps>) {
    'worklet';
    const label = UILabel.alloc().init();
    label.text = context.props.text;
    label.textColor = UIColor.labelColor;
    label.textAlignment = NSTextAlignment.Center;
    label.numberOfLines = 0;
    return label;
  },
  update(view: UILabel, props: UILabelProps) {
    'worklet';
    view.text = props.text;
  }
});

// 2. Render inside SwiftUI layout tree
export default function App() {
  return (
    <Host>
      <VStack>
        <Text>SwiftUI Heading</Text>
        <RNHostView matchContents={true}>
          <View style={styles.container}>
            <NativeUILabel text="Hello from Native UIKit Label!" />
          </View>
        </RNHostView>
      </VStack>
    </Host>
  );
}

const styles = StyleSheet.create({
  container: {
    height: 50,
    width: 300,
    justifyContent: 'center',
    alignItems: 'center'
  }
});
```

---

## 2. Two-Way Target-Action Events (e.g. `UISwitch`)

Connect UIKit target-action events to React state using `context.targetAction` and `context.emit`:

```tsx
import React, { useState } from 'react';
import { View, StyleSheet } from 'react-native';
import { defineUIKitView } from '@hanlin/expo-native-api';
import { Host, HStack, Text, RNHostView } from '@hanlin/expo-ui';

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

export function SwitchExample() {
  const [enabled, setEnabled] = useState(false);

  return (
    <HStack>
      <Text>{`Switch is: ${enabled ? 'ON' : 'OFF'}`}</Text>
      <RNHostView matchContents={true}>
        <View style={{ width: 60, height: 40 }}>
          <NativeUISwitch
            isOn={enabled}
            onValueChange={(val) => setEnabled(val)}
          />
        </View>
      </RNHostView>
    </HStack>
  );
}
```

---

## 3. Native `UIViewController` Hosting

Host complex UIKit view controllers inside SwiftUI using `defineUIViewController`:

```tsx
import React, { useState } from 'react';
import { View } from 'react-native';
import { defineUIViewController } from '@hanlin/expo-native-api';
import { Host, Button, RNHostView } from '@hanlin/expo-ui';

const NativeSheetViewController = defineUIViewController<{ title: string }, UIViewController>({
  name: 'NativeSheetViewController',
  createController(context) {
    'worklet';
    const vc = UIViewController.alloc().init();
    vc.view.backgroundColor = UIColor.secondarySystemBackgroundColor;
    const label = UILabel.alloc().init();
    label.text = context.props.title;
    label.textAlignment = NSTextAlignment.Center;
    label.frame = CGRectMake(20, 20, 260, 40);
    vc.view.addSubview(label);
    return vc;
  }
});

export function ControllerExample() {
  const [visible, setVisible] = useState(false);

  return (
    <Host>
      <Button
        label={visible ? "Hide Controller" : "Show Controller"}
        onPress={() => setVisible(!visible)}
      />
      {visible && (
        <RNHostView matchContents={true}>
          <View style={{ width: 300, height: 100 }}>
            <NativeSheetViewController title="Embedded UIKit Controller" />
          </View>
        </RNHostView>
      )}
    </Host>
  );
}
```

---

## 4. UI-Thread Non-Blocking Queries via `runOnUI`

Query system APIs directly on the Worklets UI thread:

```tsx
import React, { useEffect, useState } from 'react';
import { init, runOnUI } from '@hanlin/expo-native-api';
import { Text } from '@hanlin/expo-ui';

export function SystemQueryExample() {
  const [deviceInfo, setDeviceInfo] = useState('Querying...');

  useEffect(() => {
    init(); // Initializes NativeScript JSI runtime
    runOnUI(() => {
      'worklet';
      const device = UIDevice.currentDevice;
      return `${device.name} (${device.systemName} ${device.systemVersion})`;
    })
      .then((info) => setDeviceInfo(String(info)))
      .catch((err) => setDeviceInfo(`Failed: ${err.message}`));
  }, []);

  return <Text>{`Device: ${deviceInfo}`}</Text>;
}
```

---

## 5. Host Swift Integration & Authorization

In Swift, activate a session with the authorization flag matching the user grant:

```swift
import HanlinExpoRuntime
import HanlinExpoNativeAPI

let session = HanlinExpoSession(
    bridgeMetadata: metadata,
    isNativeAPIGranted: grantedCapabilities.contains(.iosNativeAPI)
)

// If capability is revoked at runtime:
session.terminate()
```
