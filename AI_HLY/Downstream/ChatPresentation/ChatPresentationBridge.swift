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

public enum ChatHostSizePreset: String, Codable, Hashable, Sendable {
  case compact
  case standard
  case tall
  case expanded
}

public struct ChatHostSizingPreference: Hashable, Sendable {
  public var preset: ChatHostSizePreset
  public var requestedHeight: CGFloat?

  public init(preset: ChatHostSizePreset = .standard, requestedHeight: CGFloat? = nil) {
    self.preset = preset
    self.requestedHeight = requestedHeight
  }
}

// MARK: - Expansion Modes

public enum ChatHostExpansionMode: String, Codable, Hashable, Sendable {
  case sheet
  case fullScreen
  case window
}

public struct ChatHostExpansionDescriptor: Hashable, Sendable {
  public var mode: ChatHostExpansionMode
  public var title: String?

  public init(mode: ChatHostExpansionMode = .sheet, title: String? = nil) {
    self.mode = mode
    self.title = title
  }
}

// MARK: - Embedded Result Presentation Descriptor

public struct ChatHostEmbeddedPresentationDescriptor: Hashable, Sendable {
  public var sizing: ChatHostSizingPreference
  public var expansion: ChatHostExpansionDescriptor?

  public init(
    sizing: ChatHostSizingPreference = ChatHostSizingPreference(),
    expansion: ChatHostExpansionDescriptor? = nil
  ) {
    self.sizing = sizing
    self.expansion = expansion
  }
}

// MARK: - Tool Execution Presentation Families

public struct ChatHostExecutionFamilyID: RawRepresentable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public static let generic = ChatHostExecutionFamilyID(rawValue: "hanlin.execution.generic")
  public static let webSearch = ChatHostExecutionFamilyID(rawValue: "hanlin.execution.webSearch")
  public static let sourceSearch = ChatHostExecutionFamilyID(
    rawValue: "hanlin.execution.sourceSearch")
  public static let mapLocation = ChatHostExecutionFamilyID(
    rawValue: "hanlin.execution.mapLocation")
  public static let commandExecution = ChatHostExecutionFamilyID(
    rawValue: "hanlin.execution.commandExecution")
  public static let fileOperation = ChatHostExecutionFamilyID(
    rawValue: "hanlin.execution.fileOperation")
  public static let codeExecution = ChatHostExecutionFamilyID(
    rawValue: "hanlin.execution.codeExecution")
  public static let imageGeneration = ChatHostExecutionFamilyID(
    rawValue: "hanlin.execution.imageGeneration")
}

public struct ChatHostExecutionPresentationDescriptor: Hashable, Sendable {
  public var familyID: ChatHostExecutionFamilyID
  public var title: String
  public var detail: String?
  public var status: AgentActivityStatus
  public var progress: Double?  // Nil if indeterminate

  public init(
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
  /// Maps existing tool activity to a standardized execution family.
  static func executionFamily(for activityKind: AgentDisplayActivityKind)
    -> ChatHostExecutionFamilyID
  {
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
      switch block.preferredExpandedPresentation {
      case .fullScreen: return .fullScreen
      case .sheet, .none: return .sheet
      }
    }()
    return ChatHostExpansionDescriptor(mode: mode, title: block.title)
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
