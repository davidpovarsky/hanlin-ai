// screens/settings/AIInstructionsEditor.tsx — Edit AI system prompts and config
import {
  NavigationStack, List, Section, HStack, VStack, Text,
  Spacer, TextField, Button, Image, useState, Toggle, Menu,
  Toolbar, ToolbarItem,
} from "scripting"
import { CustomAIConfig } from "../../model/configTypes"
import { updateAIConfig } from "../../model/customConfig"
import { getIcon } from "../../model/icons"
import { t } from "../../model/i18n"

export function AIInstructionsEditor(props: {
  aiConfig: CustomAIConfig
  onDismiss: () => void
}) {
  const { aiConfig, onDismiss } = props
  const [systemPrompt, setSystemPrompt] = useState(aiConfig.systemPrompt)
  const [encouragementPrompt, setEncouragementPrompt] = useState(aiConfig.encouragementPrompt)
  const [menuSuggestPrompt, setMenuSuggestPrompt] = useState(aiConfig.menuSuggestPrompt)
  const [analysisPrompt, setAnalysisPrompt] = useState(aiConfig.analysisPrompt)
  const [provider, setProvider] = useState(aiConfig.provider)
  const [useHealthData, setUseHealthData] = useState(aiConfig.useHealthData)
  const [saved, setSaved] = useState(false)

  function handleSave() {
    updateAIConfig({
      systemPrompt: systemPrompt.trim(),
      encouragementPrompt: encouragementPrompt.trim(),
      menuSuggestPrompt: menuSuggestPrompt.trim(),
      analysisPrompt: analysisPrompt.trim(),
      provider,
      useHealthData,
    })
    setSaved(true)
  }

  const providerNames: Record<string, string> = {
    deepseek: "DeepSeek",
    openai: "OpenAI",
    anthropic: "Anthropic",
    gemini: "Gemini",
  }

  return (
    <NavigationStack>
      <List
        navigationTitle={t("editAIInstructions")}
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
        {/* Main System Prompt */}
        <Section header={
          <HStack spacing={6}>
            <Image systemName="text.bubble.fill" font={13} foregroundStyle="systemPurple" />
            <Text>{t("mainSystemPrompt")}</Text>
          </HStack>
        }>
          <TextField
            title={t("systemPromptPlaceholder")}
            value={systemPrompt}
            onChanged={setSystemPrompt}
            axis="vertical"
            lineLimit={{ min: 3, max: 8 }}
          />
          <Text font={11} foregroundStyle="tertiaryLabel">
            {t("systemPromptHelp")}
          </Text>
        </Section>

        {/* Encouragement Prompt */}
        <Section header={
          <HStack spacing={6}>
            <Image systemName={getIcon("encourage")} font={13} foregroundStyle="systemOrange" />
            <Text>{t("encouragementPromptTitle")}</Text>
          </HStack>
        }>
          <TextField
            title={t("encouragementPromptPlaceholder")}
            value={encouragementPrompt}
            onChanged={setEncouragementPrompt}
            axis="vertical"
            lineLimit={{ min: 2, max: 6 }}
          />
        </Section>

        {/* Menu Suggest Prompt */}
        <Section header={
          <HStack spacing={6}>
            <Image systemName={getIcon("aiSuggest")} font={13} foregroundStyle="systemTeal" />
            <Text>{t("menuPromptTitle")}</Text>
          </HStack>
        }>
          <TextField
            title={t("menuPromptPlaceholder")}
            value={menuSuggestPrompt}
            onChanged={setMenuSuggestPrompt}
            axis="vertical"
            lineLimit={{ min: 2, max: 6 }}
          />
        </Section>

        {/* Analysis Prompt */}
        <Section header={
          <HStack spacing={6}>
            <Image systemName={getIcon("analyze")} font={13} foregroundStyle="systemBlue" />
            <Text>{t("analysisPromptTitle")}</Text>
          </HStack>
        }>
          <TextField
            title={t("analysisPromptPlaceholder")}
            value={analysisPrompt}
            onChanged={setAnalysisPrompt}
            axis="vertical"
            lineLimit={{ min: 2, max: 6 }}
          />
        </Section>

        {/* Provider Selection */}
        <Section header={
          <HStack spacing={6}>
            <Image systemName="cpu" font={13} foregroundStyle="systemGray" />
            <Text>{t("aiProvider")}</Text>
          </HStack>
        }>
          <Menu title={t("provider") + ": " + providerNames[provider]} systemImage="cpu">
            <Button title="DeepSeek" action={() => setProvider("deepseek")} />
            <Button title="OpenAI" action={() => setProvider("openai")} />
            <Button title="Anthropic" action={() => setProvider("anthropic")} />
            <Button title="Gemini" action={() => setProvider("gemini")} />
          </Menu>
        </Section>

        {/* Health Data Toggle */}
        <Section header={
          <HStack spacing={6}>
            <Image systemName="heart.fill" font={13} foregroundStyle="systemRed" />
            <Text>{t("healthDataForAI")}</Text>
          </HStack>
        }>
          <Toggle
            title={t("includeHealthInAI")}
            value={useHealthData}
            onChanged={setUseHealthData}
            toggleStyle="switch"
            tint="systemRed"
          />
          <Text font={11} foregroundStyle="tertiaryLabel">
            {t("healthDataForAIDesc")}
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
