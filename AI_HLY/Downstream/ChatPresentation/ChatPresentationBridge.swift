//
//  ChatPresentationBridge.swift
//  AI_HLY
//
//  Adapter bridging canonical HanlinPlatformContracts presentation metadata
//  to host-specific Chat presentation and legacy NativeUIBlock structures.
//

import HanlinPlatformContracts
import SwiftUI

// MARK: - Host Container Style

enum ChatHostContainerStyle: String, Codable, Hashable, Sendable {
  /// The hosted content already owns its visual card styling (e.g. ModernCards).
  /// The host behaves as a neutral layout host and avoids duplicate borders, backgrounds, or nested scroll views.
  case neutral
  /// Plain or unstyled content that requires a bounded card frame, background, and internal scroll management.
  case borderedCard
}

// MARK: - Host-Specific Resolved View Models

/// Host-specific resolved expansion state combining canonical expansion mode
/// with host presentation concerns (title, native launch routing).
struct ChatResolvedExpansion: Hashable, Sendable {
  var mode: HanlinExpansionMode
  var title: String?
  var launchRequest: NativeAppLaunchRequest?
  var expandedHandler: String?

  init(
    mode: HanlinExpansionMode,
    title: String? = nil,
    launchRequest: NativeAppLaunchRequest? = nil,
    expandedHandler: String? = nil
  ) {
    self.mode = mode
    self.title = title
    self.launchRequest = launchRequest
    self.expandedHandler = expandedHandler
  }
}

/// Host-specific view model representing an execution timeline row's display state.
struct ChatExecutionViewState: Hashable, Sendable {
  var familyID: HanlinExecutionPresentationFamilyID
  var title: String
  var subtitle: String?
  var status: AgentActivityStatus
  var progress: Double?  // Nil if indeterminate
  var queries: [String]
  var inputPreview: String?
  var outputPreview: String?
  var errorDescription: String?

  init(
    familyID: HanlinExecutionPresentationFamilyID = .generic,
    title: String,
    subtitle: String? = nil,
    status: AgentActivityStatus = .running,
    progress: Double? = nil,
    queries: [String] = [],
    inputPreview: String? = nil,
    outputPreview: String? = nil,
    errorDescription: String? = nil
  ) {
    self.familyID = familyID
    self.title = title
    self.subtitle = subtitle
    self.status = status
    self.progress = progress
    self.queries = queries
    self.inputPreview = inputPreview
    self.outputPreview = outputPreview
    self.errorDescription = errorDescription
  }
}

// MARK: - Presentation Bridge / Adapter

enum ChatPresentationBridge {

  // MARK: - Canonical Tool Lookup

  /// Look up canonical tool descriptor by tool name across registered built-in canonical Mini Apps.
  static func findCanonicalTool(named toolName: String) -> HanlinToolDescriptor? {
    for registration in BuiltinCanonicalRegistrations.all {
      if let tool = registration.descriptor.tools.first(where: {
        $0.logicalID.localToolID.rawValue == toolName
      }) {
        return tool
      }
    }
    return nil
  }

  // MARK: - Execution Presentation

