// screens/settings/DataEditorScreen.tsx — Main data editor entry
import {
  NavigationStack, List, Section, HStack, VStack, Text,
  Spacer, Button, Image, useState, Toolbar, ToolbarItem,
} from "scripting"
import { loadCustomConfig, resetConfigToDefaults, saveCustomConfig } from "../../model/customConfig"
import { AppCustomConfig } from "../../model/configTypes"
import { getIcon, ICON_COLORS } from "../../model/icons"
import { t } from "../../model/i18n"
import { MealEditorScreen } from "./MealEditorScreen"
import { AIInstructionsEditor } from "./AIInstructionsEditor"
import { HealthSettingsScreen } from "./HealthSettingsScreen"

export function DataEditorScreen(props: { onDismiss: () => void }) {
  const { onDismiss } = props
  const [config, setConfig] = useState<AppCustomConfig>(() => loadCustomConfig())
  const [showResetConfirm, setShowResetConfirm] = useState(false)
  const [editingStationId, setEditingStationId] = useState<number | null>(null)
  const [showAIEditor, setShowAIEditor] = useState(false)
  const [showHealthSettings, setShowHealthSettings] = useState(false)

  function refresh() {
    setConfig(loadCustomConfig())
  }

  function handleResetDefaults() {
    resetConfigToDefaults()
    refresh()
    setShowResetConfirm(false)
  }

  const editingStation = editingStationId !== null
    ? config.stations.find(s => s.id === editingStationId) || null
    : null

  return (
    <NavigationStack>
      <List
        navigationTitle={t("dataEditor")}
        navigationBarTitleDisplayMode="inline"
        toolbar={
          <Toolbar>
            <ToolbarItem placement="topBarTrailing">
              <Button title={t("ok")} action={onDismiss} />
            </ToolbarItem>
          </Toolbar>
        }
        sheet={[
          // Meal editor sheet
          {
            isPresented: editingStationId !== null,
            onChanged: (v: boolean) => { if (!v) { setEditingStationId(null); refresh() } },
            content: editingStation ? (
              <MealEditorScreen
                station={editingStation}
                onDismiss={() => { setEditingStationId(null); refresh() }}
              />
            ) : <Text>{""}</Text>,
          },
          // AI instructions editor sheet
          {
            isPresented: showAIEditor,
            onChanged: (v: boolean) => { if (!v) { setShowAIEditor(false); refresh() } },
            content: (
              <AIInstructionsEditor
                aiConfig={config.aiConfig}
                onDismiss={() => { setShowAIEditor(false); refresh() }}
              />
            ),
          },
          // Health settings sheet
          {
            isPresented: showHealthSettings,
            onChanged: (v: boolean) => { if (!v) { setShowHealthSettings(false); refresh() } },
            content: (
              <HealthSettingsScreen
                healthConfig={config.healthConfig}
                onDismiss={() => { setShowHealthSettings(false); refresh() }}
              />
            ),
          },
        ]}
      >
        {/* Meals / Stations */}
        <Section header={
          <HStack spacing={6}>
            <Image systemName={getIcon("food")} font={13} foregroundStyle="systemBlue" />
            <Text>{t("mealsAndTimes")}</Text>
          </HStack>
        }>
          {config.stations.map(station => (
            <Button key={station.id} action={() => setEditingStationId(station.id)}>
              <HStack spacing={10} padding={{ vertical: 4 }}>
                <Image
                  systemName={station.enabled ? "checkmark.circle.fill" : "circle"}
                  font={18}
                  foregroundStyle={station.enabled ? "systemGreen" : "tertiaryLabel"}
                />
                <VStack alignment="leading" spacing={2}>
                  <Text font={15} fontWeight="medium" foregroundStyle="label">
                    {station.name}
                  </Text>
                  <Text font={12} foregroundStyle="secondaryLabel">
                    {station.timeStart + "–" + station.timeEnd + " • " + station.suggestions.length + " " + t("suggestions")}
                  </Text>
                </VStack>
                <Spacer />
                <Image systemName="chevron.left" font={12} foregroundStyle="tertiaryLabel" />
              </HStack>
            </Button>
          ))}
        </Section>

        {/* AI Instructions */}
        <Section header={
          <HStack spacing={6}>
            <Image systemName={getIcon("ai")} font={13} foregroundStyle="systemTeal" />
            <Text>{t("aiInstructionsTitle")}</Text>
          </HStack>
        }>
          <Button action={() => setShowAIEditor(true)}>
            <HStack spacing={10} padding={{ vertical: 4 }}>
              <Image systemName="text.bubble.fill" font={18} foregroundStyle="systemPurple" />
              <VStack alignment="leading" spacing={2}>
                <Text font={15} fontWeight="medium" foregroundStyle="label">
                  {t("editAIInstructions")}
                </Text>
                <Text font={12} foregroundStyle="secondaryLabel">
                  {t("aiInstructionsDesc")}
                </Text>
              </VStack>
              <Spacer />
              <Image systemName="chevron.left" font={12} foregroundStyle="tertiaryLabel" />
            </HStack>
          </Button>
        </Section>

        {/* Health Integration */}
        <Section header={
          <HStack spacing={6}>
            <Image systemName="heart.fill" font={13} foregroundStyle="systemRed" />
            <Text>{t("healthIntegration")}</Text>
          </HStack>
        }>
          <Button action={() => setShowHealthSettings(true)}>
            <HStack spacing={10} padding={{ vertical: 4 }}>
              <Image systemName="heart.text.square.fill" font={18} foregroundStyle="systemRed" />
              <VStack alignment="leading" spacing={2}>
                <Text font={15} fontWeight="medium" foregroundStyle="label">
                  {t("healthSettings")}
                </Text>
                <Text font={12} foregroundStyle="secondaryLabel">
                  {config.healthConfig.enabled ? t("healthEnabled") : t("healthDisabled")}
                </Text>
              </VStack>
              <Spacer />
              <Image systemName="chevron.left" font={12} foregroundStyle="tertiaryLabel" />
            </HStack>
          </Button>
        </Section>

        {/* Reset */}
        <Section>
          <Button
            action={() => setShowResetConfirm(true)}
            confirmationDialog={{
              isPresented: showResetConfirm,
              onChanged: setShowResetConfirm,
              title: t("resetConfigConfirm"),
              actions: (
                <Button
                  title={t("resetToDefaults")}
                  role="destructive"
                  action={handleResetDefaults}
                />
              ),
            }}
          >
            <HStack spacing={8}>
              <Image systemName="arrow.counterclockwise" font={16} foregroundStyle="systemRed" />
              <Text font={15} foregroundStyle="systemRed">{t("resetToDefaults")}</Text>
            </HStack>
          </Button>
        </Section>
      </List>
    </NavigationStack>
  )
}
