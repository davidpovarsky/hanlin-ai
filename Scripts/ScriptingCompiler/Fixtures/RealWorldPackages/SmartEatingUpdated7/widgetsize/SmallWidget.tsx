// SmallWidget.tsx — Widget for systemSmall size
import {
  VStack,
  HStack,
  Text,
  Button,
  Spacer,
  ZStack,
  Image,
  ProgressView,
  Widget,
  Color,
} from "scripting"
import {
  STATIONS,
  loadTodayLog,
  loadAppData,
  getNextStation,
  minutesUntilStation,
  getEncouragement,
  getStationIcon,
  getStationColor,
  getIcon,
  ICON_TYPE,
  ICONS,
  ICON_COLORS,
  getSkippedStations,
} from "../model/index"
import { CompleteStationIntent, OpenStationIntent } from "../app_intents"

export function SmallWidget() {
  const todayLog = loadTodayLog()
  const appData = loadAppData()
  const completed = todayLog.stations.length
  const nextStation = getNextStation(todayLog)
  const streak = appData.streak
  const skippedStations = getSkippedStations(todayLog)

  return (
    <VStack spacing={6} padding={14}>
      <HStack>
        {streak > 0 ? (
          <HStack spacing={3}>
            <Image systemName={getIcon("streak")} font={12} foregroundStyle={ICON_COLORS.streak as Color} />
            <Text font={13} fontWeight="semibold">
              {streak + " ימים"}
            </Text>
          </HStack>
        ) : (
          <HStack spacing={3}>
            <Image systemName={getIcon("appTitle")} font={12} foregroundStyle={ICON_COLORS.appTitle as Color} />
            <Text font={13} foregroundStyle="secondaryLabel">
              {"תזונה יומית"}
            </Text>
          </HStack>
        )}
        <Spacer />
        <Text font={13} fontWeight="bold" foregroundStyle="systemGreen">
          {completed + "/5"}
        </Text>
      </HStack>

      <ProgressView value={completed} total={5} progressViewStyle="linear" />

      <Spacer />

            {skippedStations.length > 0 && (
              <VStack spacing={2} alignment="trailing">
                <HStack spacing={2}>
                  <Image systemName={getIcon("skipped")} font={10} foregroundStyle="systemRed" />
                  <Text font={11} foregroundStyle="systemRed" lineLimit={1}>
                    {"דולגו: " + skippedStations.map(s => s.name).join(", ")}
                  </Text>
                </HStack>
              </VStack>
            )}

            {nextStation ? (
              <VStack spacing={4} alignment="trailing">
                <Text font={12} foregroundStyle="secondaryLabel">
                  {"התחנה הבאה"}
                </Text>
                <HStack spacing={4}>
                  <Image systemName={getStationIcon(nextStation.id)} font={14} foregroundStyle={getStationColor(nextStation.id) as Color} />
                  <Text font={15} fontWeight="semibold">
                    {nextStation.name}
                  </Text>
                </HStack>
                {minutesUntilStation(nextStation) > 0 ? (
                  <Text font={11} foregroundStyle="secondaryLabel">
                    {"בעוד " + minutesUntilStation(nextStation) + " דקות"}
                  </Text>
                ) : (
                  <HStack spacing={2}>
                    <Image systemName={getIcon("timeNow")} font={10} foregroundStyle="systemOrange" />
                    <Text font={11} foregroundStyle="systemOrange">
                      {"עכשיו!"}
                    </Text>
                  </HStack>
                )}
              </VStack>
            ) : (
              <VStack alignment="center">
                <HStack spacing={4}>
                  <Image systemName={getIcon("allDone")} font={13} foregroundStyle={ICON_COLORS.allDone as Color} />
                  <Text font={14} fontWeight="semibold">
                    {"כל התחנות הושלמו!"}
                  </Text>
                </HStack>
                <Text font={12} foregroundStyle="secondaryLabel">
                  {todayLog.totalPoints + " נקודות היום"}
                </Text>
              </VStack>
            )}
    </VStack>
  )
}