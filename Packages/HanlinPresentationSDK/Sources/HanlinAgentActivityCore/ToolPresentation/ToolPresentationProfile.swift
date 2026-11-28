import HanlinLocalization
import Foundation

import HanlinPlatformContracts
import HanlinPresentationKit

public enum ToolActivityPresentationKind: String, Codable, Hashable, Sendable {
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
public struct ToolActivityPresentationDescriptor: Codable, Hashable, Sendable {
  public var kind: ToolActivityPresentationKind
  public var systemImage: String
  public var runningTitle: String
  public var completedTitle: String
  public var failedTitle: String
  public var visibleArgumentKeys: [String]
  public var icons: HanlinToolIconSet? = nil

    public init(
        kind: ToolActivityPresentationKind,
        systemImage: String,
        runningTitle: String,
        completedTitle: String,
        failedTitle: String,
        visibleArgumentKeys: [String],
        icons: HanlinToolIconSet? = nil
    ) {
        self.kind = kind
        self.systemImage = systemImage
        self.runningTitle = runningTitle
        self.completedTitle = completedTitle
        self.failedTitle = failedTitle
        self.visibleArgumentKeys = visibleArgumentKeys
        self.icons = icons
    }
}
public enum ToolResultRendererKind: String, Codable, Hashable, Sendable {
  case modernNative
  case legacyExisting
}
public struct ToolResultPresentationDescriptor: Codable, Hashable, Sendable {
  public var rendererKind: ToolResultRendererKind
  public var supportsCard: Bool

    public init(
        rendererKind: ToolResultRendererKind,
        supportsCard: Bool
    ) {
        self.rendererKind = rendererKind
        self.supportsCard = supportsCard
    }
}
public enum ToolResultDisplayPolicy: String, Codable, Hashable, Sendable {
  case never
  case modelControlled
  case always
}
public enum ToolResultPresentationRequest: String, Codable, Hashable, Sendable {
  case none
  case card
}
public struct ToolPresentationProfile: Codable, Hashable, Sendable {
  public var identity: String
  public var activity: ToolActivityPresentationDescriptor
  public var result: ToolResultPresentationDescriptor?
  public var resultDisplayPolicy: ToolResultDisplayPolicy
  public var canonicalExecutionPresentation: HanlinToolExecutionPresentationDescriptor?
  public var canonicalEmbeddedPresentation: HanlinEmbeddedPresentationDescriptor?

  public init(
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
  public var resolvedExecutionPresentation: HanlinToolExecutionPresentationDescriptor {
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

  public static func generic(toolName: String) -> ToolPresentationProfile {
    ToolPresentationProfile(
      identity: "generic.\(toolName)",
      activity: ToolActivityPresentationDescriptor(
        kind: .generic,
        systemImage: "wrench.and.screwdriver",
        runningTitle: String(localized: "Using a tool", bundle: HanlinLocalization.bundle),
        completedTitle: String(localized: "Used a tool", bundle: HanlinLocalization.bundle),
        failedTitle: String(localized: "Tool failed", bundle: HanlinLocalization.bundle),
        visibleArgumentKeys: []
      ),
      result: nil,
      resultDisplayPolicy: .never
    )
  }

  public static func modernNative(
    toolName: String,
    kind: ToolActivityPresentationKind,
    systemImage: String,
    runningTitle: LocalizedStringResource,
    completedTitle: LocalizedStringResource,
    failedTitle: LocalizedStringResource = HanlinLocalization.resource("Tool failed"),
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

  public static func canonical(
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
        runningTitle: String(localized: "Using a tool", bundle: HanlinLocalization.bundle),
        completedTitle: String(localized: "Used a tool", bundle: HanlinLocalization.bundle),
        failedTitle: String(localized: "Tool failed", bundle: HanlinLocalization.bundle),
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
  public var agentActivityKind: AgentActivityKind {
    switch self {
    case .search: .webSearch
    case .retrieve, .read: .sourceRead
    case .execute, .calculate: .codeExecution
    case .navigate: .map
    case .write, .generate, .communicate, .inspect, .generic: .toolExecution
    }
  }

  public var displayActivityKind: AgentDisplayActivityKind {
    switch self {
    case .search: .search
    case .retrieve, .read: .source
    case .execute, .calculate: .code
    case .navigate: .map
    case .write, .generate, .communicate, .inspect, .generic: .tool
    }
  }
}
