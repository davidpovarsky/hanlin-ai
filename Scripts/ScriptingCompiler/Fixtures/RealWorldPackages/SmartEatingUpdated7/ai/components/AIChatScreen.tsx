// ai/components/AIChatScreen.tsx - Main AI Chat Component (Updated — async health-aware)

import {
  NavigationStack, List, Section, Text, TextField, Button,
  useState, Image, HStack, VStack, Spacer, RoundedRectangle,
  Toolbar, ToolbarItem,
} from "scripting"

import { ChatMessage } from "../types"
import { useConversations } from "../hooks/useConversations"
import {
  streamAiResponse,
  buildNutritionContext,
  QUICK_ACTIONS
} from "../apiService"
import { formatTime, formatDate } from "../formatting"
import { HistorySheet } from "./HistorySheet"
import { autoTitle } from "../utils"
import { loadCustomConfig } from "../../model/customConfig"

import { getIcon } from "../../model/index"
import { t } from "../../model/i18n"

export function AIChatScreen() {
  const {
    convData,
    activeConversation,
    startNewChat,
    switchToConversation,
    deleteConversation,
    deleteAll,
    addMessage,
    refreshFromStorage,
    ensureActiveConversation,
    createUserMessage,
    createAssistantMessage,
  } = useConversations()

  const [input, setInput] = useState("")
  const [loading, setLoading] = useState(false)
  const [streamText, setStreamText] = useState("")
  const [showHistory, setShowHistory] = useState(false)

  refreshFromStorage(loading)

  const messages = activeConversation?.messages || []
  const allDisplayMessages: ChatMessage[] = streamText
    ? [...messages, {
        id: "streaming",
        role: "assistant" as const,
        content: streamText,
        timestamp: Date.now()
      }]
    : messages

  // ── Send Message Handler ───────────────────────────────────
  async function sendMessage() {
    const text = input.trim()
    if (!text || loading) return

    setLoading(true)
    setInput("")
    setStreamText("")

    const conversationId = ensureActiveConversation(text)
    const userMessage = createUserMessage(text)
    addMessage(userMessage, conversationId, activeConversation?.messages.length === 0)

    try {
      // buildNutritionContext is now async (fetches health data)
      const ctx = await buildNutritionContext()
      const result = await streamAiResponse(
        [...(activeConversation?.messages || []), userMessage],
        ctx,
        (content) => setStreamText(content)
      )

      const assistantMessage = createAssistantMessage(result)
      addMessage(assistantMessage, conversationId)
      setStreamText("")
    } catch (error) {
      const errorMessage = createAssistantMessage(t("aiError"))
      addMessage(errorMessage, conversationId)
      setStreamText("")
    }

    setLoading(false)
  }

  // ── Quick Actions ──────────────────────────────────────────
  async function executeQuickAction(actionKey: keyof typeof QUICK_ACTIONS) {
    setLoading(true)
    setStreamText("")

    const actionConfig = QUICK_ACTIONS[actionKey]()
    // promptBuilder may now be async
    const prompt = await actionConfig.promptBuilder()
    const title = actionConfig.title || autoTitle(prompt)

    const userMessage = createUserMessage(prompt)
    const conversationId = ensureActiveConversation(prompt)
    addMessage(userMessage, conversationId, true)

    try {
      const result = await streamAiResponse(
        [userMessage],
        actionConfig.systemPrompt,
        (content) => setStreamText(content)
      )

      const assistantMessage = createAssistantMessage(result)
      addMessage(assistantMessage, conversationId)
      setStreamText("")
    } catch (error) {
      const errorMessage = createAssistantMessage(t("aiError"))
      addMessage(errorMessage, conversationId)
      setStreamText("")
    }

    setLoading(false)
  }

  // ── UI Handlers ────────────────────────────────────────────
  function openHistory() {
    refreshFromStorage()
    setShowHistory(true)
  }

  // ── Render ─────────────────────────────────────────────────
  return (
    <NavigationStack>
      <List
        navigationTitle={t("aiTitle")}
        navigationBarTitleDisplayMode="inline"
        toolbar={
          <Toolbar>
            <ToolbarItem placement="topBarLeading">
              <Button
                action={openHistory}
                sheet={{
                  isPresented: showHistory,
                  onChanged: setShowHistory,
                  content: (
                    <HistorySheet
                      convData={convData}
                      onSelectConversation={switchToConversation}
                      onNewChat={startNewChat}
                      onDeleteConversation={deleteConversation}
                      onDeleteAll={deleteAll}
                      onDismiss={() => setShowHistory(false)}
                    />
                  ),
                }}
              >
                <HStack spacing={4}>
                  <Image systemName="clock.arrow.circlepath" font={16} foregroundStyle="systemOrange" />
                  {convData.conversations.length > 0 && (
                    <Text font={13} foregroundStyle="systemOrange">
                      {String(convData.conversations.length)}
                    </Text>
                  )}
                </HStack>
              </Button>
            </ToolbarItem>
            <ToolbarItem placement="topBarTrailing">
              <Button action={startNewChat}>
                <Image systemName="plus.bubble.fill" font={16} foregroundStyle="systemGreen" />
              </Button>
            </ToolbarItem>
          </Toolbar>
        }
      >
        {/* Active Conversation Indicator */}
        {activeConversation && messages.length > 0 && (
          <Section>
            <HStack spacing={6}>
              <Image systemName="bubble.left.and.bubble.right.fill" font={13} foregroundStyle="systemBlue" />
              <Text font={13} fontWeight="medium" foregroundStyle="secondaryLabel">
                {activeConversation.title}
              </Text>
              <Spacer />
              <Text font={11} foregroundStyle="tertiaryLabel">
                {formatDate(activeConversation.createdAt)}
              </Text>
            </HStack>
          </Section>
        )}

        {/* Welcome / Quick Actions */}
        {allDisplayMessages.length === 0 && (
          <>
            <Section>
              <VStack spacing={16} padding={{ vertical: 20 }}>
                <VStack spacing={8}>
                  <Image systemName="brain.head.profile" font={44} foregroundStyle="systemGreen" />
                  <Text font={20} fontWeight="bold">{t("aiTitle")}</Text>
                  <Text font={14} foregroundStyle="secondaryLabel" multilineTextAlignment="center">
                    {t("aiInstructions")}
                  </Text>
                </VStack>
              </VStack>
            </Section>

            <Section header={
              <HStack spacing={6}>
                <Image systemName={getIcon("suggestions")} font={13} foregroundStyle="systemPurple" />
                <Text>{t("quickActions")}</Text>
              </HStack>
            }>
              <Button action={() => executeQuickAction("analyzeWeek")}>
                <HStack spacing={10} padding={{ vertical: 4 }}>
                  <Image systemName="chart.line.uptrend.xyaxis" font={20} foregroundStyle="systemBlue" />
                  <VStack alignment="leading" spacing={2}>
                    <Text font={15} fontWeight="medium" foregroundStyle="label">
                      {t("analyzeWeek")}
                    </Text>
                  </VStack>
                  <Spacer />
                  <Image systemName="chevron.left" font={12} foregroundStyle="tertiaryLabel" />
                </HStack>
              </Button>

              <Button action={() => executeQuickAction("getEncouragement")}>
                <HStack spacing={10} padding={{ vertical: 4 }}>
                  <Image systemName="hand.thumbsup.fill" font={20} foregroundStyle="systemOrange" />
                  <VStack alignment="leading" spacing={2}>
                    <Text font={15} fontWeight="medium" foregroundStyle="label">
                      {t("giveEncouragement")}
                    </Text>
                  </VStack>
                  <Spacer />
                  <Image systemName="chevron.left" font={12} foregroundStyle="tertiaryLabel" />
                </HStack>
              </Button>
            </Section>
          </>
        )}

        {/* Chat Messages */}
        {allDisplayMessages.length > 0 && (
          <Section>
            {allDisplayMessages.map((msg, i) => {
              const isUser = msg.role === "user"
              const isStreaming = msg.id === "streaming"
              return (
                <VStack key={msg.id || String(i)} alignment={isUser ? "trailing" : "leading"} spacing={4} padding={{ vertical: 3 }}>
                  <HStack spacing={4}>
                    {isUser && <Spacer />}
                    <Image
                      systemName={isUser ? "person.circle.fill" : "brain.head.profile"}
                      font={11}
                      foregroundStyle={isUser ? "systemBlue" : "systemGreen"}
                    />
                    <Text font={11} fontWeight="medium" foregroundStyle="tertiaryLabel">
                      {isUser ? t("chatYou") : t("chatAI")}
                    </Text>
                    {!isStreaming && (
                      <Text font={10} foregroundStyle="tertiaryLabel">
                        {formatTime(msg.timestamp)}
                      </Text>
                    )}
                    {!isUser && <Spacer />}
                  </HStack>
                  <Text
                    font={14}
                    foregroundStyle={isStreaming ? "secondaryLabel" : "label"}
                    lineLimit={200}
                    padding={{ horizontal: 12, vertical: 8 }}
                    background={
                      <RoundedRectangle
                        cornerRadius={14}
                        fill={isUser
                          ? { light: "rgba(0,122,255,0.12)", dark: "rgba(10,132,255,0.22)" }
                          : { light: "rgba(142,142,147,0.12)", dark: "rgba(99,99,102,0.22)" }
                        }
                      />
                    }
                  >
                    {msg.content + (isStreaming ? " ..." : "")}
                  </Text>
                </VStack>
              )
            })}
          </Section>
        )}

        {/* Loading Indicator */}
        {loading && !streamText && (
          <Section>
            <HStack spacing={8} padding={{ vertical: 8 }}>
              <Spacer />
              <Image systemName="ellipsis.circle" font={16} foregroundStyle="systemGreen" />
              <Text font={14} foregroundStyle="secondaryLabel">{t("thinking")}</Text>
              <Spacer />
            </HStack>
          </Section>
        )}

        {/* Input Section */}
        <Section>
          <TextField
            title={t("exampleQuestion")}
            value={input}
            onChanged={setInput}
          />
          <Button
            action={sendMessage}
            disabled={loading || !input.trim()}
          >
            <HStack spacing={8}>
              <Spacer />
              <Image
                systemName={loading ? "ellipsis.circle" : "paperplane.fill"}
                font={17}
                foregroundStyle={loading || !input.trim() ? "tertiaryLabel" : "systemBlue"}
              />
              <Text
                font={15}
                fontWeight="semibold"
                foregroundStyle={loading || !input.trim() ? "tertiaryLabel" : "systemBlue"}
              >
                {loading ? t("thinking") : t("send")}
              </Text>
              <Spacer />
            </HStack>
          </Button>
        </Section>
      </List>
    </NavigationStack>
  )
}
