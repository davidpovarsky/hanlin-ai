import { AppIntentManager, AppIntentProtocol, Widget } from "scripting"
import { getFavorites, getRecentStops, getWidgetIndex, setWidgetIndex } from "./src/storage/transitStorage"
import { endActiveArrivalActivity } from "./src/services/liveActivityService"

type CycleStationParameters = {
  direction: -1 | 1
  groupKey: string
}

type SelectStationParameters = {
  index: number
  groupKey: string
}

export const CycleWidgetStationIntent = AppIntentManager.register<CycleStationParameters>({
  name: "CycleTransitNearbyWidgetStation",
  protocol: AppIntentProtocol.AppIntent,
  perform: async ({ direction, groupKey }) => {
    const stops = getFavorites().length > 0 ? getFavorites() : getRecentStops()
    if (stops.length === 0) return
    const current = getWidgetIndex(groupKey, stops.length)
    setWidgetIndex(groupKey, current + direction)
    Widget.reloadAll()
  },
})

export const SelectWidgetStationIntent = AppIntentManager.register<SelectStationParameters>({
  name: "SelectTransitNearbyWidgetStation",
  protocol: AppIntentProtocol.AppIntent,
  perform: async ({ index, groupKey }) => {
    const stops = getFavorites().length > 0 ? getFavorites() : getRecentStops()
    if (stops.length === 0) return
    setWidgetIndex(groupKey, index)
    Widget.reloadAll()
  },
})

export const StopTransitLiveActivityIntent = AppIntentManager.register<undefined>({
  name: "StopTransitNearbyLiveActivity",
  protocol: AppIntentProtocol.LiveActivityIntent,
  perform: async () => {
    await endActiveArrivalActivity()
  },
})
