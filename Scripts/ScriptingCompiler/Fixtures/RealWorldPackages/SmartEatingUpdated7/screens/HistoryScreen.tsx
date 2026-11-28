// screens/HistoryScreen.tsx
import {
  NavigationStack, List, Section, HStack, VStack,
  Text, Spacer, Image, Chart, BarChart,
} from "scripting"
import { loadAppData, getWeekHistory, getIcon, ICON_COLORS } from "../model/index"
import { t } from "../model/i18n"

export function HistoryScreen() {
  const appData = loadAppData()
  const weekData = getWeekHistory(appData)

  const chartMarks = weekData.map(d => ({ label: d.day, value: d.count }))
  const pointsMarks = weekData.map(d => ({ label: d.day, value: d.points }))

  return (
    <NavigationStack>
      <List navigationTitle={t("historyTitle")}>
        <Section header={<Text>{t("weeklyCompleted")}</Text>}>
          <Chart frame={{ height: 200 }}>
            <BarChart marks={chartMarks} />
          </Chart>
        </Section>

        <Section header={<Text>{t("weeklyPoints")}</Text>}>
          <Chart frame={{ height: 200 }}>
            <BarChart marks={pointsMarks} />
          </Chart>
        </Section>

        <Section header={<Text>{t("statistics")}</Text>}>
          <HStack>
            <HStack spacing={4}>
              <Image systemName={getIcon("streak")} font={13} foregroundStyle={ICON_COLORS.streak} />
              <Text font={14}>{t("currentStreak")}</Text>
            </HStack>
            <Spacer />
            <Text font={14} fontWeight="bold">{appData.streak + " " + t("days")}</Text>
          </HStack>
          <HStack>
            <HStack spacing={4}>
              <Image systemName={getIcon("calendar")} font={13} foregroundStyle="systemBlue" />
              <Text font={14}>{t("loggedDays")}</Text>
            </HStack>
            <Spacer />
            <Text font={14} fontWeight="bold">{appData.history.length + ""}</Text>
          </HStack>
          {appData.history.length > 0 && (
            <HStack>
              <HStack spacing={4}>
                <Image systemName={getIcon("average")} font={13} foregroundStyle={ICON_COLORS.points} />
                <Text font={14}>{t("dailyAvgPoints")}</Text>
              </HStack>
              <Spacer />
              <Text font={14} fontWeight="bold">
                {Math.round(
                  appData.history.reduce((sum, d) => sum + d.totalPoints, 0) / appData.history.length
                ) + ""}
              </Text>
            </HStack>
          )}
        </Section>

        <Section header={<Text>{t("dayDetails")}</Text>}>
          {[...weekData].reverse().map((d, i) => (
            <HStack key={i} spacing={8}>
              <Text font={14} fontWeight="medium">{d.day}</Text>
              <Spacer />
              <Text font={13} foregroundStyle={d.count >= 3 ? "systemGreen" : "secondaryLabel"}>
                {d.count + "/5 " + t("stations")}
              </Text>
              <Text font={13} foregroundStyle="secondaryLabel">{d.points + " " + t("pointsShort")}</Text>
            </HStack>
          ))}
        </Section>
      </List>
    </NavigationStack>
  )
}