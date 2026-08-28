// LargeWidget.tsx — Widget for systemLarge size
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
  Circle,
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

export function LargeWidget() {
  const todayLog = loadTodayLog()
  const appData = loadAppData()
  const completed = todayLog.stations.length
  const completedIds = new Set(todayLog.stations.map(s => s.stationId))
  const streak = appData.streak
  const encouragement = getEncouragement(todayLog, appData)
  const skippedStations = getSkippedStations(todayLog)

  return (
    <VStack spacing={8} padding={16}>
      <HStack>
        <VStack alignment="leading" spacing={2}>
          <HStack spacing={4}>
            <Image systemName={getIcon("appTitle")} font={16} foregroundStyle={ICON_COLORS.appTitle as Color} />
            <Text font={18} fontWeight="bold">
              {"תזונה יומית"}
            </Text>
          </HStack>
          {streak > 0 && (
            <HStack spacing={3}>
              <Image systemName={getIcon("streak")} font={12} foregroundStyle={ICON_COLORS.streak as Color} />
              <Text font={13} fontWeight="semibold">
                {streak + " ימים ברצף!"}
              </Text>
            </HStack>
          )}
        </VStack>
        <Spacer />
        <VStack alignment="trailing">
          <Text font={28} fontWeight="bold" foregroundStyle="systemGreen">
            {completed + "/5"}
          </Text>
          <Text font={11} foregroundStyle="secondaryLabel">
            {todayLog.totalPoints + " נקודות"}
          </Text>
        </VStack>
      </HStack>

      <ProgressView value={completed} total={5} progressViewStyle="linear" />

            {skippedStations.length > 0 && (
              <HStack spacing={2}>
                <Image systemName={getIcon("skipped")} font={12} foregroundStyle="systemRed" />
                <Text font={13} foregroundStyle="systemRed" lineLimit={2}>
                  {"דולגו: " + skippedStations.map(s => s.name).join(", ")}
                </Text>
              </HStack>
            )}

            <VStack spacing={6}>
              {STATIONS.map(station => {
                const isDone = completedIds.has(station.id)
                const log = todayLog.stations.find(s => s.stationId === station.id)
                return (
                  <HStack key={station.id} spacing={8}>
                                      {/* עיגול לחיץ */}
                                      <Button
                                        intent={
                                          isDone
                                            ? OpenStationIntent({ stationId: station.id })
                                            : CompleteStationIntent({ stationId: station.id })
                                        }
                                      >
                                        <ZStack frame={{ width: 32, height: 32 }}>
                                          <Circle
                                            fill={isDone ? "systemGreen" : undefined}
                                            stroke={isDone ? undefined : { shapeStyle: "systemGray3", strokeStyle: { lineWidth: 2 } }}
                                          />
                                          {isDone && (
                                            <Image
                                              systemName="checkmark"
                                              font={16}
                                              foregroundStyle="white"
                                            />
                                          )}
                                        </ZStack>
                                      </Button>
                                      
                                      {/* אייקון הארוחה */}
                                                                            <Image systemName={getStationIcon(station.id)} font={18} foregroundStyle={getStationColor(station.id) as Color} />
                                      
                                      {/* טקסט הארוחה (לא לחיץ) */}
                                      <VStack alignment="leading" spacing={1}>
                                        <Text
                                          font={14}
                                          fontWeight="medium"
                                          foregroundStyle={isDone ? "secondaryLabel" : "label"}
                                          strikethrough={isDone ? { color: "secondaryLabel", pattern: "solid" } : undefined}
                                        >
                                          {station.name}
                                        </Text>
                                        <Text font={11} foregroundStyle="secondaryLabel">
                                          {station.timeStart + "–" + station.timeEnd +
                                            (log ? "  +" + log.points + " נק׳" : "")}
                                        </Text>
                                      </VStack>
                                      <Spacer />
                                    </HStack>
                )
              })}
            </VStack>

      <Spacer />

      <Text font={12} foregroundStyle="secondaryLabel" multilineTextAlignment="center">
        {encouragement}
      </Text>
    </VStack>
  )
}