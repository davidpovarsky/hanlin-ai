// app_intents.tsx — AppIntents for widget buttons
import { AppIntentManager, AppIntentProtocol, Widget } from "scripting"
import { completeStation } from "./model/index"
// Storage is a global — do NOT import it from "scripting"

// Intent: Complete a station from the widget
export const CompleteStationIntent = AppIntentManager.register({
  name: "CompleteStationIntent",
  protocol: AppIntentProtocol.AppIntent,
  perform: async (params: { stationId: number }) => {
    completeStation(params.stationId, "")
    Widget.reloadAll()
  },
})

// Intent: Open the app to a specific station detail
export const OpenStationIntent = AppIntentManager.register({
  name: "OpenStationIntent",
  protocol: AppIntentProtocol.AppIntent,
  perform: async (params: { stationId: number }) => {
    Storage.set("open_station_id", params.stationId)
    Widget.reloadAll()
  },
})
