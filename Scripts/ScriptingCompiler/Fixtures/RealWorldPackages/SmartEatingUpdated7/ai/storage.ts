// ai/storage.ts - AI Chat Storage Management
// Storage is a global — do NOT import from "scripting"

import { ChatMessage, Conversation, ConversationsData } from "./types"
import { CONVERSATIONS_KEY } from "./constants"
import { generateId, autoTitle } from "./utils"

export function loadConversations(): ConversationsData {
  const data = Storage.get<ConversationsData>(CONVERSATIONS_KEY)
  if (data && data.conversations) {
    return {
      conversations: data.conversations,
      activeConversationId: data.activeConversationId ?? null,
    }
  }
  return { conversations: [], activeConversationId: null }
}

export function saveConversations(data: ConversationsData): void {
  const now = Date.now()
  const filteredConversations = data.conversations.filter(c => {
    if (c.messages.length > 0) return true
    return (now - c.createdAt) < 5 * 60 * 1000
  })

  let newActiveId = data.activeConversationId
  if (newActiveId && !filteredConversations.find(c => c.id === newActiveId)) {
    newActiveId = filteredConversations.length > 0 ? filteredConversations[0].id : null
  }

  Storage.set(CONVERSATIONS_KEY, {
    conversations: filteredConversations,
    activeConversationId: newActiveId,
  })
}

export function createNewConversation(title?: string): Conversation {
  return {
    id: generateId(),
    title: title || "שיחה חדשה",
    messages: [],
    createdAt: Date.now(),
    updatedAt: Date.now(),
  }
}

export function addMessageToConversation(
  conversationsData: ConversationsData,
  conversationId: string,
  message: ChatMessage,
  isFirstMessage?: boolean
): ConversationsData {
  const { conversations, activeConversationId } = conversationsData
  const convIndex = conversations.findIndex(c => c.id === conversationId)
  
  if (convIndex === -1) {
    // Create new conversation
    const newConv: Conversation = {
      id: conversationId,
      title: isFirstMessage ? autoTitle(message.content) : "שיחה חדשה",
      messages: [message],
      createdAt: Date.now(),
      updatedAt: Date.now(),
    }
    return {
      conversations: [newConv, ...conversations],
      activeConversationId: conversationId,
    }
  }
  
  // Update existing conversation
  const updatedConversations = [...conversations]
  const conv = updatedConversations[convIndex]
  updatedConversations[convIndex] = {
    ...conv,
    title: isFirstMessage && conv.messages.length === 0 ? autoTitle(message.content) : conv.title,
    messages: [...conv.messages, message],
    updatedAt: Date.now(),
  }
  
  return {
    conversations: updatedConversations,
    activeConversationId: conversationId,
  }
}

export function saveAiMealSuggestion(
  userPrompt: string,
  aiResponse: string,
  mealName: string
): string {
  const data = loadConversations()
  const conversationId = generateId()
  const title = `הצעת ארוחה: ${mealName}`
  
  const userMessage: ChatMessage = {
    id: generateId(),
    role: "user",
    content: userPrompt,
    timestamp: Date.now(),
  }
  
  const assistantMessage: ChatMessage = {
    id: generateId(),
    role: "assistant",
    content: aiResponse,
    timestamp: Date.now(),
  }
  
  // Add user message
  let newData = addMessageToConversation(data, conversationId, userMessage, true)
  // Add assistant message
  newData = addMessageToConversation(newData, conversationId, assistantMessage, false)
  
  // Update title
  const convIndex = newData.conversations.findIndex(c => c.id === conversationId)
  if (convIndex !== -1) {
    newData.conversations[convIndex].title = title
  }
  
  saveConversations(newData)
  return conversationId
}

export function deleteConversation(conversationsData: ConversationsData, convId: string): ConversationsData {
  const filtered = conversationsData.conversations.filter(c => c.id !== convId)
  const newActiveId = conversationsData.activeConversationId === convId
    ? (filtered.length > 0 ? filtered[0].id : null)
    : conversationsData.activeConversationId
  return { conversations: filtered, activeConversationId: newActiveId }
}

export function deleteAllConversations(): ConversationsData {
  return { conversations: [], activeConversationId: null }
}

export function switchActiveConversation(conversationsData: ConversationsData, convId: string): ConversationsData {
  return {
    ...conversationsData,
    activeConversationId: convId,
  }
}