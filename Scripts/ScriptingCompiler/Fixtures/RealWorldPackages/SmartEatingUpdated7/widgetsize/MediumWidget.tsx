// MediumWidget.tsx — Widget for systemMedium size
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

export function MediumWidget() {
  const todayLog = loadTodayLog()
  const appData = loadAppData()
  const completed = todayLog.stations.length
  const completedIds = new Set(todayLog.stations.map(s => s.stationId))
  const nextStation = getNextStation(todayLog)
  const streak = appData.streak
  const encouragement = getEncouragement(todayLog, appData)
  const skippedStations = getSkippedStations(todayLog)

  return (
    <VStack spacing={8} padding={14}>
      <HStack>
        <VStack alignment="leading" spacing={2}>
          <HStack spacing={4}>
            {streak > 0 && (
              <HStack spacing={2}>
                <Image systemName={getIcon("streak")} font={13} foregroundStyle={ICON_COLORS.streak as Color} />
                <Text font={14} fontWeight="bold">
                  {streak + ""}
                </Text>
              </HStack>
            )}
            <HStack spacing={3}>
              <Image systemName={getIcon("appTitle")} font={13} foregroundStyle={ICON_COLORS.appTitle as Color} />
              <Text font={14} fontWeight="semibold">
                {"תזונה יומית"}
              </Text>
            </HStack>
          </HStack>
          <Text font={11} foregroundStyle="secondaryLabel">
            {encouragement}
          </Text>
        </VStack>
        <Spacer />
        <Text font={22} fontWeight="bold" foregroundStyle="systemGreen">
          {completed + "/5"}
        </Text>
      </HStack>

      <ProgressView value={completed} total={5} progressViewStyle="linear" />

            {skippedStations.length > 0 && (
              <HStack spacing={2}>
                <Image systemName={getIcon("skipped")} font={11} foregroundStyle="systemRed" />
                <Text font={12} foregroundStyle="systemRed" lineLimit={1}>
                  {"דולגו: " + skippedStations.map(s => s.name).join(", ")}
                </Text>
              </HStack>
            )}

            <HStack spacing={6}>
        {STATIONS.map(station => {
                  const isDone = completedIds.has(station.id)
                  return (
                    <VStack key={station.id} spacing={2}>
                      {/* הכפתור המקורי עם האייקון והטקסט */}
                      <Button
                        intent={OpenStationIntent({ stationId: station.id })}
                      >
                        <VStack spacing={2}>
                          <Image systemName={getStationIcon(station.id)} font={18} foregroundStyle={getStationColor(station.id) as Color} />
                          <Text
                            font={9}
                            foregroundStyle={isDone ? "systemGreen" : "label"}
                            lineLimit={1}
                          >
                            {station.name}
                          </Text>
                        </VStack>
                      </Button>

                      {/* העיגול הלחיץ החדש מתחת לאייקון הארוחה */}
                      <Button
                                      intent={CompleteStationIntent({ stationId: station.id })}
                                      buttonStyle="plain"
                                    >
                                      <ZStack frame={{ width: 18, height: 18 }}>
                                        <Circle
                                          fill={isDone ? "systemGreen" : undefined}
                                          stroke={isDone ? undefined : { shapeStyle: "systemGray3", strokeStyle: { lineWidth: 2 } }}
                                        />
                                        {isDone && (
                                          <Image
                                            systemName="checkmark"
                                            font={10}
                                            foregroundStyle="white"
                                          />
                                        )}
                                      </ZStack>
                                    </Button>
                    </VStack>
                  )
                })}
      </HStack>

      {nextStation && (
        <HStack>
          <Spacer />
          <HStack spacing={3}>
            <Image systemName={getStationIcon(nextStation.id)} font={10} foregroundStyle={getStationColor(nextStation.id) as Color} />
            <Text font={11} foregroundStyle="secondaryLabel">
              {"הבאה: " + nextStation.name +
                (minutesUntilStation(nextStation) > 0
                  ? " בעוד " + minutesUntilStation(nextStation) + " דק׳"
                  : " — עכשיו!")}
            </Text>
          </HStack>
        </HStack>
      )}
    </VStack>
  )
}