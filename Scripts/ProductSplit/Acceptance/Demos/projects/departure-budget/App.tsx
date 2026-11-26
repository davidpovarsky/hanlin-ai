import React, { useState } from 'react';
import {
  Button, DatePicker, Form, Host, HStack, Section, Stepper, Text, Toggle, VStack,
} from '@expo/ui/swift-ui';
import {
  buttonStyle, disabled, font, foregroundStyle, monospacedDigit,
} from '@expo/ui/swift-ui/modifiers';
import { nextArrival, planDeparture } from './model';

const checklistLabels = ['Keys and wallet', 'Ticket or address', 'Phone and charger'];

export default function App() {
  const [arrival, setArrival] = useState(nextArrival);
  const [travel, setTravel] = useState(30);
  const [preparation, setPreparation] = useState(15);
  const [buffer, setBuffer] = useState(10);
  const [includeBuffer, setIncludeBuffer] = useState(true);
  const [packed, setPacked] = useState<boolean[]>([false, false, false]);
  const plan = planDeparture(arrival, travel, preparation, includeBuffer ? buffer : 0);
  const readyCount = packed.filter(Boolean).length;

  function preset(travelMinutes: number, preparationMinutes: number, bufferMinutes: number) {
    setTravel(travelMinutes);
    setPreparation(preparationMinutes);
    setBuffer(bufferMinutes);
    setIncludeBuffer(true);
  }

  function reset() {
    setArrival(nextArrival());
    preset(30, 15, 10);
    setPacked([false, false, false]);
  }

  return (
    <Host style={{ flex: 1 }} useViewportSizeMeasurement seedColor="#146C78">
      <Form>
        <Section title="Departure Budget" footer={<Text>Set your target arrival, then work backwards.</Text>}>
          <VStack alignment="leading" spacing={6}>
            <Text modifiers={[font({ textStyle: 'headline' })]}>Leave by</Text>
            <Text date={plan.leaveHome} dateStyle="time"
              modifiers={[font({ textStyle: 'largeTitle', weight: 'bold' }), monospacedDigit()]} />
            <Text date={plan.leaveHome} dateStyle="date" />
            <Text>{plan.totalMinutes} minutes reserved before the target</Text>
          </VStack>
        </Section>

        <Section title="Your arrival">
          <DatePicker title="Target date and time" selection={arrival}
            displayedComponents={['date', 'hourAndMinute']} onDateChange={setArrival} />
          <Stepper label={`Travel: ${travel} min`} value={travel} min={0} max={240} step={5}
            onValueChange={setTravel} />
          <Stepper label={`Get ready: ${preparation} min`} value={preparation}
            min={0} max={120} step={5} onValueChange={setPreparation} />
          <Toggle label="Arrive early" isOn={includeBuffer} onIsOnChange={setIncludeBuffer} />
          <Stepper label={`Arrival buffer: ${buffer} min`} value={buffer}
            min={0} max={90} step={5} onValueChange={setBuffer}
            modifiers={[disabled(!includeBuffer)]} />
        </Section>

        <Section title="Quick starting points" footer={<Text>Adjust these estimates to suit your journey.</Text>}>
          <HStack spacing={8}>
            <Button label="Local" onPress={() => preset(20, 10, 5)}
              modifiers={[buttonStyle('bordered')]} />
            <Button label="City" onPress={() => preset(45, 15, 10)}
              modifiers={[buttonStyle('bordered')]} />
            <Button label="Long trip" onPress={() => preset(90, 30, 20)}
              modifiers={[buttonStyle('bordered')]} />
          </HStack>
        </Section>

        <Section title="Your timeline">
          <HStack><Text>Start getting ready</Text><Text date={plan.startPreparing} dateStyle="time" /></HStack>
          <Text date={plan.startPreparing} dateStyle="date" />
          <HStack><Text>Leave</Text><Text date={plan.leaveHome} dateStyle="time" /></HStack>
          <HStack><Text>Expected arrival</Text><Text date={plan.expectedArrival} dateStyle="time" /></HStack>
          <Text date={plan.expectedArrival} dateStyle="date" />
          <Text modifiers={[foregroundStyle('#146C78')]}>
            {includeBuffer ? `${buffer} minutes spare at your destination` : 'No arrival buffer included'}
          </Text>
        </Section>

        <Section title={`Before you go · ${readyCount}/3 ready`}>
          {checklistLabels.map((label, index) => (
            <Toggle key={label} label={label} isOn={packed[index]}
              onIsOnChange={isOn => setPacked(current => current.map((value, i) => i === index ? isOn : value))} />
          ))}
          <Button label="Clear checklist" onPress={() => setPacked([false, false, false])}
            modifiers={[disabled(readyCount === 0)]} />
          <Button label="Reset planner" onPress={reset} />
        </Section>
      </Form>
    </Host>
  );
}
