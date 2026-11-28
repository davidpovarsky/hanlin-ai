// ai/apiService.ts - AI API Service (Updated — uses custom config + health data)
// Assistant is a global — do NOT import from "scripting"

import { ChatMessage } from "./types"
import { AI_CONFIG } from "./constants"
import { buildApiMessages } from "./utils"
import { loadTodayLog, loadAppData, getWeekHistory, STATIONS } from "../model/index"
import { loadCustomConfig, getActiveStations } from "../model/customConfig"
import { buildHealthContextString, buildShortHealthSummary } from "../health/healthContext"
import { t } from "../model/i18n"

declare const Assistant: any

export async function buildNutritionContext(): Promise<string> {
  const todayLog = loadTodayLog()
  const appData = loadAppData()
  const weekHistory = getWeekHistory(appData)
  const config = loadCustomConfig()
  const activeStations = getActiveStations()

  const lines = [
    config.aiConfig.systemPrompt || t("aiContext"),
    t("todayCompleted") + todayLog.stations.length + "/" + activeStations.length,
    t("todayPoints") + todayLog.totalPoints,
    t("streakLabel") + appData.streak + " " + t("days"),
    t("weekHistory") + weekHistory.map(d => d.day + "=" + d.count + " " + t("stations")).join(", "),
    "",
    t("todayStations") +
      todayLog.stations.map(s => {
        const st = activeStations.find(x => x.id === s.stationId)
        return st ? st.name + (s.note ? " (" + s.note + ")" : "") : ""
      }).join(", "),
    "",
    "ארוחות מוגדרות: " + activeStations.map(s => s.name + " (" + s.timeStart + "–" + s.timeEnd + ")").join(", "),
  ]

  // Add health context if enabled
  if (config.aiConfig.useHealthData && config.healthConfig.enabled) {
    try {
      const healthCtx = await buildHealthContextString()
      if (healthCtx) {
        lines.push(healthCtx)
      }
    } catch (e) {
      console.error("Error building health context:", e)
    }
  }

  lines.push("")
  lines.push(t("aiInstructions"))

  return lines.join("\n")
}

export async function buildWeekAnalysisPrompt(): Promise<string> {
  const appData = loadAppData()
  const weekHistory = getWeekHistory(appData)
  const todayLog = loadTodayLog()
  const config = loadCustomConfig()

  const lines = [
    config.aiConfig.analysisPrompt || t("analyzePrompt"),
    t("historyLabel") + weekHistory.map(d => d.day + ": " + d.count + "/5 " + t("stations") + ", " + d.points + " " + t("pointsShort")).join(" | "),
    t("currentStreakLabel") + appData.streak,
    t("todayLabel") + todayLog.stations.length + "/5 " + t("stations"),
  ]

  // Add short health summary
  if (config.aiConfig.useHealthData && config.healthConfig.enabled) {
    try {
      const healthSummary = await buildShortHealthSummary()
      if (healthSummary) {
        lines.push(healthSummary)
      }
    } catch {}
  }

  return lines.join("\n")
}

export function buildEncouragementPrompt(): string {
  const todayLog = loadTodayLog()
  const appData = loadAppData()

  return [
    t("encouragementPrompt"),
    t("todayCompletedShort") + todayLog.stations.length + "/5 " + t("stations"),
    t("streakLabelShort") + appData.streak + " " + t("days"),
    t("todayPointsShort") + todayLog.totalPoints,
  ].join("\n")
}

export async function streamAiResponse(
  messages: ChatMessage[],
  systemPrompt: string,
  onChunk?: (content: string) => void
): Promise<string> {
  const config = loadCustomConfig()

  try {
    const stream = await Assistant.requestStreaming({
      systemPrompt: systemPrompt,
      messages: buildApiMessages(messages),
      provider: config.aiConfig.provider || AI_CONFIG.provider,
    })

    let result = ""
    try {
      for await (const chunk of stream) {
        if (chunk && chunk.type === "text" && typeof chunk.content === "string") {
          result += chunk.content
          if (onChunk) {
            onChunk(result)
          }
        }
      }
    } catch (streamError) {
      console.error("Stream processing error:", streamError)
      if (!result) {
        result = t("aiError")
      }
    }

    return result
  } catch (error) {
    console.error("AI API error:", error)
    throw new Error(t("aiError"))
  }
}

export async function requestAiResponse(
  userMessage: string,
  conversationHistory: ChatMessage[],
  systemPrompt?: string
): Promise<string> {
  const messages = [...conversationHistory, {
    role: "user" as const,
    content: userMessage,
  }]

  const ctx = systemPrompt || await buildNutritionContext()

  return streamAiResponse(
    messages.map(m => ({
      id: "",
      role: m.role,
      content: m.content,
      timestamp: Date.now()
    })),
    ctx
  )
}

export interface QuickActionConfig {
  promptBuilder: () => string | Promise<string>
  systemPrompt: string
  title?: string
}

export const QUICK_ACTIONS = {
  analyzeWeek: (): QuickActionConfig => {
    const config = loadCustomConfig()
    return {
      promptBuilder: buildWeekAnalysisPrompt,
      systemPrompt: config.aiConfig.systemPrompt || t("aiSystemPrompt"),
      title: t("analyzeWeek"),
    }
  },

  getEncouragement: (): QuickActionConfig => {
    const config = loadCustomConfig()
    return {
      promptBuilder: buildEncouragementPrompt,
      systemPrompt: config.aiConfig.encouragementPrompt || t("encouragementSystemPrompt"),
      title: t("giveEncouragement"),
    }
  },
}
