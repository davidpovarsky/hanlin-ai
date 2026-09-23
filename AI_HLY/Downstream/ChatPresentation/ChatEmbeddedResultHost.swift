//
//  ChatEmbeddedResultHost.swift
//  AI_HLY
//
//  Generic host container for embedded tool results and Mini Apps.
//  Enforces centralized size policy, safe transcript placement, calm neutral
//  container styling, and optional expansion affordances with floating circular controls.
//

import HanlinPlatformContracts
import SwiftUI

struct ChatEmbeddedResultHost<Content: View, ExpandedContent: View>: View {
  let title: String?
  let sizingPreference: HanlinEmbeddedSizingPreference
  let expansions: [ChatResolvedExpansion]
  let contentActions: [HanlinEmbeddedContentAction]
  let containerStyle: ChatHostContainerStyle
  let onLaunchRequest: ((HanlinLaunchRequest) -> Void)?
  let onLegacyLaunchRequest: ((NativeAppLaunchRequest) -> Void)?
  let onContentAction: ((HanlinEmbeddedContentAction) -> Void)?
  @ViewBuilder let content: () -> Content
  @ViewBuilder let expandedContent: () -> ExpandedContent

  @State private var isSheetPresented = false
  @State private var isFullScreenPresented = false
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.openWindow) private var openWindow

  init(
    title: String? = nil,
    sizingPreference: HanlinEmbeddedSizingPreference = HanlinEmbeddedSizingPreference(),
    expansions: [ChatResolvedExpansion] = [],
    contentActions: [HanlinEmbeddedContentAction] = [],
    containerStyle: ChatHostContainerStyle = .borderedCard,
    onLaunchRequest: ((HanlinLaunchRequest) -> Void)? = nil,
    onLegacyLaunchRequest: ((NativeAppLaunchRequest) -> Void)? = nil,
    onContentAction: ((HanlinEmbeddedContentAction) -> Void)? = nil,
    @ViewBuilder content: @escaping () -> Content,
    @ViewBuilder expandedContent: @escaping () -> ExpandedContent
  ) {
    self.title = title
    self.sizingPreference = sizingPreference
    self.expansions = expansions
    self.contentActions = contentActions
    self.containerStyle = containerStyle
    self.onLaunchRequest = onLaunchRequest
    self.onLegacyLaunchRequest = onLegacyLaunchRequest
    self.onContentAction = onContentAction
    self.content = content
    self.expandedContent = expandedContent
  }

  // Legacy initializer supporting NativeAppLaunchRequest
  init(
    title: String? = nil,
    sizingPreference: HanlinEmbeddedSizingPreference = HanlinEmbeddedSizingPreference(),
    expansions: [ChatResolvedExpansion] = [],
    contentActions: [HanlinEmbeddedContentAction] = [],
    containerStyle: ChatHostContainerStyle = .borderedCard,
    onLaunchRequest: ((NativeAppLaunchRequest) -> Void)? = nil,
    onContentAction: ((HanlinEmbeddedContentAction) -> Void)? = nil,
    @ViewBuilder content: @escaping () -> Content,
    @ViewBuilder expandedContent: @escaping () -> ExpandedContent
  ) {
    self.init(
      title: title,
      sizingPreference: sizingPreference,
      expansions: expansions,
      contentActions: contentActions,
      containerStyle: containerStyle,
      onLaunchRequest: onLaunchRequest.map { legacy in { req in legacy(req.toLegacy()) } },
      onLegacyLaunchRequest: onLaunchRequest,
      onContentAction: onContentAction,
      content: content,
      expandedContent: expandedContent
    )
  }

  init(
    title: String? = nil,
    sizingPreference: HanlinEmbeddedSizingPreference = HanlinEmbeddedSizingPreference(),
    expansionDescriptor: ChatResolvedExpansion? = nil,
    contentActions: [HanlinEmbeddedContentAction] = [],
    containerStyle: ChatHostContainerStyle = .borderedCard,
    onLaunchRequest: ((NativeAppLaunchRequest) -> Void)? = nil,
    onContentAction: ((HanlinEmbeddedContentAction) -> Void)? = nil,
    @ViewBuilder content: @escaping () -> Content,
    @ViewBuilder expandedContent: @escaping () -> ExpandedContent
  ) {
    self.init(
      title: title,
      sizingPreference: sizingPreference,
      expansions: expansionDescriptor.map { [$0] } ?? [],
      contentActions: contentActions,
      containerStyle: containerStyle,
      onLaunchRequest: onLaunchRequest,
      onContentAction: onContentAction,
      content: content,
      expandedContent: expandedContent
    )
  }

  private var isRegularWidth: Bool {
    horizontalSizeClass == .regular
  }

  private var clampedHeight: CGFloat {
    let maxAllowed = ChatHostPresentationPolicy.maxEmbeddedResultHeight(
      isRegularWidth: isRegularWidth)
    if let requested = sizingPreference.preferredHeight, requested > 0, !requested.isNaN {
      return min(CGFloat(requested), maxAllowed)
    }
    let presetHeight = ChatHostPresentationPolicy.height(
      for: sizingPreference.preset, isRegularWidth: isRegularWidth)
    return min(presetHeight, maxAllowed)
  }

  private var clampedMaxWidth: CGFloat {
    let hostMax = ChatHostPresentationPolicy.maxEmbeddedResultWidth(isRegularWidth: isRegularWidth)
    if let requested = sizingPreference.preferredWidth, requested > 0, !requested.isNaN {
      return min(CGFloat(requested), hostMax)
    }
    return hostMax
  }

  /// All expansion modes that are valid and resolvable in the current environment.
  private var validExpansions: [ChatResolvedExpansion] {
    expansions.filter { expansion in
      switch expansion.mode {
      case .sheet, .fullScreen:
        return true
      case .window:
        return ChatHostPresentationPolicy.supportsWindowExpansion
      }
    }
  }

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      Group {
        switch containerStyle {
        case .neutral:
          neutralHostedContent
        case .borderedCard:
          borderedCardHostedContent
        }
      }

      if !validExpansions.isEmpty || !contentActions.isEmpty {
        floatingControlsView
          .padding(12)
      }
    }
    .frame(
      maxWidth: clampedMaxWidth,
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

  // MARK: - Floating Action Controls (Legacy Map/Web visual grammar)
  // Shared visual control group for both content actions and host presentation/expansion actions.

  @ViewBuilder
  private var floatingControlsView: some View {
    HStack(spacing: 6) {
      // 1. Content Actions (e.g. Open in Maps, Open in Mini App)
      ForEach(contentActions, id: \.id) { action in
        Button {
          if let onContentAction {
            onContentAction(action)
          } else if let launchReq = action.launchRequest {
            if let onLaunchRequest {
              onLaunchRequest(launchReq)
            } else if let onLegacyLaunchRequest {
              onLegacyLaunchRequest(launchReq.toLegacy())
            }
          }
        } label: {
          Image(systemName: action.systemImage ?? "arrow.up.right.square")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(width: 28, height: 28)
            .background(.ultraThinMaterial, in: Circle())
            .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
        .accessibilityIdentifier("content_action_\(action.id)")
      }

      // 2. Host Presentation / Expansion Actions
      ForEach(validExpansions, id: \.mode) { expansion in
        Button {
          handleExpansion(expansion)
        } label: {
          Image(systemName: iconName(for: expansion.mode))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(width: 28, height: 28)
            .background(.ultraThinMaterial, in: Circle())
            .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: expansion.mode))
        .accessibilityIdentifier("expansion_action_\(expansion.mode.rawValue)")
      }
    }
  }

  private func iconName(for mode: HanlinExpansionMode) -> String {
    switch mode {
    case .sheet:
      return "arrow.down.backward.and.arrow.up.forward"
    case .fullScreen:
      return "arrow.up.left.and.arrow.down.right"
    case .window:
      return "macwindow.badge.plus"
    }
  }

  private func accessibilityLabel(for mode: HanlinExpansionMode) -> String {
    switch mode {
    case .sheet:
      return String(localized: "Expand into sheet")
    case .fullScreen:
      return String(localized: "Open full screen")
    case .window:
      return String(localized: "Open in new window")
    }
  }

  // MARK: - Neutral Style

  @ViewBuilder
  private var neutralHostedContent: some View {
    content()
      .frame(maxWidth: .infinity, maxHeight: clampedHeight, alignment: .topLeading)
      .clipped()
      .frame(
        maxHeight: ChatHostPresentationPolicy.maxEmbeddedResultHeight(isRegularWidth: isRegularWidth),
        alignment: .topLeading
      )
      .clipped()
  }

  // MARK: - Bordered Card Style

  @ViewBuilder
  private var borderedCardHostedContent: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let title, !title.isEmpty {
        HStack(alignment: .center) {
          Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
          Spacer(minLength: 8)
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
    .frame(
      maxHeight: ChatHostPresentationPolicy.maxEmbeddedResultHeight(isRegularWidth: isRegularWidth),
      alignment: .topLeading
    )
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

  private func handleExpansion(_ expansion: ChatResolvedExpansion) {
    switch expansion.mode {
    case .sheet:
      isSheetPresented = true
    case .fullScreen:
      isFullScreenPresented = true
    case .window:
      if ChatHostPresentationPolicy.supportsWindowExpansion {
        if let canonical = expansion.launchRequest {
          if let onLaunchRequest {
            onLaunchRequest(canonical)
          } else if let onLegacyLaunchRequest {
            onLegacyLaunchRequest(canonical.toLegacy())
          } else {
            #if targetEnvironment(macCatalyst) || os(visionOS)
              openWindow(value: canonical)
            #elseif os(iOS)
              if UIApplication.shared.supportsMultipleScenes {
                openWindow(value: canonical)
              }
            #endif
          }
        } else if let legacy = expansion.legacyLaunchRequest {
          if let onLegacyLaunchRequest {
            onLegacyLaunchRequest(legacy)
          } else if let onLaunchRequest {
            onLaunchRequest(legacy.toCanonical())
          }
        }
      }
    }
  }
}

extension ChatEmbeddedResultHost where ExpandedContent == Content {
  init(
    title: String? = nil,
    sizingPreference: HanlinEmbeddedSizingPreference = HanlinEmbeddedSizingPreference(),
    expansions: [ChatResolvedExpansion] = [],
    contentActions: [HanlinEmbeddedContentAction] = [],
    containerStyle: ChatHostContainerStyle = .borderedCard,
    onLaunchRequest: ((HanlinLaunchRequest) -> Void)? = nil,
    onLegacyLaunchRequest: ((NativeAppLaunchRequest) -> Void)? = nil,
    onContentAction: ((HanlinEmbeddedContentAction) -> Void)? = nil,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.init(
      title: title,
      sizingPreference: sizingPreference,
      expansions: expansions,
      contentActions: contentActions,
      containerStyle: containerStyle,
      onLaunchRequest: onLaunchRequest,
      onLegacyLaunchRequest: onLegacyLaunchRequest,
      onContentAction: onContentAction,
      content: content,
      expandedContent: content
    )
  }

  init(
    title: String? = nil,
    sizingPreference: HanlinEmbeddedSizingPreference = HanlinEmbeddedSizingPreference(),
    expansions: [ChatResolvedExpansion] = [],
    contentActions: [HanlinEmbeddedContentAction] = [],
    containerStyle: ChatHostContainerStyle = .borderedCard,
    onLaunchRequest: ((NativeAppLaunchRequest) -> Void)? = nil,
    onContentAction: ((HanlinEmbeddedContentAction) -> Void)? = nil,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.init(
      title: title,
      sizingPreference: sizingPreference,
      expansions: expansions,
      contentActions: contentActions,
      containerStyle: containerStyle,
      onLaunchRequest: onLaunchRequest,
      onContentAction: onContentAction,
      content: content,
      expandedContent: content
    )
  }

  init(
    title: String? = nil,
    sizingPreference: HanlinEmbeddedSizingPreference = HanlinEmbeddedSizingPreference(),
    expansionDescriptor: ChatResolvedExpansion? = nil,
    contentActions: [HanlinEmbeddedContentAction] = [],
    containerStyle: ChatHostContainerStyle = .borderedCard,
    onLaunchRequest: ((NativeAppLaunchRequest) -> Void)? = nil,
    onContentAction: ((HanlinEmbeddedContentAction) -> Void)? = nil,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.init(
      title: title,
      sizingPreference: sizingPreference,
      expansions: expansionDescriptor.map { [$0] } ?? [],
      contentActions: contentActions,
      containerStyle: containerStyle,
      onLaunchRequest: onLaunchRequest,
      onContentAction: onContentAction,
      content: content,
      expandedContent: content
    )
  }
}
