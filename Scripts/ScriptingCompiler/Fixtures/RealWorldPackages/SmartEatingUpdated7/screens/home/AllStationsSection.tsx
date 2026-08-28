// screens/home/AllStationsSection.tsx — List of all stations
import {
  Section, HStack, VStack, Text, Spacer, Button, Image,
} from "scripting"
import {
  Station, StationLog, STATIONS, getStationTimeStatus,
  getStationIcon, getStationColor, getIcon, ICON_COLORS,
} from "../../model/index"
import { t, getStationName } from "../../model/i18n"

export function AllStationsSection(props: {
  completedIds: Set<number>
  stationLogs: StationLog[]
  onOpenStation: (stationId: number) => void
}) {
  const { completedIds, stationLogs, onOpenStation } = props

  return (
    <Section header={
      <HStack spacing={6}>
        <Image systemName={getIcon("food")} font={13} foregroundStyle="systemBlue" />
        <Text>{t("allStations")}</Text>
      </HStack>
    }>
      {STATIONS.map(station => {
        const isDone = completedIds.has(station.id)
        const log = stationLogs.find(s => s.stationId === station.id)
        const timeStatus = getStationTimeStatus(station)
        const isSkipped = !isDone && timeStatus === "passed"

        return (
          <Button key={station.id} action={() => onOpenStation(station.id)}>
            <HStack spacing={10} padding={{ vertical: 5 }}>
              {/* Icon */}
              {isDone ? (
                <Image systemName={getIcon("completed")} font={22} foregroundStyle={ICON_COLORS.completed} />
              ) : isSkipped ? (
                <HStack spacing={2}>
                  <Image systemName={getStationIcon(station.id)} font={22} foregroundStyle="systemRed" />
                  <Image systemName={getIcon("skipped")} font={12} foregroundStyle="systemRed" />
                </HStack>
              ) : (
                <Image systemName={getStationIcon(station.id)} font={22} foregroundStyle={getStationColor(station.id) as any} />
              )}

              {/* Info */}
              <VStack alignment="leading" spacing={2}>
                <HStack spacing={6}>
                  <Text
                    font={15}
                    fontWeight="medium"
                    foregroundStyle={isDone ? "secondaryLabel" : (isSkipped ? "systemRed" : "label")}
                    strikethrough={isDone ? { color: "secondaryLabel", pattern: "solid" } : undefined}
                  >
                    {getStationName(station.id)}
                  </Text>
                  {isDone && log ? (
                    <Text font={12} fontWeight="medium" foregroundStyle="systemGreen">{"+" + log.points}</Text>
                  ) : null}
                </HStack>
                <Text font={12} foregroundStyle="tertiaryLabel">
                  {station.timeStart + "–" + station.timeEnd}
                </Text>
                {/* Show what was eaten */}
                {isDone && log && log.note ? (
                  <HStack spacing={4}>
                    <Image systemName={getIcon("note")} font={10} foregroundStyle="secondaryLabel" />
                    <Text font={12} foregroundStyle="secondaryLabel" lineLimit={1}>{log.note}</Text>
                  </HStack>
                ) : isDone && log && !log.note ? (
                  <HStack spacing={4}>
                    <Image systemName={getIcon("edit")} font={10} foregroundStyle="tertiaryLabel" />
                    <Text font={11} foregroundStyle="tertiaryLabel">{t("noNoteYet")}</Text>
                  </HStack>
                ) : null}
              </VStack>
              <Spacer />

              {/* Action indicators */}
              {isDone ? (
                <Image systemName="pencil.circle" font={16} foregroundStyle="tertiaryLabel" />
              ) : (
                <Image systemName="chevron.left" font={12} foregroundStyle="tertiaryLabel" />
              )}
            </HStack>
          </Button>
        )
      })}
    </Section>
  )
}
