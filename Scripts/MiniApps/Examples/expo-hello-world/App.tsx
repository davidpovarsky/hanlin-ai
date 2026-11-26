import React, { useState } from 'react';
import { Button, Host, Text, VStack } from '@expo/ui/swift-ui';

export default function App() {
  const [count, setCount] = useState(0);
  return (
    <Host style={{ flex: 1 }} useViewportSizeMeasurement>
      <VStack spacing={16}>
        <Text>Hello from Expo!</Text>
        <Text>{`Button taps: ${count}`}</Text>
        <Button label="Say hello" onPress={() => setCount(value => value + 1)} />
      </VStack>
    </Host>
  );
}
