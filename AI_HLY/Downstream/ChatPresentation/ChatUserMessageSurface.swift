//
//  ChatUserMessageSurface.swift
//  AI_HLY
//
//  Clean, content-first user message presentation inspired by native iOS design
//  with soft pale bubble styling, generous continuous corners, restrained width,
//  and mixed RTL/LTR support.
//

import SwiftUI
import UniformTypeIdentifiers

struct ChatUserMessageSurface: View {
  let text: String
  let images: [UIImage]?
  let uploadDocument: [URL]?
  let documentText: String?
  let prompts: [PromptCard]?
  let temporaryRecord: Bool
  let onSaveKnowledge: (String) -> Void
  let onDelete: () -> Void

  @State private var isTextSelectionSheetPresented = false
  @State private var selectedImage: UIImage?
  @State private var isImageViewerPresented = false
  @State private var showDocumentContent = false
  @State private var isCopied = false

  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  init(
    text: String,
    images: [UIImage]?,
    uploadDocument: [URL]?,
    documentText: String? = nil,
    prompts: [PromptCard]?,
    temporaryRecord: Bool,
    onSaveKnowledge: @escaping (String) -> Void,
    onDelete: @escaping () -> Void
  ) {
    self.text = text
    self.images = images
    self.uploadDocument = uploadDocument
    self.documentText = documentText
    self.prompts = prompts
    self.temporaryRecord = temporaryRecord
    self.onSaveKnowledge = onSaveKnowledge
    self.onDelete = onDelete
  }

  private var isRegularWidth: Bool {
    horizontalSizeClass == .regular
  }

