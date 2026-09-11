import Foundation

import HanlinPlatformContracts

enum AgentDisplayActivityKind: String, Hashable, Sendable {
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
struct AgentDisplayActivity: Identifiable, Hashable {
  var id: String
  var kind: AgentDisplayActivityKind
  var systemImage: String?
  var title: String
  var subtitle: String?
  var narrativeText: String?
  var status: AgentActivityStatus
  var startedAt: Date?
  var completedAt: Date?
  var queries: [String]
  var searchProviderName: String?
  var sources: [AgentActivitySource]
  var inputPreview: String?
  var outputPreview: String?
  var errorDescription: String?
  var isExpandable: Bool
  var sourceStepIDs: [UUID]
  var executionPresentation: HanlinToolExecutionPresentationDescriptor?
  var embeddedPresentation: HanlinEmbeddedPresentationDescriptor?

  init(
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
    embeddedPresentation: HanlinEmbeddedPresentationDescriptor? = nil
  ) {
    self.id = id
    self.kind = kind
    self.systemImage = systemImage
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
struct AgentDisplayTimeline: Hashable {
  var summaryTitle: String
  var activities: [AgentDisplayActivity]
  var totalDuration: TimeInterval?
  var status: AgentActivityStatus
}