  /// Maps tool activity and toolName metadata to a canonical HanlinExecutionPresentationFamilyID.
  /// Precedence:
  /// 1. Explicit attached HanlinToolExecutionPresentationDescriptor from activity/transcript item
  /// 2. Secondary compatibility fallback: Declared descriptor from built-in canonical registrations
  /// 3. Heuristic mapping from toolName
  /// 4. Heuristic mapping from activityKind
  /// 5. Generic default
  static func executionFamily(
    explicit: HanlinToolExecutionPresentationDescriptor? = nil,
    for activityKind: AgentDisplayActivityKind? = nil,
    toolName: String? = nil
  ) -> HanlinExecutionPresentationFamilyID {
    // 1. Explicit attached descriptor from activity/transcript item
    if let explicit, let familyID = explicit.familyID {
      return familyID
    }

    // 2. Secondary compatibility fallback: Built-in canonical tool lookup
    if let toolName, !toolName.isEmpty {
      if let canonicalTool = findCanonicalTool(named: toolName),
        let execDesc = canonicalTool.presentation.executionPresentation,
        let familyID = execDesc.familyID
      {
        return familyID
      }
    }

    // 2. Fallback to existing reliable toolName heuristics
    if let toolName = toolName?.lowercased(), !toolName.isEmpty {
      if toolName == "write_system_event" || toolName == "run_command"
        || toolName.contains("command") || toolName.contains("terminal")
      {
        return .command
      }
      if toolName == "extract_remote_file_content" || toolName == "fileutility"
        || toolName == "create_knowledge_document" || toolName.contains("file")
      {
        return .fileOperation
      }
      if toolName == "create_canvas" || toolName == "edit_canvas"
        || toolName.contains("image") || toolName.contains("canvas")
      {
        return .imageGeneration
      }
      if toolName == "execute_python_code" || toolName == "python"
        || toolName.contains("code")
      {
        return .codeExecution
      }
      if toolName == "query_location" || toolName == "get_current_location"
        || toolName == "search_nearby_locations" || toolName == "get_route"
        || toolName.contains("map") || toolName.contains("location")
      {
        return .map
      }
      if toolName == "search_knowledge_bag" || toolName == "retrieve_memory"
        || toolName == "save_memory" || toolName == "update_memory"
      {
        return .sourceSearch
      }
      if toolName == "search_online" || toolName == "search_arxiv_papers"
        || toolName == "read_web_page" || toolName.contains("search")
      {
        return .webSearch
      }
    }

    // 3. Fallback to activityKind
    if let activityKind {
      switch activityKind {
      case .search:
        return .webSearch
      case .source, .document:
        return .sourceSearch
      case .code:
        return .codeExecution
      case .map:
        return .map
      case .reasoning, .narrative, .tool, .result, .health, .calendar, .error:
        return .generic
      }
    }

    return .generic
  }

  // MARK: - Expansion Resolution

  /// Resolves canonical expansion descriptor according to host policy:
  /// 1. No descriptor or empty supported modes -> nil (no affordance).
  /// 2. Iterates declared supportedModes in preference order.
  /// 3. Selects first mode the host/device can legitimately honor.
  /// 4. Host policy decides availability.
  /// 5. Does NOT silently turn unsupported .window into .sheet.
  /// 6. Preserves NativeAppLaunchRequest for window routes.
  static func resolveExpansion(
    descriptor: HanlinExpansionDescriptor?,
    title: String? = nil,
    launchRequest: NativeAppLaunchRequest? = nil
  ) -> ChatResolvedExpansion? {
    guard let descriptor = descriptor, !descriptor.supportedModes.isEmpty else {
      return nil
    }

    for mode in descriptor.supportedModes {
      if ChatHostPresentationPolicy.isExpansionModeAvailable(mode) {
        return ChatResolvedExpansion(
          mode: mode,
          title: title,
          launchRequest: launchRequest,
          expandedHandler: descriptor.expandedHandler
        )
      }
    }

    return nil
  }

  // MARK: - Legacy NativeUIBlock Adapters

  private static func hasExpandableContent(_ block: NativeUIBlock) -> Bool {
    let itemLimit = block.compactItemLimit ?? 4
    let lineLimit = block.compactLineLimit ?? 8
    return block.items.count > itemLimit
      || block.keyValues.count > itemLimit
      || !block.children.isEmpty
      || (block.body?.count ?? 0) > lineLimit * 24
      || block.type == .searchResults && !block.items.isEmpty
  }

