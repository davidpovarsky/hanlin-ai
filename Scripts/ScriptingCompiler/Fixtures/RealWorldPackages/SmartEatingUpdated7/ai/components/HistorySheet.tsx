// ai/components/HistorySheet.tsx - History Sheet Component

import {
  NavigationStack, List, Section, Text, Button, useState,
  Image, HStack, VStack, Spacer, Toolbar, ToolbarItem,
} from "scripting"
import { HistorySheetProps } from "../types"
import { formatDate } from "../formatting"
import { t } from "../../model/i18n"

export function HistorySheet(props: HistorySheetProps) {
  const { 
    convData, 
    onSelectConversation, 
    onNewChat, 
    onDeleteConversation, 
    onDeleteAll, 
    onDismiss 
  } = props
  
  const [showDeleteAllConfirm, setShowDeleteAllConfirm] = useState(false)

  return (
    <NavigationStack>
      <List
        navigationTitle={t("chatHistoryTitle")}
        navigationBarTitleDisplayMode="inline"
        toolbar={
          <Toolbar>
            <ToolbarItem placement="topBarTrailing">
              <Button title={t("chatBackToChat")} action={onDismiss} />
            </ToolbarItem>
          </Toolbar>
        }
      >
        {/* Actions Section */}
        <Section header={
          <HStack spacing={6}>
            <Image systemName="bolt.fill" font={13} foregroundStyle="systemOrange" />
            <Text>{t("chatActions")}</Text>
          </HStack>
        }>
          <Button action={() => { onNewChat(); onDismiss() }}>
            <HStack spacing={8}>
              <Image systemName="plus.message.fill" font={18} foregroundStyle="systemGreen" />
              <Text font={15} foregroundStyle="label">{t("chatNewChat")}</Text>
              <Spacer />
              <Image systemName="chevron.left" font={12} foregroundStyle="tertiaryLabel" />
            </HStack>
          </Button>
          
          {convData.conversations.length > 0 && (
            <Button
              action={() => setShowDeleteAllConfirm(true)}
              confirmationDialog={{
                isPresented: showDeleteAllConfirm,
                onChanged: setShowDeleteAllConfirm,
                title: t("chatDeleteAllConfirm"),
                actions: (
                  <Button
                    title={t("chatDeleteAll")}
                    role="destructive"
                    action={() => { 
                      onDeleteAll()
                      setShowDeleteAllConfirm(false)
                    }}
                  />
                ),
              }}
            >
              <HStack spacing={8}>
                <Image systemName="trash.fill" font={18} foregroundStyle="systemRed" />
                <Text font={15} foregroundStyle="systemRed">{t("chatDeleteAll")}</Text>
              </HStack>
            </Button>
          )}
        </Section>

        {/* Conversations List */}
        {convData.conversations.length > 0 ? (
          <Section header={
            <HStack spacing={6}>
              <Image systemName="clock.arrow.circlepath" font={13} foregroundStyle="systemBlue" />
              <Text>{t("chatPreviousChats")}</Text>
            </HStack>
          }>
            {convData.conversations.map(conv => (
              <HStack
                key={conv.id}
                spacing={10}
                padding={{ vertical: 6 }}
                contentShape="rect"
                onTapGesture={() => { 
                  onSelectConversation(conv.id)
                  onDismiss() 
                }}
                trailingSwipeActions={{
                  allowsFullSwipe: true,
                  actions: [
                    <Button
                      role="destructive"
                      action={() => onDeleteConversation(conv.id)}
                    >
                      <Image systemName="trash" />
                    </Button>,
                  ],
                }}
              >
                <Image
                  systemName={
                    conv.id === convData.activeConversationId 
                      ? "bubble.left.and.bubble.right.fill" 
                      : "bubble.left.fill"
                  }
                  font={20}
                  foregroundStyle={
                    conv.id === convData.activeConversationId 
                      ? "systemBlue" 
                      : "tertiaryLabel"
                  }
                />
                <VStack alignment="leading" spacing={3}>
                  <Text 
                    font={15} 
                    fontWeight={
                      conv.id === convData.activeConversationId 
                        ? "semibold" 
                        : "regular"
                    }
                  >
                    {conv.title}
                  </Text>
                  <HStack spacing={8}>
                    <Text font={12} foregroundStyle="tertiaryLabel">
                      {formatDate(conv.updatedAt)}
                    </Text>
                    <Text font={12} foregroundStyle="tertiaryLabel">
                      {conv.messages.length + " " + t("chatMessages")}
                    </Text>
                  </HStack>
                </VStack>
                <Spacer />
                <Image systemName="chevron.left" font={12} foregroundStyle="tertiaryLabel" />
              </HStack>
            ))}
          </Section>
        ) : (
          <Section>
            <VStack spacing={12} padding={{ vertical: 30 }}>
              <Image 
                systemName="bubble.left.and.text.bubble.right" 
                font={40} 
                foregroundStyle="tertiaryLabel" 
              />
              <Text 
                font={15} 
                foregroundStyle="secondaryLabel" 
                multilineTextAlignment="center"
              >
                {t("chatNoHistory")}
              </Text>
            </VStack>
          </Section>
        )}
      </List>
    </NavigationStack>
  )
}