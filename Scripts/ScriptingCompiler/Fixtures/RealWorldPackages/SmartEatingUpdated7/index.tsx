// index.tsx — Entry point only
import {
  Navigation, Script, Tab, TabView, useObservable,
} from "scripting"
import { HomeScreen } from "./screens/HomeScreen"
import { HistoryScreen } from "./screens/HistoryScreen"
import { AIChatScreen } from "./screens/AIChatScreen"
import { SettingsScreen } from "./screens/SettingsScreen"
import { t } from "./model/i18n"

function MainApp() {
  const selection = useObservable<number>(0)

  return (
    <TabView selection={selection}>
      <Tab title={t("homeTab")} systemImage="house.fill" value={0}>
        <HomeScreen tabSelection={selection} />
      </Tab>
      <Tab title={t("historyTab")} systemImage="chart.bar.fill" value={1}>
        <HistoryScreen />
      </Tab>
      <Tab title={t("aiTab")} systemImage="brain.head.profile" value={2}>
        <AIChatScreen />
      </Tab>
      <Tab title={t("settingsTab")} systemImage="gearshape.fill" value={3}>
        <SettingsScreen />
      </Tab>
    </TabView>
  )
}

async function run() {
  try {
    await Navigation.present({ element: <MainApp /> })
  } catch (error) {
    console.error("Failed to load app:", error)
  } finally {
    Script.exit()
  }
}

run()