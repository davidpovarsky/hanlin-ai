// ai/index.ts - AI Module Main Exports

// Types
export * from "./types"

// Storage
export {
  loadConversations,
  saveConversations,
  createNewConversation,
  addMessageToConversation,
  saveAiMealSuggestion,
  deleteConversation,
  deleteAllConversations,
  switchActiveConversation,
} from "./storage"

// Utilities
export {
  generateId,
  autoTitle,
  buildApiMessages,
  createChatMessage,
  findActiveConversation,
  shouldRefreshFromStorage,
} from "./utils"

// Formatting
export {
  formatTime,
  formatDate,
  formatMessageCount,
  formatConversationAge,
  truncateText,
  formatStreamingMessage,
} from "./formatting"

// API Service
export {
  buildNutritionContext,
  buildWeekAnalysisPrompt,
  buildEncouragementPrompt,
  streamAiResponse,
  requestAiResponse,
  QUICK_ACTIONS,
} from "./apiService"

// Hooks
export { useConversations } from "./hooks/useConversations"

// Components
export { AIChatScreen } from "./components/AIChatScreen"
export { HistorySheet } from "./components/HistorySheet"

// Constants
export * from "./constants"