// screens/home/MealDetailSheet.tsx — Meal detail bottom sheet
import {
  NavigationStack, List, Section, HStack, VStack, Text,
  Spacer, TextField, Button, Image, useState, Toolbar, ToolbarItem,
} from "scripting"
import {
  Station, calculatePoints, getStationTimeStatus,
  getStationIcon, getStationColor, getIcon, ICON_COLORS,
} from "../../model/index"
import { t, getStationName } from "../../model/i18n"

export function MealDetailSheet(props: {
  station: Station
  isDone: boolean
  existingNote: string
  onComplete: (note: string) => void
  onUpdateNote: (note: string) => void
  onAiSuggest: () => void
  onDismiss: () => void
}) {
  const { station, isDone, existingNote, onComplete, onUpdateNote, onAiSuggest, onDismiss } = props
  const [note, setNote] = useState(existingNote)
  const [saved, setSaved] = useState(false)
  const potentialPoints = calculatePoints(station)
  const timeStatus = getStationTimeStatus(station)

  function handleSave() {
    if (isDone) {
      onUpdateNote(note)
    } else {
      onComplete(note)
    }
    setSaved(true)
  }

  return (
    <NavigationStack>
      <List
        navigationTitle={getStationName(station.id)}
        navigationBarTitleDisplayMode="inline"
        toolbar={
          <Toolbar>
            <ToolbarItem placement="topBarTrailing">
              <Button title={t("ok")} action={onDismiss} />
            </ToolbarItem>
          </Toolbar>
        }
        presentationDetents={["medium", "large"]}
        presentationDragIndicator="visible"
      >
        {/* Station Info Header */}
        <Section>
          <VStack spacing={10} padding={{ vertical: 8 }}>
            <HStack spacing={12}>
              <Image
                systemName={getStationIcon(station.id)}
                font={32}
                foregroundStyle={getStationColor(station.id) as any}
              />
              <VStack alignment="leading" spacing={4}>
                <Text font={18} fontWeight="bold">{getStationName(station.id)}</Text>
                <HStack spacing={6}>
                  <Image systemName={getIcon("clock")} font={12} foregroundStyle="secondaryLabel" />
                  <Text font={13} foregroundStyle="secondaryLabel">
                    {station.timeStart + "–" + station.timeEnd}
                  </Text>
                  {timeStatus === "active" ? (
                    <Text font={12} fontWeight="semibold" foregroundStyle="systemGreen">{t("stationActive")}</Text>
                  ) : timeStatus === "late" ? (
                    <Text font={12} fontWeight="semibold" foregroundStyle="systemOrange">{t("stationLate")}</Text>
                  ) : timeStatus === "passed" ? (
                    <Text font={12} fontWeight="semibold" foregroundStyle="systemRed">{t("stationPassed")}</Text>
                  ) : null}
                </HStack>
              </VStack>
              <Spacer />
              {isDone ? (
                <Image systemName={getIcon("completed")} font={24} foregroundStyle={ICON_COLORS.completed} />
              ) : (
                <VStack alignment="trailing">
                  <Text font={20} fontWeight="bold" foregroundStyle="systemBlue">{"+" + potentialPoints}</Text>
                  <Text font={11} foregroundStyle="secondaryLabel">{t("pointsShort")}</Text>
                </VStack>
              )}
            </HStack>
          </VStack>
        </Section>

        {/* What did you eat input */}
        <Section header={
          <HStack spacing={6}>
            <Image systemName={getIcon("mealLog")} font={13} foregroundStyle="systemBlue" />
            <Text>{t("whatDidYouEatDetail")}</Text>
          </HStack>
        }>
          <TextField
            title={t("enterMealNote")}
            value={note}
            onChanged={setNote}
            axis="vertical"
            lineLimit={{ min: 2, max: 6 }}
          />
        </Section>

        {/* Suggestions */}
        <Section header={
          <HStack spacing={6}>
            <Image systemName={getIcon("suggestions")} font={13} foregroundStyle="systemPurple" />
            <Text>{t("suggestionsTitle")}</Text>
          </HStack>
        }>
          {station.suggestions.map((s, i) => (
            <Button key={i} action={() => {
              const current = note.trim()
              setNote(current ? current + ", " + s : s)
            }}>
              <HStack spacing={8}>
                <Text font={14} foregroundStyle="label">{"• " + s}</Text>
                <Spacer />
                <Image systemName="plus.circle" font={14} foregroundStyle="systemBlue" />
              </HStack>
            </Button>
          ))}
        </Section>

        {/* AI Suggest Button */}
        <Section>
          <Button action={onAiSuggest}>
            <HStack spacing={8}>
              <Image systemName={getIcon("aiSuggest")} font={18} foregroundStyle="systemPurple" />
              <Text font={15} fontWeight="medium" foregroundStyle="systemPurple">{t("aiSuggestMeal")}</Text>
              <Spacer />
              <Image systemName="chevron.left" font={12} foregroundStyle="tertiaryLabel" />
            </HStack>
          </Button>
        </Section>

        {/* Save / Complete Button */}
        <Section>
          {saved ? (
            <VStack spacing={8} padding={{ vertical: 6 }}>
              <HStack spacing={8}>
                <Spacer />
                <Image systemName="checkmark.circle.fill" font={20} foregroundStyle="systemGreen" />
                <Text font={16} fontWeight="semibold" foregroundStyle="systemGreen">{t("mealSaved")}</Text>
                <Spacer />
              </HStack>
              <Button action={onDismiss}>
                <HStack>
                  <Spacer />
                  <Text font={14} foregroundStyle="systemBlue">{t("ok")}</Text>
                  <Spacer />
                </HStack>
              </Button>
            </VStack>
          ) : (
            <Button action={handleSave}>
              <HStack spacing={8} padding={{ vertical: 4 }}>
                <Spacer />
                <Image
                  systemName={isDone ? "pencil.circle.fill" : "checkmark.circle.fill"}
                  font={18}
                  foregroundStyle={isDone ? "systemBlue" : "systemGreen"}
                />
                <Text font={16} fontWeight="semibold" foregroundStyle={isDone ? "systemBlue" : "systemGreen"}>
                  {isDone ? t("updateMeal") : t("completeAndSave", { points: potentialPoints })}
                </Text>
                <Spacer />
              </HStack>
            </Button>
          )}
        </Section>
      </List>
    </NavigationStack>
  )
}
