// ai/hooks/useConversations.ts - Custom hook for managing conversations

import { useState, useCallback } from "scripting"
import { ConversationsData, ChatMessage } from "../types"
import { 
  loadConversations, 
  saveConversations, 
  createNewConversation,
  addMessageToConversation,
  deleteConversation as deleteConversationFromStorage,
  deleteAllConversations,
  switchActiveConversation 
} from "../storage"
import { createChatMessage, autoTitle, shouldRefreshFromStorage } from "../utils"

export function useConversations() {
  const [convData, setConvData] = useState<ConversationsData>(() => loadConversations())

  const updateAndSave = useCallback((updater: (data: ConversationsData) => ConversationsData) => {
    setConvData(prev => {
      const next = updater(prev)
      saveConversations(next)
      return next
    })
  }, [])

  const refreshFromStorage = useCallback((loading: boolean = false) => {
    const currentStorageData = loadConversations()
    if (shouldRefreshFromStorage(convData, currentStorageData, loading)) {
      setConvData(currentStorageData)
    }
  }, [convData])

  const startNewChat = useCallback(() => {
    const currentConv = convData.conversations.find(c => c.id === convData.activeConversationId)
    if (currentConv && currentConv.messages.length === 0) {
      return
    }

    const conv = createNewConversation()
    updateAndSave(data => ({
      conversations: [conv, ...data.conversations],
      activeConversationId: conv.id,
    }))
  }, [convData, updateAndSave])

  const switchToConversation = useCallback((convId: string) => {
    updateAndSave(data => switchActiveConversation(data, convId))
  }, [updateAndSave])

  const deleteConversation = useCallback((convId: string) => {
    updateAndSave(data => deleteConversationFromStorage(data, convId))
  }, [updateAndSave])

  const deleteAll = useCallback(() => {
    updateAndSave(() => deleteAllConversations())
  }, [updateAndSave])

  const addMessage = useCallback((
    message: ChatMessage, 
    conversationId?: string, 
    isFirst = false
  ) => {
    const targetId = conversationId || convData.activeConversationId
    if (!targetId) return

    updateAndSave(data => addMessageToConversation(data, targetId, message, isFirst))
  }, [convData.activeConversationId, updateAndSave])

  const createUserMessage = useCallback((content: string): ChatMessage => {
    return createChatMessage("user", content)
  }, [])

  const createAssistantMessage = useCallback((content: string): ChatMessage => {
    return createChatMessage("assistant", content)
  }, [])

  const ensureActiveConversation = useCallback((userMessage: string): string => {
      let activeId = convData.activeConversationId
      let activeConv = convData.conversations.find(c => c.id === activeId)

      if (!activeConv) {
        const conv = createNewConversation(autoTitle(userMessage))
        activeId = conv.id
        updateAndSave(data => ({
          conversations: [conv, ...data.conversations],
          activeConversationId: conv.id,
        }))
      }

      return activeId!
    }, [convData, updateAndSave])

  return {
    // State
    convData,
    activeConversation: convData.conversations.find(c => c.id === convData.activeConversationId) || null,
    
    // Actions
    startNewChat,
    switchToConversation,
    deleteConversation,
    deleteAll,
    addMessage,
    refreshFromStorage,
    ensureActiveConversation,
    
    // Helpers
    createUserMessage,
    createAssistantMessage,
    updateAndSave,
  }
}