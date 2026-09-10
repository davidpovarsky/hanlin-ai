//
//  ChatPresentationBridge.swift
//  AI_HLY
//
//  ISOLATED TEMPORARY PRESENTATION BRIDGE
//  Branch: feature/chat-agent-presentation
//
//  This file isolates interim host presentation request structures corresponding
//  to the presentation contracts being designed on feature/universal-miniapps.
//  DO NOT re-export or leak these temporary names across the broader codebase.
//  When the architecture branch lands with canonical HanlinPlatformContracts,
//  this single bridge file will be updated/replaced during rebase.
//

import SwiftUI

// MARK: - Embedded Result Sizing & Presets

enum ChatHostSizePreset: String, Codable, Hashable, Sendable {
  case compact
  case standard
  case tall
  case expanded
}

struct ChatHostSizingPreference: Hashable, Sendable {
  var preset: ChatHostSizePreset
  var requestedHeight: CGFloat?

  init(preset: ChatHostSizePreset = .standard, requestedHeight: CGFloat? = nil) {
    self.preset = preset
    self.requestedHeight = requestedHeight
  }
}

// MARK: - Expansion Modes

enum ChatHostExpansionMode: String, Codable, Hashable, Sendable {
  case sheet
  case fullScreen
  case window
}

enum ChatHostContainerStyle: String, Codable, Hashable, Sendable {
  /// The hosted content already owns its visual card styling (e.g. ModernCards).
  /// The host behaves as a neutral layout host and avoids duplicate borders, backgrounds, or nested scroll views.
  case neutral
  /// Plain or unstyled content that requires a bounded card frame, background, and internal scroll management.
  case borderedCard
}

struct ChatHostExpansionDescriptor: Hashable, Sendable {
  var mode: ChatHostExpansionMode
  var title: String?
  var launchRequest: NativeAppLaunchRequest?

  init(
    mode: ChatHostExpansionMode = .sheet,
    title: String? = nil,
    launchRequest: NativeAppLaunchRequest? = nil
  ) {
    self.mode = mode
    self.title = title
    self.launchRequest = launchRequest
  }
}

// MARK: - Embedded Result Presentation Descriptor

struct ChatHostEmbeddedPresentationDescriptor: Hashable, Sendable {
  var sizing: ChatHostSizingPreference
  var expansion: ChatHostExpansionDescriptor?

  init(
    sizing: ChatHostSizingPreference = ChatHostSizingPreference(),
    expansion: ChatHostExpansionDescriptor? = nil
  ) {
    self.sizing = sizing
    self.expansion = expansion
  }
}

// MARK: - Tool Execution Presentation Families

struct ChatHostExecutionFamilyID: RawRepresentable, Hashable, Sendable {
  let rawValue: String

  init(rawValue: String) {
    self.rawValue = rawValue
  }

  static let generic = ChatHostExecutionFamilyID(rawValue: "hanlin.execution.generic")
  static let webSearch = ChatHostExecutionFamilyID(rawValue: "hanlin.execution.webSearch")
  static let sourceSearch = ChatHostExecutionFamilyID(
    rawValue: "hanlin.execution.sourceSearch")
  static let mapLocation = ChatHostExecutionFamilyID(
    rawValue: "hanlin.execution.mapLocation")
  static let commandExecution = ChatHostExecutionFamilyID(
    rawValue: "hanlin.execution.commandExecution")
  static let fileOperation = ChatHostExecutionFamilyID(
    rawValue: "hanlin.execution.fileOperation")
  static let codeExecution = ChatHostExecutionFamilyID(
    rawValue: "hanlin.execution.codeExecution")
  static let imageGeneration = ChatHostExecutionFamilyID(
    rawValue: "hanlin.execution.imageGeneration")
}

struct ChatHostExecutionPresentationDescriptor: Hashable, Sendable {
  var familyID: ChatHostExecutionFamilyID
  var title: String
  var detail: String?
  var status: AgentActivityStatus
  var progress: Double?  // Nil if indeterminate

  init(
    familyID: ChatHostExecutionFamilyID = .generic,
    title: String,
    detail: String? = nil,
    status: AgentActivityStatus = .running,
    progress: Double? = nil
  ) {
    self.familyID = familyID
    self.title = title
    self.detail = detail
    self.status = status
    self.progress = progress
  }
}

// MARK: - Bridge Helpers & Adapters

enum ChatPresentationBridge {
  /// Maps existing tool activity and toolName metadata to a standardized execution family.
  static func executionFamily(
    for activityKind: AgentDisplayActivityKind?,
    toolName: String? = nil
  ) -> ChatHostExecutionFamilyID {
    if let toolName = toolName?.lowercased(), !toolName.isEmpty {
      if toolName == "write_system_event" || toolName == "run_command"
        || toolName.contains("command") || toolName.contains("terminal")
      {
        return .commandExecution
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
        return .mapLocation
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

    if let activityKind {
      switch activityKind {
      case .search:
        return .webSearch
      case .source, .document:
        return .sourceSearch
      case .code:
        return .codeExecution
      case .map:
        return .mapLocation
      case .reasoning, .narrative, .tool, .result, .health, .calendar, .error:
        return .generic
      }
    }

    return .generic
  }

  private static func hasExpandableContent(_ block: NativeUIBlock) -> Bool {
    let itemLimit = block.compactItemLimit ?? 4
    let lineLimit = block.compactLineLimit ?? 8
    return block.items.count > itemLimit
      || block.keyValues.count > itemLimit
      || !block.children.isEmpty
      || (block.body?.count ?? 0) > lineLimit * 24
      || block.type == .searchResults && !block.items.isEmpty
  }

  /// Adapts existing NativeUIBlock expansion preferences to ChatHostExpansionDescriptor.
  static func expansionDescriptor(for blocks: [NativeUIBlock]) -> ChatHostExpansionDescriptor? {
    guard
      let block = blocks.first(where: { ($0.allowsExpansion ?? true) && hasExpandableContent($0) })
    else {
      return nil
    }
    let mode: ChatHostExpansionMode = {
      if block.actions.contains(where: { $0.presentationStyle == .newWindow }) {
        return .window
      }
      switch block.preferredExpandedPresentation {
      case .fullScreen: return .fullScreen
      case .sheet, .none: return .sheet
      }
    }()

    guard ChatHostPresentationPolicy.isExpansionModeAvailable(mode) else {
      return nil
    }

    var launchRequest: NativeAppLaunchRequest? = nil
    for action in block.actions {
      if let route = action.route {
        let style: NativeAppPresentationStyle =
          action.presentationStyle
          ?? (mode == .window ? .newWindow : (mode == .fullScreen ? .fullScreen : .largeSheet))
        launchRequest = NativeAppLaunchRequest(
          appID: route.appID,
          presentationStyle: style,
          initialRoute: route
        )
        break
      }
    }

    return ChatHostExpansionDescriptor(mode: mode, title: block.title, launchRequest: launchRequest)
  }

  /// Adapts existing NativeUIBlock compact preferences to ChatHostSizingPreference.
  static func sizingPreference(for blocks: [NativeUIBlock]) -> ChatHostSizingPreference {
    if blocks.contains(where: { $0.type == .searchResults }) {
      return ChatHostSizingPreference(preset: .standard)
    }
    if blocks.contains(where: { $0.type == .error || $0.type == .calculation }) {
      return ChatHostSizingPreference(preset: .compact)
    }
    return ChatHostSizingPreference(preset: .standard)
  }
}
