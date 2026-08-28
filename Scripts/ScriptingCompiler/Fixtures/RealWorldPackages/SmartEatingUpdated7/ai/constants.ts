// ai/constants.ts - AI Chat Constants

export const CONVERSATIONS_KEY = "ai_chat_conversations"

export const AI_CONFIG = {
  provider: "deepseek" as const,
  maxMessageLength: 1000,
  streamingEnabled: true,
  autoSaveInterval: 5 * 60 * 1000, // 5 minutes
}

export const MESSAGE_LIMITS = {
  titleLength: 30,
  conversationHistory: 100,
  streamingChunkSize: 1024,
}

export const STREAMING_MESSAGES = {
  loading: "...",
  thinking: "חושב...",
  error: "שגיאה בקבלת תגובה",
}