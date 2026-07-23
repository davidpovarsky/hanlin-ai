import { Label, List, NavigationLink, Section } from "scripting"
import { FavoritesScreen } from "./FavoritesScreen"
import { SettingsScreen } from "./SettingsScreen"

export function MoreScreen() {
  return (
    <List navigationTitle="עוד" navigationBarTitleDisplayMode="large" listStyle="insetGroup" environments={{ layoutDirection: "rightToLeft" }}>
      <Section>
        <NavigationLink destination={<FavoritesScreen />}><Label title="מועדפים" systemImage="star" /></NavigationLink>
        <Label title="התראות" systemImage="bell" />
        <NavigationLink destination={<SettingsScreen />}><Label title="הגדרות" systemImage="gearshape" /></NavigationLink>
      </Section>
      <Section>
        <Label title="עזרה ומשוב" systemImage="questionmark.circle" />
        <Label title="אודות תחבורה קרובה" systemImage="info.circle" />
      </Section>
    </List>
  )
}
