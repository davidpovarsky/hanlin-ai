// screens/StationDetailScreen.tsx
import {
  NavigationStack, List, Section, HStack, VStack,
  Text, Spacer, TextField, Button, Image, useState, Widget,
} from "scripting"
import {
  Station, loadTodayLog, calculatePoints, completeStation,
  getStationIcon, getStationColor, getIcon, ICON_COLORS,
} from "../model/index"
import { t, getStationName } from "../model/i18n"

export function StationDetailScreen(props: {
  station: Station
  onComplete: (note: string) => void
}) {
  const { station, onComplete } = props
  const [note, setNote] = useState("")
  const todayLog = loadTodayLog()
  const isDone = todayLog.stations.some(s => s.stationId === station.id)
  const log = todayLog.stations.find(s => s.stationId === station.id)
  const potentialPoints = calculatePoints(station)

  return (
    <NavigationStack>
      <List navigationTitle={getStationName(station.id)} navigationBarTitleDisplayMode="inline">
        <Section header={<Text>{t("details")}</Text>}>
          <HStack>
            <HStack spacing={4}>
              <Image systemName={getIcon("clock")} font={13} foregroundStyle="systemBlue" />
              <Text font={14}>{t("recommendedTime")}</Text>
            </HStack>
            <Spacer />
            <Text font={14} fontWeight="semibold">{station.timeStart + "–" + station.timeEnd}</Text>
          </HStack>
          <HStack>
            <HStack spacing={4}>
              <Image systemName={getIcon("trophy")} font={13} foregroundStyle={ICON_COLORS.trophy} />
              <Text font={14}>{t("points")}</Text>
            </HStack>
            <Spacer />
            <Text font={14} fontWeight="semibold" foregroundStyle={isDone ? "systemGreen" : "systemBlue"}>
              {isDone ? "+" + log!.points : "+" + potentialPoints + " " + t("nowShort")}
            </Text>
          </HStack>
        </Section>

        <Section header={<Text>{t("suggestionsTitle")}</Text>}>
          {station.suggestions.map((s, i) => (
            <Text key={i} font={14}>{"• " + s}</Text>
          ))}
        </Section>

        {!isDone && (
          <Section header={<Text>{t("whatDidYouEat")}</Text>}>
            <TextField title={t("noteOptional")} value={note} onChanged={setNote} />
            <Button
              title={t("markDoneWithPoints", { points: potentialPoints })}
              action={() => onComplete(note)}
            />
          </Section>
        )}

        {isDone && log && (
          <Section header={<Text>{t("status")}</Text>}>
            <VStack spacing={6} padding={{ vertical: 8 }}>
              <HStack spacing={4}>
                <Image systemName={getIcon("completed")} font={14} foregroundStyle={ICON_COLORS.completed} />
                <Text font={15} fontWeight="semibold" foregroundStyle="systemGreen">{t("completed") + "!"}</Text>
              </HStack>
              {log.note ? (
                <HStack spacing={3}>
                  <Image systemName={getIcon("note")} font={12} foregroundStyle="secondaryLabel" />
                  <Text font={13} foregroundStyle="secondaryLabel">{log.note}</Text>
                </HStack>
              ) : null}
              <Text font={12} foregroundStyle="secondaryLabel">{"+" + log.points + " " + t("points")}</Text>
            </VStack>
          </Section>
        )}
      </List>
    </NavigationStack>
  )
}