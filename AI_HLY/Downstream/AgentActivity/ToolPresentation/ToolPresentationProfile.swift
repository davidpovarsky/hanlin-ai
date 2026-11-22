import Foundation

import HanlinPlatformContracts

enum ToolActivityPresentationKind: String, Codable, Hashable, Sendable {
  case search
  case retrieve
  case read
  case write
  case execute
  case calculate
  case navigate
  case generate
  case communicate
  case inspect
  case generic
}
struct ToolActivityPresentationDescriptor: Codable, Hashable, Sendable {
  var kind: ToolActivityPresentationKind
  var systemImage: String
  var runningTitle: String
  var completedTitle: String
  var failedTitle: String
  var visibleArgumentKeys: [String]
}
enum ToolResultRendererKind: String, Codable, Hashable, Sendable {
  case modernNative
  case legacyExisting
}
struct ToolResultPresentationDescriptor: Codable, Hashable, Sendable {
  var rendererKind: ToolResultRendererKind
  var supportsCard: Bool
}
enum ToolResultDisplayPolicy: String, Codable, Hashable, Sendable {
  case never
  case modelControlled
  case always
}
enum ToolResultPresentationRequest: String, Codable, Hashable, Sendable {
  case none
  case card
}
struct ToolPresentationProfile: Codable, Hashable, Sendable {
  var identity: String
  var activity: ToolActivityPresentationDescriptor
  var result: ToolResultPresentationDescriptor?
  var resultDisplayPolicy: ToolResultDisplayPolicy
  var canonicalExecutionPresentation: HanlinToolExecutionPresentationDescriptor?
  var canonicalEmbeddedPresentation: HanlinEmbeddedPresentationDescriptor?

  init(
    identity: String,
    activity: ToolActivityPresentationDescriptor,
    result: ToolResultPresentationDescriptor? = nil,
    resultDisplayPolicy: ToolResultDisplayPolicy = .never,
    canonicalExecutionPresentation: HanlinToolExecutionPresentationDescriptor? = nil,
    canonicalEmbeddedPresentation: HanlinEmbeddedPresentationDescriptor? = nil
  ) {
    self.identity = identity
    self.activity = activity
    self.result = result
    self.resultDisplayPolicy = resultDisplayPolicy
    self.canonicalExecutionPresentation = canonicalExecutionPresentation
    self.canonicalEmbeddedPresentation = canonicalEmbeddedPresentation
  }

  /// Uses explicit provider/native profile metadata, never tool-name heuristics.
  var resolvedExecutionPresentation: HanlinToolExecutionPresentationDescriptor {
    let preset: HanlinToolExecutionAnimationPreset
    switch activity.kind {
    case .search, .retrieve: preset = .search
    case .execute, .calculate: preset = .execution
    default: preset = .common
    }
    return .init(
      familyID: canonicalExecutionPresentation?.familyID,
      customHandler: canonicalExecutionPresentation?.customHandler,
      systemImage: canonicalExecutionPresentation?.systemImage ?? activity.systemImage,
      animation: canonicalExecutionPresentation?.animation
        ?? (canonicalExecutionPresentation?.familyID == nil ? preset : canonicalExecutionPresentation?.resolvedAnimation)
    )
  }

  static func generic(toolName: String) -> ToolPresentationProfile {
    ToolPresentationProfile(
      identity: "generic.\(toolName)",
      activity: ToolActivityPresentationDescriptor(
        kind: .generic,
        systemImage: "wrench.and.screwdriver",
        runningTitle: String(localized: "Using a tool"),
        completedTitle: String(localized: "Used a tool"),
        failedTitle: String(localized: "Tool failed"),
        visibleArgumentKeys: []
      ),
      result: nil,
      resultDisplayPolicy: .never
    )
  }

  static func modernNative(
    toolName: String,
    kind: ToolActivityPresentationKind,
    systemImage: String,
    runningTitle: LocalizedStringResource,
    completedTitle: LocalizedStringResource,
    failedTitle: LocalizedStringResource = "Tool failed",
    visibleArgumentKeys: [String],
    supportsCard: Bool = true,
    canonicalExecutionPresentation: HanlinToolExecutionPresentationDescriptor? = nil,
    canonicalEmbeddedPresentation: HanlinEmbeddedPresentationDescriptor? = nil
  ) -> ToolPresentationProfile {
    ToolPresentationProfile(
      identity: "native.\(toolName)",
      activity: ToolActivityPresentationDescriptor(
        kind: kind,
        systemImage: systemImage,
        runningTitle: String(localized: runningTitle),
        completedTitle: String(localized: completedTitle),
        failedTitle: String(localized: failedTitle),
        visibleArgumentKeys: visibleArgumentKeys
      ),
      result: supportsCard
        ? ToolResultPresentationDescriptor(rendererKind: .modernNative, supportsCard: true)
        : nil,
      resultDisplayPolicy: supportsCard ? .modelControlled : .never,
      canonicalExecutionPresentation: canonicalExecutionPresentation,
      canonicalEmbeddedPresentation: canonicalEmbeddedPresentation
    )
  }

  static func canonical(
    toolName: String,
    presentation: HanlinToolPresentationDescriptor
  ) -> ToolPresentationProfile {
    let kind: ToolActivityPresentationKind = {
      switch presentation.executionPresentation?.familyID {
      case .webSearch?: return .search
      case .sourceSearch?: return .retrieve
      case .codeExecution?: return .execute
      case .map?: return .navigate
      default: return .generic
      }
    }()
    let systemImage = presentation.executionPresentation?.resolvedSystemImage
      ?? "wrench.and.screwdriver"
    let supportsCard = presentation.embeddedPresentation != nil
    return ToolPresentationProfile(
      identity: "canonical.\(toolName)",
      activity: ToolActivityPresentationDescriptor(
        kind: kind,
        systemImage: systemImage,
        runningTitle: String(localized: "Using a tool"),
        completedTitle: String(localized: "Used a tool"),
        failedTitle: String(localized: "Tool failed"),
        visibleArgumentKeys: []
      ),
      result: supportsCard
        ? ToolResultPresentationDescriptor(rendererKind: .modernNative, supportsCard: true)
        : nil,
      resultDisplayPolicy: supportsCard ? .modelControlled : .never,
      canonicalExecutionPresentation: presentation.executionPresentation,
      canonicalEmbeddedPresentation: presentation.embeddedPresentation
    )
  }
}
extension ToolActivityPresentationKind {
  var agentActivityKind: AgentActivityKind {
    switch self {
    case .search: .webSearch
    case .retrieve, .read: .sourceRead
    case .execute, .calculate: .codeExecution
    case .navigate: .map
    case .write, .generate, .communicate, .inspect, .generic: .toolExecution
    }
  }

  var displayActivityKind: AgentDisplayActivityKind {
    switch self {
    case .search: .search
    case .retrieve, .read: .source
    case .execute, .calculate: .code
    case .navigate: .map
    case .write, .generate, .communicate, .inspect, .generic: .tool
    }
  }
}
