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
/// with host presentation concerns (title, canonical HanlinLaunchRequest, legacy routing).
struct ChatResolvedExpansion: Hashable, Sendable {
  var mode: HanlinExpansionMode
  var title: String?
  var launchRequest: HanlinLaunchRequest?
  var legacyLaunchRequest: NativeAppLaunchRequest?
  var expandedHandler: String?

  init(
    mode: HanlinExpansionMode,
    title: String? = nil,
    launchRequest: HanlinLaunchRequest? = nil,
    legacyLaunchRequest: NativeAppLaunchRequest? = nil,
    expandedHandler: String? = nil
  ) {
    self.mode = mode
    self.title = title
    self.launchRequest = launchRequest
    self.legacyLaunchRequest = legacyLaunchRequest
    self.expandedHandler = expandedHandler
  }

  init(
    mode: HanlinExpansionMode,
    title: String? = nil,
    launchRequest: NativeAppLaunchRequest?,
    expandedHandler: String? = nil
  ) {
    self.mode = mode
    self.title = title
    self.launchRequest = launchRequest.map { HanlinLaunchRequest(from: $0) }
    self.legacyLaunchRequest = launchRequest
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

@MainActor
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
      if toolName == "execute_remote_python_code" || toolName == "execute_python_code" || toolName == "python"
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

  /// Resolves canonical expansion descriptor into all valid and supported host expansion modes:
  /// 1. No descriptor or empty supported modes -> empty array.
  /// 2. Iterates declared supportedModes in declared order.
  /// 3. Filters out modes the host/device cannot legitimately honor.
  /// 4. Does NOT silently turn unsupported .window into .sheet.
  /// 5. Validates that declared expandedHandler is valid/resolvable if specified.
  static func resolveExpansions(
    descriptor: HanlinExpansionDescriptor?,
    title: String? = nil,
    launchRequest: HanlinLaunchRequest? = nil,
    legacyLaunchRequest: NativeAppLaunchRequest? = nil,
    handler: String? = nil,
    canResolveHandler: ((String) -> Bool)? = nil
  ) -> [ChatResolvedExpansion] {
    guard let descriptor = descriptor, !descriptor.supportedModes.isEmpty else {
      return []
    }

    var results: [ChatResolvedExpansion] = []
    let effectiveHandler = descriptor.expandedHandler ?? handler

    for mode in descriptor.supportedModes {
      // 1. Check host/platform availability
      guard ChatHostPresentationPolicy.isExpansionModeAvailable(mode) else {
        continue
      }

      // 2. If expansion declares an expandedHandler, verify it resolves
      if let expHandler = descriptor.expandedHandler {
        guard !expHandler.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          continue
        }
        if let canResolve = canResolveHandler, !canResolve(expHandler) {
          continue
        }
      }

      results.append(
        ChatResolvedExpansion(
          mode: mode,
          title: title,
          launchRequest: launchRequest,
          legacyLaunchRequest: legacyLaunchRequest,
          expandedHandler: effectiveHandler
        )
      )
    }

    return results
  }

  /// Single expansion resolver for backwards compatibility.
  static func resolveExpansion(
    descriptor: HanlinExpansionDescriptor?,
    title: String? = nil,
    launchRequest: NativeAppLaunchRequest? = nil
  ) -> ChatResolvedExpansion? {
    resolveExpansions(
      descriptor: descriptor,
      title: title,
      legacyLaunchRequest: launchRequest
    ).first
  }

  static func resolveExpansion(
    descriptor: HanlinExpansionDescriptor?,
    title: String? = nil,
    launchRequest: HanlinLaunchRequest? = nil
  ) -> ChatResolvedExpansion? {
    resolveExpansions(
      descriptor: descriptor,
      title: title,
      launchRequest: launchRequest
    ).first
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

// MARK: - Launch Request Conversions

extension HanlinLaunchRequest {
  init(from legacy: NativeAppLaunchRequest) {
    let appID = (try? HanlinAppID(validating: legacy.appID)) ?? HanlinAppID(unchecked: legacy.appID)
    let launchID = HanlinLaunchID(unchecked: legacy.id.uuidString)
    let reqID = HanlinRequestID(unchecked: legacy.id.uuidString)
    let intent: HanlinPresentationIntent = switch legacy.presentationStyle {
    case .fullScreen: .fullScreen
    case .largeSheet: .sheet
    case .newWindow: .window
    }
    self.init(
      id: launchID,
      requestID: reqID,
      target: HanlinLaunchTarget(appID: appID),
      presentation: intent,
      initialRoute: nil,
      origin: .chatUI
    )
  }

  func toLegacy() -> NativeAppLaunchRequest {
    NativeAppLaunchRequest(from: self)
  }
}

extension NativeAppLaunchRequest {
  init(from canonical: HanlinLaunchRequest) {
    let style: NativeAppPresentationStyle = switch canonical.presentation {
    case .fullScreen: .fullScreen
    case .sheet: .largeSheet
    case .window: .newWindow
    case .inline: .largeSheet
    }
    self.init(
      id: UUID(uuidString: canonical.id.rawValue) ?? UUID(),
      appID: canonical.target.appID.rawValue,
      presentationStyle: style,
      initialRoute: nil
    )
  }

  func toCanonical() -> HanlinLaunchRequest {
    HanlinLaunchRequest(from: self)
  }
}
