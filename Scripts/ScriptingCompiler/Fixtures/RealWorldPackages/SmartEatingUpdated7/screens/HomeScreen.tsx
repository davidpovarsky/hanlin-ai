// screens/HomeScreen.tsx — Main home screen (orchestrator)
// Storage, Widget are globals — do NOT import from "scripting"
import {
  NavigationStack, List, Text, useState, Widget,
} from "scripting"
import {
  DayLog, AppData, Station, STATIONS,
  loadTodayLog, loadAppData, completeStation, updateStationNote,
  getNextStationByTime, getSkippedStations, getEncouragement,
} from "../model/index"
import { t, getStationName } from "../model/i18n"

// Home sub-components
import { SummarySection } from "./home/SummarySection"
import { SkippedSection } from "./home/SkippedSection"
import { NextStationSection } from "./home/NextStationSection"
import { AllStationsSection } from "./home/AllStationsSection"
import { AllDoneSection } from "./home/AllDoneSection"
import { MealDetailSheet } from "./home/MealDetailSheet"
import { AiSuggestSheet } from "./home/AiSuggestSheet"
import { saveMealSuggestionToChat } from "./home/chatHelpers"

declare const Assistant: any

export function HomeScreen(props: { tabSelection?: { value: number } }) {
  const { tabSelection } = props
  const [todayLog, setTodayLog] = useState<DayLog>(loadTodayLog())
  const [appData, setAppData] = useState<AppData>(loadAppData())
  const [sheetStationId, setSheetStationId] = useState<number | null>(null)
  const [showSheet, setShowSheet] = useState(false)
  // AI suggest state
  const [aiSheetStation, setAiSheetStation] = useState<Station | null>(null)
  const [showAiSheet, setShowAiSheet] = useState(false)
  const [aiLoading, setAiLoading] = useState(false)
  const [aiResult, setAiResult] = useState("")
  const [aiConvId, setAiConvId] = useState("")

  const completed = todayLog.stations.length
  const completedIds = new Set(todayLog.stations.map(s => s.stationId))
  const nextStation = getNextStationByTime(todayLog)
  const skippedStations = getSkippedStations(todayLog)
  const encouragement = getEncouragement(todayLog, appData)
  const streak = appData.streak

  // ── Data helpers ──────────────────────────────────────────────
  function refreshData() {
    setTodayLog(loadTodayLog())
    setAppData(loadAppData())
  }

  function openMealSheet(stationId: number) {
    setSheetStationId(stationId)
    setShowSheet(true)
  }

  function handleComplete(stationId: number, note: string) {
    const result = completeStation(stationId, note)
    setTodayLog(result.todayLog)
    setAppData(result.appData)
    Widget.reloadAll()
  }

  function handleUpdateNote(stationId: number, note: string) {
    const result = updateStationNote(stationId, note)
    setTodayLog(result.todayLog)
    setAppData(result.appData)
  }

  // ── AI suggestion ─────────────────────────────────────────────
  async function openAiSuggest(station: Station) {
    setShowSheet(false)
    setAiSheetStation(station)
    setAiResult("")
    setAiConvId("")
    setAiLoading(true)
    setShowAiSheet(true)

    const userPrompt = t("aiMenuPrompt", { meal: getStationName(station.id), time: station.timeStart + "–" + station.timeEnd })

    try {
      const stream = await Assistant.requestStreaming({
        systemPrompt: t("aiMenuSystem"),
        messages: [{
          role: "user",
          content: userPrompt,
        }],
        provider: "deepseek",
      })

      let result = ""
      for await (const chunk of stream) {
        if (chunk.type === "text") {
          result += chunk.content
          setAiResult(result)
        }
      }

      const convId = saveMealSuggestionToChat(
        getStationName(station.id),
        userPrompt,
        result
      )
      setAiConvId(convId)
    } catch (e) {
      setAiResult(t("aiError"))
    }
    setAiLoading(false)
  }

  function continueInAiChat() {
    setShowAiSheet(false)
    if (tabSelection) {
      tabSelection.value = 2
    }
  }

  // ── Sheet data ────────────────────────────────────────────────
  const sheetStation = sheetStationId ? STATIONS.find(s => s.id === sheetStationId) : null
  const sheetLog = sheetStationId ? todayLog.stations.find(s => s.stationId === sheetStationId) : null

  return (
    <NavigationStack>
      <List
        navigationTitle={t("homeTitle")}
        sheet={[
          // Meal detail sheet
          {
            isPresented: showSheet,
            onChanged: (v: boolean) => { setShowSheet(v); if (!v) refreshData() },
            content: sheetStation ? (
              <MealDetailSheet
                station={sheetStation}
                isDone={completedIds.has(sheetStation.id)}
                existingNote={sheetLog?.note || ""}
                onComplete={(note) => handleComplete(sheetStation.id, note)}
                onUpdateNote={(note) => handleUpdateNote(sheetStation.id, note)}
                onAiSuggest={() => openAiSuggest(sheetStation)}
                onDismiss={() => setShowSheet(false)}
              />
            ) : <Text>{""}</Text>,
          },
          // AI suggestion sheet
          {
            isPresented: showAiSheet,
            onChanged: setShowAiSheet,
            content: (
              <AiSuggestSheet
                station={aiSheetStation}
                aiResult={aiResult}
                aiLoading={aiLoading}
                aiConvId={aiConvId}
                onContinueInChat={continueInAiChat}
                onDismiss={() => setShowAiSheet(false)}
              />
            ),
          },
        ]}
      >
        {/* Summary Header */}
        <SummarySection
          completed={completed}
          streak={streak}
          encouragement={encouragement}
          todayPoints={todayLog.totalPoints}
        />

        {/* Skipped Meals Warning */}
        <SkippedSection
          skippedStations={skippedStations}
          onOpenStation={openMealSheet}
        />

        {/* Next Station */}
        {nextStation && !completedIds.has(nextStation.id) ? (
          <NextStationSection
            nextStation={nextStation}
            onOpenStation={openMealSheet}
          />
        ) : null}

        {/* All Stations */}
        <AllStationsSection
          completedIds={completedIds}
          stationLogs={todayLog.stations}
          onOpenStation={openMealSheet}
        />

        {/* All Done Celebration */}
        {completed === 5 ? (
          <AllDoneSection totalPoints={todayLog.totalPoints} />
        ) : null}
      </List>
    </NavigationStack>
  )
}
