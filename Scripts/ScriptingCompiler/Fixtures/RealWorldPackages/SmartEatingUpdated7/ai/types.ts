// ai/types.ts - AI Chat Type Definitions

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

export interface QuickActionProps {
  promptBuilder: () => string
  systemPrompt: string
}

export interface HistorySheetProps {
  convData: ConversationsData
  onSelectConversation: (id: string) => void
  onNewChat: () => void
  onDeleteConversation: (id: string) => void
  onDeleteAll: () => void
  onDismiss: () => void
}