// screens/home/SkippedSection.tsx — Skipped meals warning section
import {
  Section, HStack, VStack, Text, Spacer, Button, Image,
} from "scripting"
import {
  Station, getStationIcon, getIcon,
} from "../../model/index"
import { t, getStationName } from "../../model/i18n"

export function SkippedSection(props: {
  skippedStations: Station[]
  onOpenStation: (stationId: number) => void
}) {
  const { skippedStations, onOpenStation } = props

  if (skippedStations.length === 0) return null

  return (
    <Section header={
      <HStack spacing={6}>
        <Image systemName={getIcon("skipped")} font={13} foregroundStyle="systemRed" />
        <Text foregroundStyle="systemRed">{t("skippedMeals")}</Text>
      </HStack>
    }>
      {skippedStations.map(station => (
        <Button key={station.id} action={() => onOpenStation(station.id)}>
          <HStack spacing={10} padding={{ vertical: 4 }}>
            <HStack spacing={4}>
              <Image
                systemName={getStationIcon(station.id)}
                font={20}
                foregroundStyle="systemRed"
              />
              <Image
                systemName={getIcon("skipped")}
                font={12}
                foregroundStyle="systemRed"
              />
            </HStack>
            <VStack alignment="leading" spacing={2}>
              <Text font={15} fontWeight="medium" foregroundStyle="label">{getStationName(station.id)}</Text>
              <Text font={12} foregroundStyle="systemRed">{t("skippedWarning") + " • " + station.timeStart + "–" + station.timeEnd}</Text>
            </VStack>
            <Spacer />
            <Image systemName="chevron.left" font={12} foregroundStyle="tertiaryLabel" />
          </HStack>
        </Button>
      ))}
    </Section>
  )
}
