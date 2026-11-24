import Foundation

import HanlinPlatformContracts
import HanlinPresentationKit

public enum AgentDisplayActivityKind: String, Hashable, Sendable {
  case reasoning
  case narrative
  case tool
  case search
  case source
  case document
  case code
  case map
  case calendar
  case health
  case result
  case error
}
public struct AgentDisplayActivity: Identifiable, Hashable {
  public var id: String
  public var kind: AgentDisplayActivityKind
  public var systemImage: String?
  public var icons: HanlinToolIconSet?
  public var title: String
  public var subtitle: String?
  public var narrativeText: String?
  public var status: AgentActivityStatus
  public var startedAt: Date?
  public var completedAt: Date?
  public var queries: [String]
  public var searchProviderName: String?
  public var sources: [AgentActivitySource]
  public var inputPreview: String?
  public var outputPreview: String?
  public var errorDescription: String?
  public var isExpandable: Bool
  public var sourceStepIDs: [UUID]
  public var executionPresentation: HanlinToolExecutionPresentationDescriptor?
  public var embeddedPresentation: HanlinEmbeddedPresentationDescriptor?

  public init(
    id: String,
    kind: AgentDisplayActivityKind,
    systemImage: String? = nil,
    title: String,
    subtitle: String? = nil,
    narrativeText: String? = nil,
    status: AgentActivityStatus,
    startedAt: Date? = nil,
    completedAt: Date? = nil,
    queries: [String] = [],
    searchProviderName: String? = nil,
    sources: [AgentActivitySource] = [],
    inputPreview: String? = nil,
    outputPreview: String? = nil,
    errorDescription: String? = nil,
    isExpandable: Bool = false,
    sourceStepIDs: [UUID] = [],
    executionPresentation: HanlinToolExecutionPresentationDescriptor? = nil,
    embeddedPresentation: HanlinEmbeddedPresentationDescriptor? = nil,
    icons: HanlinToolIconSet? = nil
  ) {
    self.id = id
    self.kind = kind
    self.systemImage = systemImage
    self.icons = icons
    self.title = title
    self.subtitle = subtitle
    self.narrativeText = narrativeText
    self.status = status
    self.startedAt = startedAt
    self.completedAt = completedAt
    self.queries = queries
    self.searchProviderName = searchProviderName
    self.sources = sources
    self.inputPreview = inputPreview
    self.outputPreview = outputPreview
    self.errorDescription = errorDescription
    self.isExpandable = isExpandable
    self.sourceStepIDs = sourceStepIDs
    self.executionPresentation = executionPresentation
    self.embeddedPresentation = embeddedPresentation
  }
}
public struct AgentDisplayTimeline: Hashable {
  public var summaryTitle: String
  public var activities: [AgentDisplayActivity]
  public var totalDuration: TimeInterval?
  public var status: AgentActivityStatus

    public init(
        summaryTitle: String,
        activities: [AgentDisplayActivity],
        totalDuration: TimeInterval? = nil,
        status: AgentActivityStatus
    ) {
        self.summaryTitle = summaryTitle
        self.activities = activities
        self.totalDuration = totalDuration
        self.status = status
    }
}
