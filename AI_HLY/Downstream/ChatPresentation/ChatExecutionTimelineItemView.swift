//
//  ChatExecutionTimelineItemView.swift
//  AI_HLY
//
//  Compact, secondary execution timeline item for tools and agent actions,
//  implementing the 8 canonical Hanlin execution presentation families
//  under a shared visual grammar.
//

import SwiftUI

struct ChatExecutionTimelineItemView: View {
  let familyID: ChatHostExecutionFamilyID
  let title: String
  let subtitle: String?
  let status: AgentActivityStatus
  let queries: [String]
  let inputPreview: String?
  let outputPreview: String?
  let errorDescription: String?
  let onOpenDetails: (() -> Void)?

  @State private var isInlineExpanded = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      headerRow

      if isInlineExpanded {
        inlineDetailsView
          .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .padding(.vertical, 3)
    .padding(.horizontal, 10)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(isInlineExpanded ? Color(uiColor: .secondarySystemFill) : Color.clear)
    )
    .frame(
      maxHeight: isInlineExpanded
        ? ChatHostPresentationPolicy.maxExecutionHeight
        : ChatHostPresentationPolicy.standardExecutionRowHeight,
      alignment: .topLeading
    )
    .contentShape(Rectangle())
  }

  // MARK: - Header Row

  private var headerRow: some View {
    HStack(spacing: 8) {
      // Status / Family Icon
      familyIconView
        .frame(width: 18, height: 18)

      // Primary title & subtitle
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 6) {
          Text(displayTitle)
            .font(.subheadline)
            .foregroundStyle(titleColor)
            .lineLimit(1)
            .truncationMode(.tail)

          if let countBadge {
            Text(countBadge)
              .font(.caption2.weight(.medium))
              .foregroundStyle(.secondary)
              .padding(.horizontal, 5)
              .padding(.vertical, 1)
              .background(Color(uiColor: .tertiarySystemFill))
              .clipShape(Capsule())
          }
        }

        if let subtitle, !subtitle.isEmpty, !isInlineExpanded {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      Spacer(minLength: 4)

      // Disclosure Toggle
      if hasDetails {
        Button {
          toggleInlineExpansion()
        } label: {
          Image(systemName: isInlineExpanded ? "chevron.down" : "chevron.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
      }
    }
    .frame(minHeight: ChatHostPresentationPolicy.standardExecutionRowHeight)
    .onTapGesture {
      if hasDetails {
        toggleInlineExpansion()
      } else {
        onOpenDetails?()
      }
    }
  }

  // MARK: - Family Icon

  @ViewBuilder
  private var familyIconView: some View {
    if status == .running || status == .pending {
      ProgressView()
        .controlSize(.mini)
    } else if status == .failed {
      Image(systemName: "exclamationmark.circle.fill")
        .font(.caption)
        .foregroundStyle(Color.red)
    } else {
      Image(systemName: systemImageName)
        .font(.caption)
        .foregroundStyle(Color.secondary)
    }
  }

  private var systemImageName: String {
    switch familyID {
    case .webSearch:
      return "globe"
    case .sourceSearch:
      return "doc.text.magnifyingglass"
    case .mapLocation:
      return "map"
    case .commandExecution:
      return "terminal"
    case .fileOperation:
      return "folder"
    case .codeExecution:
      return "chevron.left.forwardslash.chevron.right"
    case .imageGeneration:
      return "photo.badge.plus"
    default:
      return "sparkle"
    }
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
    case .mapLocation:
      return status == .running
        ? String(localized: "Finding location…") : String(localized: "Location found")
    case .commandExecution:
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
      return status == .running ? String(localized: "Thinking…") : String(localized: "Done")
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
    .padding(.leading, 26)
    .padding(.top, 2)
    .padding(.bottom, 6)
  }
}