  /// Adapts NativeUIBlock and canonical tool expansion preferences to ChatResolvedExpansion.
  /// Precedence:
  /// 1. Explicit attached HanlinExpansionDescriptor from activity/transcript item
  /// 2. Secondary compatibility fallback: Built-in canonical tool lookup
  /// 3. Heuristic / NativeUIBlock actions fallback
  static func expansionDescriptor(
    explicit: HanlinExpansionDescriptor? = nil,
    for blocks: [NativeUIBlock] = [],
    toolName: String? = nil
  ) -> ChatResolvedExpansion? {
    // 1. Explicit attached canonical expansion descriptor
    let canonicalExpansion: HanlinExpansionDescriptor? =
      explicit
      ?? {
        // 2. Secondary compatibility fallback: Built-in canonical tool lookup
        if let toolName, let tool = findCanonicalTool(named: toolName),
          let embedded = tool.presentation.embeddedPresentation
        {
          return embedded.expansion
        }
        return nil
      }()

    guard
      let block = blocks.first(where: { ($0.allowsExpansion ?? true) && hasExpandableContent($0) })
    else {
      if let canonicalExpansion {
        return resolveExpansion(descriptor: canonicalExpansion, title: toolName)
      }
      return nil
    }

    var launchRequest: NativeAppLaunchRequest? = nil
    for action in block.actions {
      if let route = action.route {
        let style: NativeAppPresentationStyle = action.presentationStyle ?? .largeSheet
        launchRequest = NativeAppLaunchRequest(
          appID: route.appID,
          presentationStyle: style,
          initialRoute: route
        )
        break
      }
    }

    let descriptor =
      canonicalExpansion
      ?? {
        let preferredModes: [HanlinExpansionMode] = {
          if block.actions.contains(where: { $0.presentationStyle == .newWindow }) {
            return [.window]
          }
          switch block.preferredExpandedPresentation {
          case .fullScreen: return [.fullScreen]
          case .sheet, .none: return [.sheet]
          }
        }()
        return HanlinExpansionDescriptor(supportedModes: preferredModes)
      }()

    return resolveExpansion(
      descriptor: descriptor,
      title: block.title ?? toolName,
      launchRequest: launchRequest
    )
  }

  static func expansionDescriptor(
    explicit: HanlinEmbeddedPresentationDescriptor?,
    for blocks: [NativeUIBlock] = [],
    toolName: String? = nil
  ) -> ChatResolvedExpansion? {
    expansionDescriptor(explicit: explicit?.expansion, for: blocks, toolName: toolName)
  }

  /// Adapts NativeUIBlock and canonical tool sizing preferences to HanlinEmbeddedSizingPreference.
  /// Precedence:
  /// 1. Explicit attached HanlinEmbeddedSizingPreference from activity/transcript item
  /// 2. Secondary compatibility fallback: Built-in canonical tool lookup
  /// 3. Heuristic sizing based on NativeUIBlock content
  static func sizingPreference(
    explicit: HanlinEmbeddedSizingPreference? = nil,
    for blocks: [NativeUIBlock] = [],
    toolName: String? = nil
  ) -> HanlinEmbeddedSizingPreference {
    // 1. Explicit attached preference
    if let explicit {
      return explicit
    }

    // 2. Secondary compatibility fallback: Built-in canonical tool lookup
    if let toolName, let tool = findCanonicalTool(named: toolName),
      let embedded = tool.presentation.embeddedPresentation
    {
      return embedded.sizing
    }

    // 3. Fallback heuristics from blocks
    if blocks.contains(where: { $0.type == .searchResults }) {
      return HanlinEmbeddedSizingPreference(preset: .regular)
    }
    if blocks.contains(where: { $0.type == .error || $0.type == .calculation }) {
      return HanlinEmbeddedSizingPreference(preset: .compact)
    }
    return HanlinEmbeddedSizingPreference(preset: .regular)
  }

  static func sizingPreference(
    explicit: HanlinEmbeddedPresentationDescriptor?,
    for blocks: [NativeUIBlock] = [],
    toolName: String? = nil
  ) -> HanlinEmbeddedSizingPreference {
    sizingPreference(explicit: explicit?.sizing, for: blocks, toolName: toolName)
  }
}
