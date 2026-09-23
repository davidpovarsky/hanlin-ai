//
//  ChatExecutionTimelineItemView.swift
//  AI_HLY
//
//  Lightweight, secondary execution presentation for tools, thinking, and agent actions.
//  Uses minimal shimmering text with chevron disclosure; no spinners, icons, or card chrome.
//  Renders compact custom execution UI when a customHandler resolves.
//

import HanlinPlatformContracts
import SwiftUI

struct ChatExecutionTimelineItemView: View {
  let familyID: HanlinExecutionPresentationFamilyID
  let title: String
  let subtitle: String?
  let status: AgentActivityStatus
  let queries: [String]
  let inputPreview: String?
  let outputPreview: String?
  let errorDescription: String?
  let customHandler: String?
  let toolName: String?
  let payload: HanlinEmbeddedResultPayload?
  let onOpenDetails: (() -> Void)?

  @State private var isInlineExpanded = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(
    familyID: HanlinExecutionPresentationFamilyID = .generic,
    title: String,
    subtitle: String? = nil,
    status: AgentActivityStatus,
    queries: [String] = [],
    inputPreview: String? = nil,
    outputPreview: String? = nil,
    errorDescription: String? = nil,
    customHandler: String? = nil,
    toolName: String? = nil,
    payload: HanlinEmbeddedResultPayload? = nil,
    onOpenDetails: (() -> Void)? = nil
  ) {
    self.familyID = familyID
    self.title = title
    self.subtitle = subtitle
    self.status = status
    self.queries = queries
    self.inputPreview = inputPreview
    self.outputPreview = outputPreview
    self.errorDescription = errorDescription
    self.customHandler = customHandler
    self.toolName = toolName
    self.payload = payload
    self.onOpenDetails = onOpenDetails
  }

  init(
    state: ChatExecutionViewState,
    customHandler: String? = nil,
    toolName: String? = nil,
    payload: HanlinEmbeddedResultPayload? = nil,
    onOpenDetails: (() -> Void)? = nil
  ) {
    self.init(
      familyID: state.familyID,
      title: state.title,
      subtitle: state.subtitle,
      status: state.status,
      queries: state.queries,
      inputPreview: state.inputPreview,
      outputPreview: state.outputPreview,
      errorDescription: state.errorDescription,
      customHandler: customHandler,
      toolName: toolName,
      payload: payload,
      onOpenDetails: onOpenDetails
    )
  }

  var body: some View {
    // If a custom execution handler is present and resolves, render compact execution UI
    if let customHandler,
       let session = HanlinEmbeddedResultResolver.shared.resolve(
         handler: customHandler,
         toolName: toolName,
         payload: payload
       ) {
      session.rootView
        .frame(maxHeight: ChatHostPresentationPolicy.maxExecutionHeight)
        .clipped()
        .onDisappear {
          session.tearDown()
        }
    } else {
      lightweightExecutionRow
    }
  }

  // MARK: - Lightweight Text & Shimmer Presentation

  private var lightweightExecutionRow: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 4) {
        Text(displayTitle)
          .font(.subheadline)
          .foregroundStyle(titleColor)
          .lineLimit(1)
          .truncationMode(.tail)
          .chatShimmer(isActive: status == .running || status == .pending)

        if let countBadge {
          Text(countBadge)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color(uiColor: .tertiarySystemFill))
            .clipShape(Capsule())
        }

        if hasDetails {
          Image(systemName: isInlineExpanded ? "chevron.down" : "chevron.forward")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
        }
      }
      .contentShape(Rectangle())
      .onTapGesture {
        if hasDetails {
          toggleInlineExpansion()
        } else {
          onOpenDetails?()
        }
      }

      if isInlineExpanded {
        inlineDetailsView
          .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .padding(.vertical, 2)
  }

  private var displayTitle: String {
    if !title.isEmpty { return title }
    switch familyID {
    case .webSearch:
      return status == .running
        ? String(localized: "Searching the web…") : String(localized: "Web search")
    case .sourceSearch:
      return status == .running
        ? String(localized: "Searching sources…") : String(localized: "Source search")
    case .map:
      return status == .running
        ? String(localized: "Finding location…") : String(localized: "Location found")
    case .command:
      return status == .running
        ? String(localized: "Running command…") : String(localized: "Command completed")
    case .fileOperation:
      return status == .running
        ? String(localized: "Reading files…") : String(localized: "File operation")
    case .codeExecution:
      return status == .running
        ? String(localized: "Executing code…") : String(localized: "Code executed")
    case .imageGeneration:
      return status == .running
        ? String(localized: "Generating image…") : String(localized: "Image generated")
    default:
      return status == .running ? String(localized: "Thinking") : String(localized: "Done")
    }
  }

  private var titleColor: Color {
    if status == .failed {
      return .red
    }
    return .secondary
  }

  private var countBadge: String? {
    if !queries.isEmpty && queries.count > 1 {
      return "\(queries.count)"
    }
    return nil
  }

  private var hasDetails: Bool {
    !queries.isEmpty || inputPreview?.isEmpty == false || outputPreview?.isEmpty == false
      || errorDescription?.isEmpty == false || onOpenDetails != nil
  }

  private func toggleInlineExpansion() {
    if reduceMotion {
      isInlineExpanded.toggle()
    } else {
      withAnimation(.easeInOut(duration: 0.18)) {
        isInlineExpanded.toggle()
      }
    }
  }

  // MARK: - Inline Details View

  private var inlineDetailsView: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(alignment: .leading, spacing: 6) {
        // Queries
        if !queries.isEmpty {
          ForEach(queries, id: \.self) { q in
            HStack(spacing: 4) {
              Image(systemName: "magnifyingglass")
                .font(.caption2)
                .foregroundStyle(.tertiary)
              Text(q)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
          }
        }

        // Input / Arguments preview
        if let input = inputPreview, !input.isEmpty {
          Text(input)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .padding(6)
            .background(Color(uiColor: .tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }

        // Output / Result preview
        if let output = outputPreview, !output.isEmpty {
          Text(output)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(4)
        }

        // Error
        if let error = errorDescription, !error.isEmpty {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
            .lineLimit(3)
        }

        // More details button if inspector callback provided
        if let onOpenDetails {
          Button {
            onOpenDetails()
          } label: {
            Text(String(localized: "View full activity"))
              .font(.caption2.weight(.medium))
              .foregroundStyle(Color.accentColor)
          }
          .padding(.top, 2)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .scrollBounceBehavior(.basedOnSize)
    .frame(maxHeight: ChatHostPresentationPolicy.maxExecutionDetailsHeight)
    .padding(.leading, 12)
    .padding(.top, 2)
    .padding(.bottom, 4)
  }
}
