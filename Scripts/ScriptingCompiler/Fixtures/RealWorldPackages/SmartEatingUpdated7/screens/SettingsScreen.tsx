// screens/SettingsScreen.tsx (Updated — adds Data Editor access)
// Storage, Widget, Notification, DateComponents, CalendarNotificationTrigger are globals
import {
  NavigationStack, List, Section, HStack, VStack, Text, Spacer, Button, Image, useState, Menu, Toggle,
} from "scripting"

declare const Storage: any
declare const Widget: any
declare const Notification: any
declare const DateComponents: any
declare const CalendarNotificationTrigger: any

import { getNotificationTimes, STATIONS, getIcon, isAIProcessingEnabled, setAIProcessingEnabled, isAIGeneralProcessingEnabled, setAIGeneralProcessingEnabled, isAIMealMenuCreationEnabled, setAIMealMenuCreationEnabled, isAIProcessingActive, isMealMenuCreationActive } from "../model/index"
import { t, getCurrentLanguage, setLanguage, Language } from "../model/i18n"
import { DataEditorScreen } from "./settings/DataEditorScreen"

async function scheduleAllNotifications() {
  await Notification.removeAllPendingsOfCurrentScript()
  const times = getNotificationTimes()
  for (const time of times) {
    const station = STATIONS.find(s => s.id === time.stationId)!
    const components = new DateComponents({ hour: time.hour, minute: time.minute })
    await Notification.schedule({
      title: station.name + " " + t("inMinutes", { minutes: 15 }),
      body: t("notificationsBody", { station: station.name }),
      trigger: new CalendarNotificationTrigger({ dateMatching: components, repeats: true }),
      interruptionLevel: "timeSensitive",
    })
  }
}

