// screens/home/AiSuggestSheet.tsx — AI menu suggestion bottom sheet
import {
  NavigationStack, List, Section, HStack, VStack, Text,
  Spacer, Button, Image, Toolbar, ToolbarItem,
} from "scripting"
import {
  Station, getStationIcon, getStationColor, getIcon,
} from "../../model/index"
import { t, getStationName } from "../../model/i18n"

export function AiSuggestSheet(props: {
  station: Station | null
  aiResult: string
  aiLoading: boolean
  aiConvId: string
  onContinueInChat: () => void
  onDismiss: () => void
}) {
  const { station, aiResult, aiLoading, aiConvId, onContinueInChat, onDismiss } = props

  return (
    <NavigationStack>
      <List
        navigationTitle={t("aiSuggestTitle")}
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
        {station ? (
          <Section>
            <HStack spacing={10} padding={{ vertical: 6 }}>
              <Image
                systemName={getStationIcon(station.id)}
                font={24}
                foregroundStyle={getStationColor(station.id) as any}
              />
              <VStack alignment="leading" spacing={2}>
                <Text font={16} fontWeight="semibold">{getStationName(station.id)}</Text>
                <Text font={13} foregroundStyle="secondaryLabel">{station.timeStart + "–" + station.timeEnd}</Text>
              </VStack>
            </HStack>
          </Section>
        ) : null}

        <Section header={
          <HStack spacing={6}>
            <Image systemName={getIcon("aiSuggest")} font={13} foregroundStyle="systemPurple" />
            <Text>{t("aiSuggestTitle")}</Text>
          </HStack>
        }>
          {aiLoading && !aiResult ? (
            <HStack spacing={8} padding={{ vertical: 12 }}>
              <Spacer />
              <Image systemName="ellipsis.circle" font={16} foregroundStyle="systemPurple" />
              <Text font={14} foregroundStyle="secondaryLabel">{t("thinking")}</Text>
              <Spacer />
            </HStack>
          ) : (
            <Text
              font={14}
              foregroundStyle={aiLoading ? "secondaryLabel" : "label"}
              lineLimit={100}
              padding={{ vertical: 4 }}
            >
              {aiResult + (aiLoading ? " ..." : "")}
            </Text>
          )}
        </Section>

        {!aiLoading && aiResult && aiConvId ? (
          <Section>
            <Button action={onContinueInChat}>
              <HStack spacing={8} padding={{ vertical: 6 }}>
                <Spacer />
                <Image systemName="bubble.left.and.bubble.right.fill" font={18} foregroundStyle="systemGreen" />
                <Text font={14} fontWeight="medium" foregroundStyle="systemGreen">{t("continueInAiChat")}</Text>
                <Image systemName="arrow.right" font={12} foregroundStyle="systemGreen" />
                <Spacer />
              </HStack>
            </Button>
          </Section>
        ) : null}
      </List>
    </NavigationStack>
  )
}
