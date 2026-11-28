// screens/settings/HealthSettingsScreen.tsx — Health integration settings
import {
  NavigationStack, List, Section, HStack, VStack, Text,
  Spacer, Button, Image, useState, Toggle, Toolbar, ToolbarItem,
} from "scripting"
import { HealthIntegrationConfig } from "../../model/configTypes"
import { updateHealthConfig } from "../../model/customConfig"
import { isHealthAvailable } from "../../health/healthService"
import { t } from "../../model/i18n"

export function HealthSettingsScreen(props: {
  healthConfig: HealthIntegrationConfig
  onDismiss: () => void
}) {
  const { healthConfig, onDismiss } = props
  const [enabled, setEnabled] = useState(healthConfig.enabled)
  const [trackSteps, setTrackSteps] = useState(healthConfig.trackSteps)
  const [trackCalories, setTrackCalories] = useState(healthConfig.trackCalories)
  const [trackWorkouts, setTrackWorkouts] = useState(healthConfig.trackWorkouts)
  const [trackHeartRate, setTrackHeartRate] = useState(healthConfig.trackHeartRate)
  const [trackActivityRings, setTrackActivityRings] = useState(healthConfig.trackActivityRings)
  const [saved, setSaved] = useState(false)

  const healthAvailable = isHealthAvailable()

  function handleSave() {
    updateHealthConfig({
      enabled,
      trackSteps,
      trackCalories,
      trackWorkouts,
      trackHeartRate,
      trackActivityRings,
    })
    setSaved(true)
  }

  return (
    <NavigationStack>
      <List
        navigationTitle={t("healthSettings")}
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
        {/* Availability Check */}
        {!healthAvailable && (
          <Section>
            <HStack spacing={8} padding={{ vertical: 8 }}>
              <Image systemName="exclamationmark.triangle.fill" font={18} foregroundStyle="systemOrange" />
              <Text font={14} foregroundStyle="systemOrange">
                {t("healthNotAvailable")}
              </Text>
            </HStack>
          </Section>
        )}

        {/* Master Toggle */}
        <Section header={
          <HStack spacing={6}>
            <Image systemName="heart.fill" font={13} foregroundStyle="systemRed" />
            <Text>{t("healthIntegration")}</Text>
          </HStack>
        }>
          <Toggle
            title={t("enableHealthTracking")}
            value={enabled}
            onChanged={setEnabled}
            toggleStyle="switch"
            tint="systemRed"
            disabled={!healthAvailable}
          />
          <Text font={12} foregroundStyle="secondaryLabel">
            {enabled ? t("healthTrackingOnDesc") : t("healthTrackingOffDesc")}
          </Text>
        </Section>

        {/* Individual Toggles */}
        {enabled && (
          <Section header={
            <HStack spacing={6}>
              <Image systemName="list.bullet" font={13} foregroundStyle="systemBlue" />
              <Text>{t("dataTypes")}</Text>
            </HStack>
          }>
            <Toggle
              title={t("trackSteps")}
              value={trackSteps}
              onChanged={setTrackSteps}
              toggleStyle="switch"
              tint="systemGreen"
            />
            <Toggle
              title={t("trackCalories")}
              value={trackCalories}
              onChanged={setTrackCalories}
              toggleStyle="switch"
              tint="systemOrange"
            />
            <Toggle
              title={t("trackWorkouts")}
              value={trackWorkouts}
              onChanged={setTrackWorkouts}
              toggleStyle="switch"
              tint="systemBlue"
            />
            <Toggle
              title={t("trackHeartRate")}
              value={trackHeartRate}
              onChanged={setTrackHeartRate}
              toggleStyle="switch"
              tint="systemRed"
            />
            <Toggle
              title={t("trackActivityRings")}
              value={trackActivityRings}
              onChanged={setTrackActivityRings}
              toggleStyle="switch"
              tint="systemPink"
            />
          </Section>
        )}

        {/* Info */}
        <Section>
          <Text font={12} foregroundStyle="tertiaryLabel">
            {t("healthPrivacyNote")}
          </Text>
        </Section>

        {/* Save */}
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
