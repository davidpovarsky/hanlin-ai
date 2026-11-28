import {
  Button,
  EnvironmentValuesReader,
  Label,
  List,
  NavigationSplitView,
  NavigationStack,
  Section,
  TabView,
  useObservable,
  useState,
} from "scripting"
import { FavoritesScreen } from "../screens/FavoritesScreen"
import { MapScreen } from "../screens/MapScreen"
import { NearbyScreen } from "../screens/NearbyScreen"
import { SearchScreen } from "../screens/SearchScreen"
import { SettingsScreen } from "../screens/SettingsScreen"
import { getRecentStops } from "../storage/transitStorage"
import { TransitTheme } from "../design/TransitTheme"

export function TransitNearbyApp() {
  return (
    <EnvironmentValuesReader keys={["horizontalSizeClass"]}>
      {environment => Device.isiPad && environment.horizontalSizeClass !== "compact" ? <PadApp /> : <PhoneApp />}
    </EnvironmentValuesReader>
  )
}

function PhoneApp() {
  const selection = useObservable(0)
  return (
    <TabView
      selection={selection}
      environments={{ layoutDirection: "rightToLeft" }}
      tint={TransitTheme.accent}
    >
      <NavigationStack tabItem={<Label title="קרוב" systemImage="location.fill" />} tag={0}>
        <NearbyScreen />
      </NavigationStack>
      <NavigationStack tabItem={<Label title="חיפוש" systemImage="magnifyingglass" />} tag={1}>
        <SearchScreen />
      </NavigationStack>
      <NavigationStack tabItem={<Label title="מועדפים" systemImage="star.fill" />} tag={2}>
        <FavoritesScreen />
      </NavigationStack>
      <NavigationStack tabItem={<Label title="מפה" systemImage="map.fill" />} tag={3}>
        <MapScreen stops={getRecentStops()} />
      </NavigationStack>
      <NavigationStack tabItem={<Label title="הגדרות" systemImage="gearshape" />} tag={4}>
        <SettingsScreen />
      </NavigationStack>
    </TabView>
  )
}

function PadApp() {
  const [selection, setSelection] = useState<"nearby" | "search" | "favorites" | "map" | "settings">("nearby")
  const recentStops = getRecentStops()
  const content = selection === "nearby" ? <NearbyScreen />
    : selection === "search" ? <SearchScreen />
      : selection === "favorites" ? <FavoritesScreen />
        : selection === "map" ? <MapScreen stops={recentStops} />
          : <SettingsScreen />
  return (
    <NavigationSplitView
      navigationSplitViewStyle="balanced"
      environments={{ layoutDirection: "rightToLeft" }}
      sidebar={(
        <List
          navigationTitle="תחבורה קרובה"
          navigationBarTitleDisplayMode="large"
          listStyle="sidebar"
          navigationSplitViewColumnWidth={{ min: 250, ideal: 290, max: 340 }}
        >
          <Section>
            <Button
              title="קרוב אליי"
              systemImage="location.fill"
              action={() => setSelection("nearby")}
              buttonStyle="borderedProminent"
              controlSize="large"
              frame={{ maxWidth: "infinity" }}
            />
          </Section>
          <Section title="ניווט">
            <Button action={() => setSelection("nearby")} buttonStyle="plain"><Label title="תחנות קרובות" systemImage="location.fill" /></Button>
            <Button action={() => setSelection("search")} buttonStyle="plain"><Label title="חיפוש ותכנון" systemImage="magnifyingglass" /></Button>
            <Button action={() => setSelection("favorites")} buttonStyle="plain"><Label title="מועדפים" systemImage="star.fill" /></Button>
            <Button action={() => setSelection("map")} buttonStyle="plain"><Label title="מפה" systemImage="map.fill" /></Button>
            <Button action={() => setSelection("settings")} buttonStyle="plain"><Label title="הגדרות" systemImage="gearshape" /></Button>
          </Section>
        </List>
      )}
      content={(
        <NavigationStack>
          {content}
        </NavigationStack>
      )}
    >
      <NavigationStack>
        <MapScreen stops={recentStops} navigationTitle="מפת תחבורה" />
      </NavigationStack>
    </NavigationSplitView>
  )
}
