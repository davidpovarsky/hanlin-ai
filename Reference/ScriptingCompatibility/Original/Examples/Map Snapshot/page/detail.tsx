import { Button, List, Navigation, NavigationStack, Section, Text } from "scripting";
import type { MapSelectionValue } from "scripting";
import { server } from "../class/server";

export function View({ selection }: { selection: MapSelectionValue }) {
  const dismiss = Navigation.useDismiss();
  const selectedId = (selection as any)?.tag as string | undefined;
  const pin = server.getPinById(selectedId);

  return (
    <NavigationStack>
      <MainView
        pin={pin}
        navigationTitle={pin?.title || selectedId || "פרטים"}
        toolbar={{
          cancellationAction: [<Button title={"关闭"} systemImage={"xmark"} action={dismiss} />],
        }}
      />
    </NavigationStack>
  );
}

function MainView({ pin }: { pin: ReturnType<typeof server.getPinById> }) {
  return (
    <List>
      <Section title={"פרטי נקודה"}>
        <Text>{pin?.title || "לא נבחרה נקודה"}</Text>
        {pin ? <Text>{pin.subtitle}</Text> : null}
      </Section>
      {pin ? (
        <Section title={"קואורדינטות"}>
          <Text>Latitude: {pin.coordinate.latitude}</Text>
          <Text>Longitude: {pin.coordinate.longitude}</Text>
        </Section>
      ) : null}
    </List>
  );
}
