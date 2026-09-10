//
//  ChatAssistantActionsView.swift
//  AI_HLY
//
//  Quiet, secondary action row for assistant messages following the ChatGPT-style
//  minimal chrome pattern.
//

import SwiftUI

struct ChatAssistantActionsView: View {
  let text: String
  let isSpeaking: Bool
  let isAskingSpeech: Bool
  let isTranslating: Bool
  let isTranslated: Bool
  let mathMode: Bool
  let onCopy: () -> Void
  let onSelectText: () -> Void
  let onToggleSpeech: () -> Void
  let onTranslate: () -> Void
  let onToggleMath: () -> Void
  let onSaveKnowledge: () -> Void
  let onRetry: (() -> Void)?
  let onDelete: () -> Void

  @State private var isCopied = false

  var body: some View {
    HStack(spacing: 12) {
      // Copy
      Button {
        onCopy()
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
          isCopied = false
        }
      } label: {
        Image(systemName: isCopied ? "checkmark" : "square.on.square")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(isCopied ? Color.green : Color.secondary)
          .frame(width: 28, height: 28)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(isCopied ? String(localized: "已复制") : String(localized: "复制内容"))

      // Select Text
      Button(action: onSelectText) {
        Image(systemName: "text.redaction")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(Color.secondary)
          .frame(width: 28, height: 28)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(String(localized: "选择文本"))

      // Text to Speech
      Button(action: onToggleSpeech) {
        Group {
          if isAskingSpeech {
            ProgressView()
              .controlSize(.mini)
          } else {
            Image(systemName: isSpeaking ? "pause.circle.fill" : "speaker.wave.2")
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(isSpeaking ? Color.red : Color.secondary)
          }
        }
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(isSpeaking ? String(localized: "暂停朗读") : String(localized: "朗读内容"))

      // Translate
      Button(action: onTranslate) {
        Group {
          if isTranslating {
            ProgressView()
              .controlSize(.mini)
          } else if isTranslated {
            Image(systemName: "character.book.closed.fill")
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(Color.accentColor)
          } else {
            Image("translate")
              .renderingMode(.template)
              .resizable()
              .scaledToFit()
              .frame(width: 14, height: 14)
              .foregroundStyle(Color.secondary)
          }
        }
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(isTranslated ? String(localized: "删除译文") : String(localized: "翻译内容"))

      // Retry (if supported)
      if let onRetry {
        Button(action: onRetry) {
          Image(systemName: "arrow.clockwise")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.secondary)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "重新生成"))
      }

      // More Options Menu (Math mode, Save to Knowledge, Delete)
      Menu {
        Button(action: onToggleMath) {
          Label(
            mathMode ? String(localized: "普通文本模式") : String(localized: "LaTeX科学模式"),
            systemImage: mathMode ? "textformat" : "x.squareroot"
          )
        }

        Button(action: onSaveKnowledge) {
          Label(String(localized: "存为知识"), systemImage: "backpack")
        }

        Divider()

        Button(role: .destructive, action: onDelete) {
          Label(String(localized: "删除消息"), systemImage: "trash")
        }
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(Color.secondary)
          .frame(width: 28, height: 28)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(String(localized: "更多操作"))

      Spacer(minLength: 0)
    }
    .padding(.top, 4)
    .padding(.bottom, 6)
  }
}
