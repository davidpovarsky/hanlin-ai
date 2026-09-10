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
  let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?
  @ViewBuilder let content: () -> Content
  @ViewBuilder let expandedContent: () -> ExpandedContent

  @State private var isSheetPresented = false
  @State private var isFullScreenPresented = false
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.openWindow) private var openWindow

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
    VStack(alignment: .leading, spacing: 6) {
      // Optional Host Header (if title or expansion affordance present)
      if title != nil || expansionDescriptor != nil {
        HStack(alignment: .center) {
          if let title, !title.isEmpty {
            Text(title)
              .font(.caption.weight(.medium))
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }

          Spacer(minLength: 8)

          if let expansion = expansionDescriptor {
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
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
      }

      // Hosted Content Slot
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
      maxWidth: ChatHostPresentationPolicy.maxEmbeddedResultWidth(
        containerWidth: UIScreen.main.bounds.width,
        isRegularWidth: isRegularWidth
      ),
      alignment: .leading
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

  private func handleExpansion(_ expansion: ChatHostExpansionDescriptor) {
    switch expansion.mode {
    case .sheet:
      isSheetPresented = true
    case .fullScreen:
      isFullScreenPresented = true
    case .window:
      // If native window expansion is supported, trigger window; fallback to sheet
      #if targetEnvironment(macCatalyst) || os(visionOS)
        // Window trigger supported on window environments
      #else
        isSheetPresented = true
      #endif
    }
  }
}

extension ChatEmbeddedResultHost where ExpandedContent == Content {
  init(
    title: String? = nil,
    sizingPreference: ChatHostSizingPreference = ChatHostSizingPreference(),
    expansionDescriptor: ChatHostExpansionDescriptor? = nil,
    onLaunchRequest: ((NativeAppLaunchRequest) -> Void)? = nil,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.init(
      title: title,
      sizingPreference: sizingPreference,
      expansionDescriptor: expansionDescriptor,
      onLaunchRequest: onLaunchRequest,
      content: content,
      expandedContent: content
    )
  }
}
