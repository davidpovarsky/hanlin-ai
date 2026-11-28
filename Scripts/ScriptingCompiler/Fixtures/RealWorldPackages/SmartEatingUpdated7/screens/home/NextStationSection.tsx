// screens/home/NextStationSection.tsx — Next upcoming station section
import {
  Section, HStack, VStack, Text, Spacer, Button, Image,
} from "scripting"
import {
  Station, getStationTimeStatus, minutesUntilStation,
  getStationIcon, getStationColor, getIcon, ICON_COLORS,
} from "../../model/index"
import { t, getStationName } from "../../model/i18n"

export function NextStationSection(props: {
  nextStation: Station
  onOpenStation: (stationId: number) => void
}) {
  const { nextStation, onOpenStation } = props
  const timeStatus = getStationTimeStatus(nextStation)
  const mins = minutesUntilStation(nextStation)

  return (
    <Section header={
      <HStack spacing={6}>
        <Image systemName={getIcon("nextStation")} font={13} foregroundStyle="systemBlue" />
        <Text>{t("upcoming")}</Text>
      </HStack>
    }>
      <Button action={() => onOpenStation(nextStation.id)}>
        <HStack spacing={12} padding={{ vertical: 6 }}>
          <VStack>
            <Image
              systemName={getStationIcon(nextStation.id)}
              font={30}
              foregroundStyle={getStationColor(nextStation.id) as any}
            />
          </VStack>
          <VStack alignment="leading" spacing={3}>
            <Text font={17} fontWeight="semibold">{getStationName(nextStation.id)}</Text>
            <HStack spacing={6}>
              <Text font={13} foregroundStyle="secondaryLabel">{nextStation.timeStart + "–" + nextStation.timeEnd}</Text>
              {timeStatus === "active" ? (
                <HStack spacing={3}>
                  <Image systemName={getIcon("timeNow")} font={11} foregroundStyle="systemGreen" />
                  <Text font={12} fontWeight="semibold" foregroundStyle="systemGreen">{t("stationActive")}</Text>
                </HStack>
              ) : timeStatus === "upcoming" && mins > 0 ? (
                <Text font={12} foregroundStyle="systemBlue">{t("stationUpcoming", { minutes: mins })}</Text>
              ) : timeStatus === "late" ? (
                <HStack spacing={3}>
                  <Image systemName={getIcon("warning")} font={11} foregroundStyle="systemOrange" />
                  <Text font={12} fontWeight="semibold" foregroundStyle="systemOrange">{t("stationLate")}</Text>
                </HStack>
              ) : null}
            </HStack>
          </VStack>
          <Spacer />
          <Image systemName="chevron.left" font={14} foregroundStyle="tertiaryLabel" />
        </HStack>
      </Button>
      {/* Quick complete button */}
      <Button action={() => onOpenStation(nextStation.id)}>
        <HStack spacing={8} padding={{ vertical: 2 }}>
          <Spacer />
          <Image systemName="checkmark.circle.fill" font={16} foregroundStyle="systemGreen" />
          <Text font={14} fontWeight="medium" foregroundStyle="systemGreen">{t("markDone")}</Text>
          <Spacer />
        </HStack>
      </Button>
    </Section>
  )
}
