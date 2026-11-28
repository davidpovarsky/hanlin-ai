// screens/home/chatHelpers.ts — Chat storage helpers (shared with AIChatScreen)
// Storage is a global — do NOT import it from "scripting"
import { t, getStationName } from "../../model/i18n"

declare const Storage: {
  get<T>(key: string): T | null
  set<T>(key: string, value: T): void
}

const CONVERSATIONS_KEY = "ai_chat_conversations"

export interface ChatMessage {
  id: string
  role: "user" | "assistant"
  content: string
  timestamp: number
}

export interface Conversation {
  id: string
  title: string
  messages: ChatMessage[]
  createdAt: number
  updatedAt: number
}

export interface ConversationsData {
  conversations: Conversation[]
  activeConversationId: string | null
}

export function generateChatId(): string {
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 8)
}

export function saveMealSuggestionToChat(
  stationName: string,
  userPrompt: string,
  aiResponse: string
): string {
  const data = Storage.get<ConversationsData>(CONVERSATIONS_KEY)
  const convData: ConversationsData = data && data.conversations
    ? { conversations: data.conversations, activeConversationId: data.activeConversationId ?? null }
    : { conversations: [], activeConversationId: null }

  const convId = generateChatId()
  const now = Date.now()
  const title = t("aiSuggestMeal") + " — " + stationName

  const newConv: Conversation = {
    id: convId,
    title: title.length > 30 ? title.substring(0, 30) + "..." : title,
    messages: [
      { id: generateChatId(), role: "user", content: userPrompt, timestamp: now - 1000 },
      { id: generateChatId(), role: "assistant", content: aiResponse, timestamp: now },
    ],
    createdAt: now,
    updatedAt: now,
  }

  convData.conversations = [newConv, ...convData.conversations]
  convData.activeConversationId = convId

  Storage.set(CONVERSATIONS_KEY, convData)
  return convId
}
