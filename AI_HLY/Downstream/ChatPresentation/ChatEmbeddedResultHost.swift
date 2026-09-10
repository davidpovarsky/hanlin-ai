//
//  ChatEmbeddedResultHost.swift
//  AI_HLY
//
//  Generic host container for embedded tool results and Mini Apps.
//  Enforces centralized size policy, safe transcript placement, calm neutral
//  container styling, and optional expansion affordances.
//

import SwiftUI

struct ChatEmbeddedResultHost<Content: View, ExpandedContent: View>: View {
  let title: String?
  let sizingPreference: ChatHostSizingPreference
  let expansionDescriptor: ChatHostExpansionDescriptor?
  let containerStyle: ChatHostContainerStyle
  let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?
  @ViewBuilder let content: () -> Content
  @ViewBuilder let expandedContent: () -> ExpandedContent

  @State private var isSheetPresented = false
  @State private var isFullScreenPresented = false
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.openWindow) private var openWindow

  init(
    title: String? = nil,
    sizingPreference: ChatHostSizingPreference = ChatHostSizingPreference(),
    expansionDescriptor: ChatHostExpansionDescriptor? = nil,
    containerStyle: ChatHostContainerStyle = .borderedCard,
    onLaunchRequest: ((NativeAppLaunchRequest) -> Void)? = nil,
    @ViewBuilder content: @escaping () -> Content,
    @ViewBuilder expandedContent: @escaping () -> ExpandedContent
  ) {
    self.title = title
    self.sizingPreference = sizingPreference
    self.expansionDescriptor = expansionDescriptor
    self.containerStyle = containerStyle
    self.onLaunchRequest = onLaunchRequest
    self.content = content
    self.expandedContent = expandedContent
  }

  private var isRegularWidth: Bool {
    horizontalSizeClass == .regular
  }

  private var clampedHeight: CGFloat {
    let maxAllowed = ChatHostPresentationPolicy.maxEmbeddedResultHeight(
      isRegularWidth: isRegularWidth)
    if let requested = sizingPreference.requestedHeight {
      return min(requested, maxAllowed)
    }
    let presetHeight = ChatHostPresentationPolicy.height(
      for: sizingPreference.preset, isRegularWidth: isRegularWidth)
    return min(presetHeight, maxAllowed)
  }

  var body: some View {
    Group {
      switch containerStyle {
      case .neutral:
        neutralHostedContent
      case .borderedCard:
        borderedCardHostedContent
      }
    }
    .frame(
      maxWidth: ChatHostPresentationPolicy.maxEmbeddedResultWidth(isRegularWidth: isRegularWidth),
      alignment: .leading
    )
    .sheet(isPresented: $isSheetPresented) {
      NavigationStack {
        ScrollView {
          expandedContent()
            .padding()
        }
        .navigationTitle(title ?? String(localized: "Result"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button(String(localized: "Done")) {
              isSheetPresented = false
            }
          }
        }
      }
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
    }
    .fullScreenCover(isPresented: $isFullScreenPresented) {
      NavigationStack {
        ScrollView {
          expandedContent()
            .padding()
        }
        .navigationTitle(title ?? String(localized: "Result"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button(String(localized: "Done")) {
              isFullScreenPresented = false
            }
          }
        }
      }
    }
  }

  // MARK: - Neutral Style (for results that already own card chrome like ModernCards)

  @ViewBuilder
  private var neutralHostedContent: some View {
    VStack(alignment: .leading, spacing: 4) {
      if let expansion = expansionDescriptor,
        ChatHostPresentationPolicy.isExpansionModeAvailable(expansion.mode)
      {
        HStack {
          Spacer()
          expansionButton(expansion)
        }
        .padding(.horizontal, 4)
      }

      content()
        .frame(maxWidth: .infinity, maxHeight: clampedHeight, alignment: .topLeading)
        .clipped()
    }
    .frame(
      maxHeight: ChatHostPresentationPolicy.maxEmbeddedResultHeight(isRegularWidth: isRegularWidth),
      alignment: .topLeading
    )
    .clipped()
  }

  // MARK: - Bordered Card Style (for raw unstyled content)

  @ViewBuilder
  private var borderedCardHostedContent: some View {
    VStack(alignment: .leading, spacing: 6) {
      if title != nil
        || (expansionDescriptor != nil
          && ChatHostPresentationPolicy.isExpansionModeAvailable(expansionDescriptor!.mode))
      {
        HStack(alignment: .center) {
          if let title, !title.isEmpty {
            Text(title)
              .font(.caption.weight(.medium))
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }

          Spacer(minLength: 8)

          if let expansion = expansionDescriptor,
            ChatHostPresentationPolicy.isExpansionModeAvailable(expansion.mode)
          {
            expansionButton(expansion)
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
      }

      ScrollView(.vertical, showsIndicators: false) {
        content()
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .scrollBounceBehavior(.basedOnSize)
      .frame(maxHeight: clampedHeight)
      .padding(.horizontal, 10)
      .padding(.bottom, 10)
    }
    .background(
      RoundedRectangle(
        cornerRadius: ChatHostPresentationPolicy.resultContainerCornerRadius, style: .continuous
      )
      .fill(Color(uiColor: .secondarySystemGroupedBackground))
    )
    .overlay(
      RoundedRectangle(
        cornerRadius: ChatHostPresentationPolicy.resultContainerCornerRadius, style: .continuous
      )
      .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
    )
  }

  private func expansionButton(_ expansion: ChatHostExpansionDescriptor) -> some View {
    Button {
      handleExpansion(expansion)
    } label: {
      Image(systemName: "arrow.down.backward.and.arrow.up.forward")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(width: 26, height: 26)
        .background(Color(uiColor: .tertiarySystemFill))
        .clipShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(String(localized: "Expand result"))
  }

  private func handleExpansion(_ expansion: ChatHostExpansionDescriptor) {
    switch expansion.mode {
    case .sheet:
      isSheetPresented = true
    case .fullScreen:
      isFullScreenPresented = true
    case .window:
      if ChatHostPresentationPolicy.supportsWindowExpansion,
        let launchRequest = expansion.launchRequest
      {
        if let onLaunchRequest {
          onLaunchRequest(launchRequest)
        } else {
          #if targetEnvironment(macCatalyst) || os(visionOS)
            openWindow(value: launchRequest)
          #elseif os(iOS)
            if UIApplication.shared.supportsMultipleScenes {
              openWindow(value: launchRequest)
            }
          #endif
        }
      }
    }
  }
}

extension ChatEmbeddedResultHost where ExpandedContent == Content {
  init(
    title: String? = nil,
    sizingPreference: ChatHostSizingPreference = ChatHostSizingPreference(),
    expansionDescriptor: ChatHostExpansionDescriptor? = nil,
    containerStyle: ChatHostContainerStyle = .borderedCard,
    onLaunchRequest: ((NativeAppLaunchRequest) -> Void)? = nil,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.init(
      title: title,
      sizingPreference: sizingPreference,
      expansionDescriptor: expansionDescriptor,
      containerStyle: containerStyle,
      onLaunchRequest: onLaunchRequest,
      content: content,
      expandedContent: content
    )
  }
}
