// ai/utils.ts - AI Chat Utility Functions

import { ChatMessage } from "./types"

export function generateId(): string {
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 8)
}

export function autoTitle(msg: string): string {
  const trimmed = msg.trim()
  if (trimmed.length <= 30) return trimmed
  return trimmed.substring(0, 30) + "..."
}

export function buildApiMessages(messages: ChatMessage[]): { role: "user" | "assistant"; content: string }[] {
  return messages.map(m => ({ role: m.role, content: m.content }))
}

export function createChatMessage(
  role: "user" | "assistant", 
  content: string, 
  id?: string
): ChatMessage {
  return {
    id: id || generateId(),
    role,
    content,
    timestamp: Date.now(),
  }
}

export function findActiveConversation(conversations: any[], activeId: string | null) {
  return conversations.find(c => c.id === activeId) || null
}

export function shouldRefreshFromStorage(
  current: any, 
  storage: any,
  isLoading: boolean
): boolean {
  return !isLoading && (
    current.conversations.length !== storage.conversations.length ||
    current.activeConversationId !== storage.activeConversationId
  )
}