// screens/settings/MealEditorScreen.tsx — Edit a single meal station
import {
  NavigationStack, List, Section, HStack, VStack, Text,
  Spacer, TextField, Button, Image, useState, Toggle,
  Toolbar, ToolbarItem,
} from "scripting"
import { CustomStation } from "../../model/configTypes"
import { updateStation } from "../../model/customConfig"
import { getIcon } from "../../model/icons"
import { t } from "../../model/i18n"
import { STATION_ICONS, STATION_ICON_MAP } from "../../model/icons"

export function MealEditorScreen(props: {
  station: CustomStation
  onDismiss: () => void
}) {
  const { station, onDismiss } = props
  const [name, setName] = useState(station.name)
  const [timeStart, setTimeStart] = useState(station.timeStart)
  const [timeEnd, setTimeEnd] = useState(station.timeEnd)
  const [enabled, setEnabled] = useState(station.enabled)
  const [suggestions, setSuggestions] = useState<string[]>([...station.suggestions])
  const [newSuggestion, setNewSuggestion] = useState("")
  const [saved, setSaved] = useState(false)

  function handleSave() {
    updateStation(station.id, {
      name: name.trim() || station.name,
      timeStart,
      timeEnd,
      enabled,
      suggestions: suggestions.filter(s => s.trim()),
    })
    setSaved(true)
  }

  function addSuggestion() {
    const trimmed = newSuggestion.trim()
    if (trimmed) {
      setSuggestions([...suggestions, trimmed])
      setNewSuggestion("")
    }
  }

  function removeSuggestion(index: number) {
    setSuggestions(suggestions.filter((_, i) => i !== index))
  }

  return (
    <NavigationStack>
      <List
        navigationTitle={t("editMealStation")}
        navigationBarTitleDisplayMode="inline"
        toolbar={
          <Toolbar>
            <ToolbarItem placement="topBarTrailing">
              <Button title={t("ok")} action={onDismiss} />
            </ToolbarItem>
          </Toolbar>
        }
        presentationDetents={["large"]}
        presentationDragIndicator="visible"
      >
        {/* Basic Info */}
        <Section header={
          <HStack spacing={6}>
            <Image systemName={getIcon("edit")} font={13} foregroundStyle="systemBlue" />
            <Text>{t("basicInfo")}</Text>
          </HStack>
        }>
          <TextField
            title={t("mealName")}
            value={name}
            onChanged={setName}
          />
          <Toggle
            title={t("mealEnabled")}
            value={enabled}
            onChanged={setEnabled}
            toggleStyle="switch"
            tint="systemGreen"
          />
        </Section>

        {/* Time Window */}
        <Section header={
          <HStack spacing={6}>
            <Image systemName={getIcon("clock")} font={13} foregroundStyle="systemOrange" />
            <Text>{t("timeWindow")}</Text>
          </HStack>
        }>
          <HStack spacing={8}>
            <Text font={14}>{t("startTime")}</Text>
            <Spacer />
            <TextField
              title="HH:mm"
              value={timeStart}
              onChanged={setTimeStart}
            />
          </HStack>
          <HStack spacing={8}>
            <Text font={14}>{t("endTime")}</Text>
            <Spacer />
            <TextField
              title="HH:mm"
              value={timeEnd}
              onChanged={setTimeEnd}
            />
          </HStack>
          <Text font={11} foregroundStyle="tertiaryLabel">
            {t("timeFormat")}
          </Text>
        </Section>

        {/* Suggestions */}
        <Section header={
          <HStack spacing={6}>
            <Image systemName={getIcon("suggestions")} font={13} foregroundStyle="systemPurple" />
            <Text>{t("mealSuggestions") + " (" + suggestions.length + ")"}</Text>
          </HStack>
        }>
          {suggestions.map((s, i) => (
            <HStack key={i} spacing={8} padding={{ vertical: 2 }}>
              <Text font={14} foregroundStyle="label">{"• " + s}</Text>
              <Spacer />
              <Button action={() => removeSuggestion(i)}>
                <Image systemName="minus.circle.fill" font={16} foregroundStyle="systemRed" />
              </Button>
            </HStack>
          ))}
          <HStack spacing={8}>
            <TextField
              title={t("addSuggestion")}
              value={newSuggestion}
              onChanged={setNewSuggestion}
            />
            <Button action={addSuggestion}>
              <Image
                systemName="plus.circle.fill"
                font={20}
                foregroundStyle={newSuggestion.trim() ? "systemGreen" : "tertiaryLabel"}
              />
            </Button>
          </HStack>
        </Section>

        {/* Save Button */}
        <Section>
          {saved ? (
            <HStack spacing={8} padding={{ vertical: 6 }}>
              <Spacer />
              <Image systemName="checkmark.circle.fill" font={20} foregroundStyle="systemGreen" />
              <Text font={16} fontWeight="semibold" foregroundStyle="systemGreen">{t("mealSaved")}</Text>
              <Spacer />
            </HStack>
          ) : (
            <Button action={handleSave}>
              <HStack spacing={8} padding={{ vertical: 4 }}>
                <Spacer />
                <Image systemName="checkmark.circle.fill" font={18} foregroundStyle="systemBlue" />
                <Text font={16} fontWeight="semibold" foregroundStyle="systemBlue">{t("save")}</Text>
                <Spacer />
              </HStack>
            </Button>
          )}
        </Section>
      </List>
    </NavigationStack>
  )
}