  var body: some View {
    HStack {
      Spacer(minLength: 32)
      VStack(alignment: .trailing, spacing: 6) {
        // Attached Images
        if let images, !images.isEmpty {
          imagesRow(images)
        }

        // Attached Documents
        if let uploadDocument, !uploadDocument.isEmpty {
          documentsList(uploadDocument)
        }

        // Attached Prompts
        if let prompts, !prompts.isEmpty {
          promptsRow(prompts)
        }

        // User Text Bubble
        if !text.isEmpty {
          userTextBubble
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .trailing)
    .sheet(isPresented: $isTextSelectionSheetPresented) {
      TextSelectionView(text: text)
    }
    .sheet(isPresented: $isImageViewerPresented) {
      if let img = selectedImage {
        ImageViewer(image: img, isPresented: $isImageViewerPresented)
      }
    }
    .sheet(isPresented: $showDocumentContent) {
      FileContentViewer(
        content: (documentText ?? String(localized: "暂无内容")).trimmingCharacters(
          in: .whitespacesAndNewlines))
    }
  }

  // MARK: - Text Bubble

  private var userTextBubble: some View {
    Text(text)
      .font(.body)
      .foregroundStyle(Color.primary)
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .background(bubbleBackground)
      .clipShape(
        RoundedRectangle(
          cornerRadius: ChatHostPresentationPolicy.userBubbleCornerRadius, style: .continuous)
      )
      .overlay(
        RoundedRectangle(
          cornerRadius: ChatHostPresentationPolicy.userBubbleCornerRadius, style: .continuous
        )
        .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
      )
      .frame(
        maxWidth: ChatHostPresentationPolicy.maxUserMessageWidth(
          containerWidth: UIScreen.main.bounds.width,
          isRegularWidth: isRegularWidth
        ),
        alignment: .trailing
      )
      .contextMenu {
        Button {
          UIPasteboard.general.string = markdownToPlainText(text)
          isCopied = true
        } label: {
          Label(String(localized: "复制内容"), systemImage: "square.on.square")
        }

        Button {
          isTextSelectionSheetPresented = true
        } label: {
          Label(String(localized: "选择文本"), systemImage: "text.redaction")
        }

        Button {
          onSaveKnowledge(text)
        } label: {
          Label(String(localized: "存为知识"), systemImage: "backpack")
        }

        Button(role: .destructive) {
          onDelete()
        } label: {
          Label(String(localized: "删除消息"), systemImage: "trash")
        }
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(text)
      .accessibilityHint(String(localized: "用户消息"))
  }

  private var bubbleBackground: some View {
    Group {
      if temporaryRecord {
        Color(uiColor: .tertiarySystemFill)
      } else {
        Color(uiColor: .secondarySystemFill)
      }
    }
  }

  // MARK: - Images

  private func imagesRow(_ images: [UIImage]) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(images.indices, id: \.self) { idx in
          let img = images[idx]
          Image(uiImage: img)
            .resizable()
            .scaledToFill()
            .frame(width: 110, height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
              RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onTapGesture {
              selectedImage = img
              isImageViewerPresented = true
            }
            .contextMenu {
              Button {
                UIPasteboard.general.image = img
              } label: {
                Label(String(localized: "复制图片"), systemImage: "square.on.square")
              }
              Button {
                UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
              } label: {
                Label(String(localized: "保存图片"), systemImage: "square.and.arrow.down")
              }
            }
        }
      }
      .padding(4)
    }
    .frame(
      maxWidth: ChatHostPresentationPolicy.maxUserMessageWidth(
        containerWidth: UIScreen.main.bounds.width,
        isRegularWidth: isRegularWidth
      ), alignment: .trailing)
  }

  // MARK: - Documents

  private func documentsList(_ documents: [URL]) -> some View {
    VStack(alignment: .trailing, spacing: 6) {
      ForEach(documents, id: \.self) { url in
        HStack(spacing: 8) {
          ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(fileColor(for: url.pathExtension))
              .frame(width: 32, height: 32)
            Image(systemName: fileIcon(for: url.pathExtension))
              .font(.system(size: 16))
              .foregroundColor(.white)
          }

          VStack(alignment: .leading, spacing: 2) {
            Text(url.deletingPathExtension().lastPathComponent)
              .font(.caption.weight(.medium))
              .foregroundStyle(.primary)
              .lineLimit(1)
              .truncationMode(.tail)
            Text(url.pathExtension.uppercased())
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .onTapGesture {
          showDocumentContent = true
        }
      }
    }
    .frame(
      maxWidth: ChatHostPresentationPolicy.maxUserMessageWidth(
        containerWidth: UIScreen.main.bounds.width,
        isRegularWidth: isRegularWidth
      ), alignment: .trailing)
  }

  // MARK: - Prompts

  private func promptsRow(_ prompts: [PromptCard]) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
        ForEach(prompts, id: \.self) { item in
          HStack(spacing: 6) {
            Image("prompt")
              .renderingMode(.template)
              .resizable()
              .scaledToFit()
              .frame(width: 14, height: 14)
              .foregroundColor(.secondary)

            Text(item.name)
              .font(.caption)
              .foregroundStyle(.primary)
              .lineLimit(1)
              .truncationMode(.tail)
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(Color(uiColor: .secondarySystemFill))
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
      }
      .padding(2)
    }
    .frame(
      maxWidth: ChatHostPresentationPolicy.maxUserMessageWidth(
        containerWidth: UIScreen.main.bounds.width,
        isRegularWidth: isRegularWidth
      ), alignment: .trailing)
  }

  // MARK: - File Helpers

  private func fileColor(for fileExtension: String) -> Color {
    switch fileExtension.lowercased() {
    case "pdf":
      return Color.hlRed.opacity(0.9)
    case "doc", "docx":
      return Color.hlBluefont.opacity(0.9)
    case "ppt", "pptx":
      return Color.hlOrange.opacity(0.9)
    case "xls", "xlsx":
      return Color.hlGreen.opacity(0.9)
    case "txt", "md", "json":
      return Color.hlBrown.opacity(0.9)
    default:
      return Color.hlBluefont.opacity(0.9)
    }
  }

  private func fileIcon(for fileExtension: String) -> String {
    switch fileExtension.lowercased() {
    case "pdf":
      return "text.rectangle.page"
    case "doc", "docx":
      return "doc.text"
    case "ppt", "pptx":
      return "richtext.page"
    case "xls", "xlsx":
      return "chart.bar.horizontal.page"
    case "txt", "md", "json":
      return "text.page"
    default:
      return "doc"
    }
  }
}
