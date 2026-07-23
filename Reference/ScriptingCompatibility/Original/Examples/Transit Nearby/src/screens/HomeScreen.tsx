import { Label, List, NavigationLink, Section, Text } from "scripting"
import { StopCard } from "../components/TransitRows"
import { TransitTheme } from "../design/TransitTheme"
import { getFavorites, getRecentStops } from "../storage/transitStorage"
import { NearbyScreen } from "./NearbyScreen"
import { StopDetailsScreen } from "./StopDetailsScreen"

export function HomeScreen() {
  const preferred = getFavorites()[0] ?? getRecentStops()[0]
  return (
    <List
      navigationTitle="תחבורה קרובה"
      navigationBarTitleDisplayMode="large"
      listStyle="insetGroup"
      scrollContentBackground="hidden"
      background={TransitTheme.groupedBackground}
      environments={{ layoutDirection: "rightToLeft" }}
    >
      <Section>
        <NavigationLink destination={<NearbyScreen />}>
          <Label
            title="מצא תחנות קרובות"
            systemImage="location.fill"
            foregroundStyle="white"
            font="headline"
            padding={12}
            background={{ style: TransitTheme.accent, shape: { type: "rect", cornerRadius: 12 } }}
            frame={{ maxWidth: "infinity" }}
          />
        </NavigationLink>
      </Section>
      {preferred ? (
        <Section title="התחנה שלך">
          <NavigationLink destination={<StopDetailsScreen stop={preferred} />}>
            <StopCard stop={preferred} />
          </NavigationLink>
        </Section>
      ) : null}
      <Section title="מידע חי">
        <Label title="זמני הגעה בזמן אמת" systemImage="dot.radiowaves.left.and.right" foregroundStyle={TransitTheme.realtime} />
        <Text foregroundStyle="secondaryLabel">בחר תחנה כדי להפעיל מעקב ב‑Live Activity.</Text>
      </Section>
    </List>
  )
}
