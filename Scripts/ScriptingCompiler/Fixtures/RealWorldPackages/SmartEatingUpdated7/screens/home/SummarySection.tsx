// screens/home/SummarySection.tsx — Summary header with streak, progress, points
import {
  Section, HStack, VStack, Text, Spacer, ProgressView, Image,
} from "scripting"
import { DayLog, getIcon, ICON_COLORS } from "../../model/index"
import { t } from "../../model/i18n"

export function SummarySection(props: {
  completed: number
  streak: number
  encouragement: string
  todayPoints: number
}) {
  const { completed, streak, encouragement, todayPoints } = props

  return (
    <Section>
      <VStack spacing={10} padding={{ vertical: 8 }}>
        <HStack>
          <VStack alignment="leading" spacing={4}>
            {streak > 0 ? (
              <HStack spacing={6}>
                <Image systemName={getIcon("streak")} font={22} foregroundStyle={ICON_COLORS.streak} />
                <Text font={24} fontWeight="bold">{String(streak)}</Text>
                <Text font={15} foregroundStyle="secondaryLabel">{t("streakDays")}</Text>
              </HStack>
            ) : (
              <Text font={16} fontWeight="semibold" foregroundStyle="secondaryLabel">{t("startNewStreak")}</Text>
            )}
            <Text font={13} foregroundStyle="secondaryLabel">{encouragement}</Text>
          </VStack>
          <Spacer />
          <VStack alignment="trailing" spacing={2}>
            <Text font={34} fontWeight="bold" foregroundStyle="systemGreen">{completed + "/5"}</Text>
            <HStack spacing={3}>
              <Image systemName={getIcon("points")} font={11} foregroundStyle={ICON_COLORS.points} />
              <Text font={13} foregroundStyle="secondaryLabel">{todayPoints + " " + t("points")}</Text>
            </HStack>
          </VStack>
        </HStack>
        <ProgressView value={completed} total={5} progressViewStyle="linear" tint="systemGreen" />
      </VStack>
    </Section>
  )
}