export function SettingsScreen() {
  const [notifStatus, setNotifStatus] = useState(t("clickToSetup"))
  const [currentLang, setCurrentLang] = useState<Language>(getCurrentLanguage())
  const [aiProcessing, setAiProcessing] = useState(isAIProcessingEnabled())
  const [aiGeneralProcessing, setAiGeneralProcessing] = useState(isAIGeneralProcessingEnabled())
  const [aiMealMenuCreation, setAiMealMenuCreation] = useState(isAIMealMenuCreationEnabled())
  const [showDataEditor, setShowDataEditor] = useState(false)

  async function setupNotifications() {
    try {
      await scheduleAllNotifications()
      setNotifStatus(t("notificationsSet"))
    } catch (e) {
      setNotifStatus(t("notificationsError"))
    }
  }

  function resetData() {
    Storage.clear()
    setNotifStatus(t("dataReset"))
    Widget.reloadAll()
  }

  function handleLanguageChange(lang: Language) {
    setLanguage(lang)
    setCurrentLang(lang)
    setNotifStatus(t("clickToSetup"))
  }

  return (
    <NavigationStack>
      <List
        navigationTitle={t("settingsTitle")}
        sheet={{
          isPresented: showDataEditor,
          onChanged: setShowDataEditor,
          content: (
            <DataEditorScreen onDismiss={() => setShowDataEditor(false)} />
          ),
        }}
      >
        {/* DATA EDITOR — NEW */}
        <Section header={
          <HStack spacing={6}>
            <Image systemName="slider.horizontal.3" font={15} foregroundStyle="systemIndigo" />
            <Text>{t("dataEditor")}</Text>
          </HStack>
        }>
          <Button action={() => setShowDataEditor(true)}>
            <HStack spacing={10} padding={{ vertical: 4 }}>
              <Image systemName="pencil.and.list.clipboard" font={20} foregroundStyle="systemIndigo" />
              <VStack alignment="leading" spacing={2}>
                <Text font={15} fontWeight="medium" foregroundStyle="label">
                  {t("dataEditor")}
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

        {/* Notifications */}
        <Section header={<HStack spacing={6}><Image systemName={getIcon("notification")} font={15} foregroundStyle="systemBlue" /><Text>{t("notifications")}</Text></HStack>}>
          <Button title={t("setupReminders")} action={setupNotifications} />
          <Text font={13} foregroundStyle="secondaryLabel">{notifStatus}</Text>
        </Section>

        {/* Language */}
        <Section header={<HStack spacing={6}><Image systemName={getIcon("language")} font={15} foregroundStyle="systemPurple" /><Text>{t("language")}</Text></HStack>}>
          <Menu title={`${t("language")}: ${currentLang === "he" ? t("hebrew") : t("english")}`} systemImage={getIcon("language")}>
            <Button
              title={t("hebrew")}
              action={() => handleLanguageChange("he")}
            />
            <Button
              title={t("english")}
              action={() => handleLanguageChange("en")}
            />
          </Menu>
          <Text font={12} foregroundStyle="secondaryLabel">
            {currentLang === "he" ? "השפה הוגדרה לעברית. האפליקציה תתרענן." : "Language set to English. The app will refresh."}
          </Text>
        </Section>

        {/* AI Processing */}
        <Section header={<HStack spacing={6}><Image systemName={getIcon("ai")} font={15} foregroundStyle="systemTeal" /><Text>{t("aiProcessing")}</Text></HStack>}>
          <Toggle
            title={t("aiGeneralProcessing")}
            value={aiGeneralProcessing}
            onChanged={(newValue) => {
              setAIGeneralProcessingEnabled(newValue)
              setAiGeneralProcessing(newValue)
              if (newValue) {
                setAiProcessing(true)
                setAiMealMenuCreation(true)
              }
            }}
            toggleStyle="switch"
            tint="systemGreen"
          />
          <Text font={12} foregroundStyle="secondaryLabel">
            {aiGeneralProcessing ? t("aiGeneralProcessingDescriptionOn") : t("aiGeneralProcessingDescriptionOff")}
          </Text>
          <Toggle
            title={t("aiProcessing")}
            value={aiProcessing}
            onChanged={(newValue) => {
              if (aiGeneralProcessing) return
              setAIProcessingEnabled(newValue)
              setAiProcessing(newValue)
            }}
            toggleStyle="switch"
            tint="systemBlue"
            disabled={aiGeneralProcessing}
          />
          <Text font={12} foregroundStyle="secondaryLabel">
            {aiProcessing ? t("aiProcessingDescriptionOn") : t("aiProcessingDescriptionOff")}
            {aiGeneralProcessing ? t("autoEnabledDueToGeneral") : ""}
          </Text>
          <Toggle
            title={t("aiMealMenuCreation")}
            value={aiMealMenuCreation}
            onChanged={(newValue) => {
              if (aiGeneralProcessing) return
              setAIMealMenuCreationEnabled(newValue)
              setAiMealMenuCreation(newValue)
            }}
            toggleStyle="switch"
            tint="systemOrange"
            disabled={aiGeneralProcessing}
          />
          <Text font={12} foregroundStyle="secondaryLabel">
            {aiMealMenuCreation ? t("aiMealMenuCreationDescriptionOn") : t("aiMealMenuCreationDescriptionOff")}
            {aiGeneralProcessing ? t("autoEnabledDueToGeneral") : ""}
          </Text>
        </Section>

        {/* Widget */}
        <Section header={<HStack spacing={6}><Image systemName={getIcon("refresh")} font={15} foregroundStyle="systemGreen" /><Text>{t("widget")}</Text></HStack>}>
          <Button title={t("refreshWidget")} action={() => Widget.reloadAll()} />
          <Text font={12} foregroundStyle="secondaryLabel">
            {t("widgetInstructions")}
          </Text>
        </Section>

        {/* Data Reset */}
        <Section header={<HStack spacing={6}><Image systemName={getIcon("trash")} font={15} foregroundStyle="systemRed" /><Text>{t("data")}</Text></HStack>}>
          <Button title={t("resetData")} action={resetData} />
        </Section>

        {/* Info */}
        <Section header={<HStack spacing={6}><Image systemName={getIcon("info")} font={15} foregroundStyle="systemGray" /><Text>{t("info")}</Text></HStack>}>
          <HStack>
            <Text font={14}>{t("version")}</Text>
            <Spacer />
            <Text font={14} foregroundStyle="secondaryLabel">{"1.1"}</Text>
          </HStack>
          <VStack alignment="leading" spacing={4} padding={{ vertical: 4 }}>
            <Text font={13} foregroundStyle="secondaryLabel">
              {t("appDescription")}
            </Text>
            <Text font={12} foregroundStyle="tertiaryLabel">
              {t("aiDescription")}
            </Text>
          </VStack>
        </Section>
      </List>
    </NavigationStack>
  )
}
