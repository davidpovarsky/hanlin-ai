// screens/home/AllDoneSection.tsx — All done celebration section
import {
  Section, HStack, VStack, Text, Spacer, Image,
} from "scripting"
import { getIcon, ICON_COLORS } from "../../model/index"
import { t } from "../../model/i18n"

export function AllDoneSection(props: {
  totalPoints: number
}) {
  const { totalPoints } = props

  return (
    <Section>
      <VStack spacing={10} padding={{ vertical: 14 }}>
        <HStack spacing={8}>
          <Spacer />
          <Image systemName={getIcon("allDone")} font={22} foregroundStyle={ICON_COLORS.allDone} />
          <Text font={18} fontWeight="bold">{t("allDoneTitle")}</Text>
          <Spacer />
        </HStack>
        <HStack>
          <Spacer />
          <HStack spacing={4}>
            <Image systemName={getIcon("trophy")} font={14} foregroundStyle={ICON_COLORS.trophy} />
            <Text font={15} fontWeight="semibold" foregroundStyle="secondaryLabel">{t("totalPoints", { points: totalPoints })}</Text>
          </HStack>
          <Spacer />
        </HStack>
      </VStack>
    </Section>
  )
}
