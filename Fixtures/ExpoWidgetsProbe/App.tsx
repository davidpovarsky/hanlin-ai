import React, {useEffect, useRef, useState} from 'react';
import {Button, ScrollView, Text, View} from 'react-native';
import {Text as WidgetText, VStack} from '@expo/ui/swift-ui';
import {
  createWidget, createLiveActivity, widgetsDirectory,
  type WidgetEnvironment, type LiveActivityEnvironment,
  type LiveActivityFactory,
} from 'expo-widgets';

type ProbeProps = {count: number; label: string};
const WidgetLayout = (props: ProbeProps, _environment: WidgetEnvironment<{tone: string}>) => {
  'widget';
  return <VStack><WidgetText>{props.label}</WidgetText><WidgetText>{props.count}</WidgetText></VStack>;
};
const ActivityLayout = (props: ProbeProps, _environment: LiveActivityEnvironment) => {
  'widget';
  return {
    banner: <VStack><WidgetText>{props.label}</WidgetText><WidgetText>{props.count}</WidgetText></VStack>,
    compactLeading: <WidgetText>{props.count}</WidgetText>,
    compactTrailing: <WidgetText>Expo</WidgetText>,
    minimal: <WidgetText>{props.count}</WidgetText>,
    expandedCenter: <WidgetText>{props.label}</WidgetText>,
  };
};

export default function App({variant = 'A'}: {variant?: 'A' | 'B'}) {
  const [widgetResult, setWidgetResult] = useState('EXPO_WIDGETS_NOT_RUN');
  const [activityResult, setActivityResult] = useState('EXPO_WIDGETS_ACTIVITY_NOT_RUN');
  const factory = useRef<LiveActivityFactory<ProbeProps> | null>(null);
  useEffect(() => {
    let mounted = true;
    void (async () => {
      try {
        if (!widgetsDirectory?.startsWith('file://')) throw new Error('Original shared image directory is missing');
        const widget = createWidget('Shared public widget name', WidgetLayout, {count: 0, label: variant});
        const prior = await widget.getTimeline();
        if (prior.some(entry => entry.props.label !== variant))
          throw new Error('Original ownership mismatch: another installation timeline is visible');
        widget.updateTimeline([{date: new Date(Date.now() - 1000), props: {count: variant === 'A' ? 17 : 29, label: variant}}]);
        const before = await widget.getTimeline();
        if (before.length !== 1 || before[0].props.label !== variant || before[0].props.count !== (variant === 'A' ? 17 : 29))
          throw new Error('Original timeline did not round-trip this installation');
        widget.setConfigurationParameterEnum('tone', [{name: 'Blue', value: 'blue'}]);
        widget.updateSnapshot({count: variant === 'A' ? 23 : 31, label: variant});
        widget.reload();
        const after = await widget.getTimeline();
        if (after[0]?.props.count !== (variant === 'A' ? 23 : 31) || !(after[0]?.date instanceof Date))
          throw new Error('Original snapshot/date conversion did not round-trip');
        factory.current = createLiveActivity('Shared public activity name', ActivityLayout);
        if (mounted) setWidgetResult(`EXPO_WIDGETS_PASS:${variant}:${after[0].props.count}`);
      } catch (error) {
        if (mounted) setWidgetResult('EXPO_WIDGETS_ERROR:' + String(error));
      }
    })();
    return () => { mounted = false; };
  }, [variant]);
  const runActivity = async () => {
    try {
      const actualFactory = factory.current;
      if (!actualFactory) throw new Error('Original activity factory is not ready');
      const activity = actualFactory.start({count: 7, label: variant});
      const id = activity.getId();
      if (!id || !actualFactory.getInstances().some(instance => instance.getId() === id))
        throw new Error('Original ActivityKit instance was not returned by its factory');
      await activity.update({count: 9, label: variant});
      const token = await activity.getPushToken();
      if (token !== null && typeof token !== 'string') throw new Error('Unexpected original push token result');
      await activity.end('immediate', {count: 10, label: variant});
      setActivityResult('EXPO_WIDGETS_ACTIVITY_PASS:' + id);
    } catch (error) { setActivityResult('EXPO_WIDGETS_ACTIVITY_ERROR:' + String(error)); }
  };
  return <ScrollView contentContainerStyle={{padding: 24, gap: 18}}>
    <Text accessibilityRole="header">Original Expo Widgets {variant}</Text>
    <Text testID="expo-widgets-status" selectable>{widgetResult}</Text>
    <Text testID="expo-widgets-activity-status" selectable>{activityResult}</Text>
    <View><Button testID="expo-widgets-start-activity" title="Run original Live Activity" onPress={() => void runActivity()} /></View>
    <Text>This calls the original public Expo Widgets API, native SharedObjects, storage and ActivityKit.</Text>
  </ScrollView>;
}
