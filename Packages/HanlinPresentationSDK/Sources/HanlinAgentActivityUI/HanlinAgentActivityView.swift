import Foundation
import SwiftUI
import HanlinAgentActivityCore
import HanlinChatUI
import HanlinPresentationKit
import HanlinLocalization
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public nonisolated struct HanlinAgentActivityView: View, Equatable {
    public static func presentationRun(_ original: AgentRun?) -> AgentRun? {
        HanlinAgentActivitySnapshot.presentationRun(original)
    }

    public let run: AgentRun?
    public let reasoning: String
    public let reasoningTime: String?
    public let legacyToolContent: String
    public let disclosureExpanded: Bool
    @Binding public var isExpanded: Bool
    public let isActive: Bool
    public let hasAnswerText: Bool
    public let toolApproval: ChatToolApprovalPresentation?
    public let messageState: MessageOpenUIStateStore?
    @State private var expandedActivityIDs: Set<String> = []
    @State private var localDisclosure: HanlinActivityDisclosureState?
    @State private var legacyRunID = UUID()
    @State private var legacyDetailsExpanded = false


    @MainActor
    public init(run: AgentRun?, reasoning: String, reasoningTime: String?,
                legacyToolContent: String, disclosureExpanded: Bool, isExpanded: Binding<Bool>,
                isActive: Bool, hasAnswerText: Bool, toolApproval: ChatToolApprovalPresentation?,
                messageState: MessageOpenUIStateStore? = nil) {
        self.run = run
        self.reasoning = reasoning
        self.reasoningTime = reasoningTime
        self.legacyToolContent = legacyToolContent
        self.disclosureExpanded = disclosureExpanded
        self._isExpanded = isExpanded
        self.isActive = isActive
        self.hasAnswerText = hasAnswerText
        self.toolApproval = toolApproval
        self.messageState = messageState
    }

    @MainActor
    public init(snapshot: HanlinAgentActivitySnapshot, isExpanded: Binding<Bool>,
                toolApproval: ChatToolApprovalPresentation? = nil,
                messageState: MessageOpenUIStateStore? = nil) {
        self.init(run: snapshot.run, reasoning: snapshot.reasoning, reasoningTime: snapshot.reasoningTime,
            legacyToolContent: snapshot.legacyToolContent, disclosureExpanded: isExpanded.wrappedValue,
            isExpanded: isExpanded, isActive: snapshot.isActive, hasAnswerText: snapshot.hasAnswerText,
            toolApproval: toolApproval, messageState: messageState)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.run == rhs.run && lhs.reasoning == rhs.reasoning
            && lhs.reasoningTime == rhs.reasoningTime
            && lhs.legacyToolContent == rhs.legacyToolContent
            && lhs.disclosureExpanded == rhs.disclosureExpanded && lhs.isActive == rhs.isActive
            && lhs.hasAnswerText == rhs.hasAnswerText
            && lhs.toolApproval?.requestID == rhs.toolApproval?.requestID
            && lhs.toolApproval?.callID == rhs.toolApproval?.callID
            && lhs.toolApproval?.toolName == rhs.toolApproval?.toolName
            && lhs.toolApproval?.reviewText == rhs.toolApproval?.reviewText
            && lhs.toolApproval?.remembersDecision == rhs.toolApproval?.remembersDecision
    }

    @MainActor
    private func headerPhase(for activities: [AgentDisplayActivity],
                             approvals: [String: AgentToolApproval]) -> AgentActivityHeaderPhase {
        AgentActivityHeaderPhase.resolve(isRunActive: isActive,
            hasPendingApproval: toolApproval != nil || run?.approvals.contains {
                $0.disposition == .awaiting || $0.disposition == .providerRequired
            } == true,
            hasAnswerText: hasFinalAnswer,
            hasActiveOperation: activities.contains {
                $0.status == .running && $0.kind != .reasoning && $0.kind != .narrative
                    && toolApproval?.callID != $0.id
                    && approvals[$0.id]?.disposition != .awaiting
                    && approvals[$0.id]?.disposition != .providerRequired
            },
            hasActiveReasoning: activities.contains { $0.kind == .reasoning && $0.status == .running },
            hasPendingModelRequest: hasLiveModelRequest)
    }

    @MainActor
    private func headerTitle(for phase: AgentActivityHeaderPhase,
                             activeActivities: [AgentDisplayActivity]) -> String {
        switch phase {
        case .working:
            if hierarchyIsExpanded { return String(localized: "Working…", bundle: HanlinLocalization.bundle) }
            let titles = activeActivities.filter { $0.kind != .reasoning }.map(\.title)
            if !titles.isEmpty { return titles.joined(separator: " · ") }
            if activeActivities.contains(where: { $0.kind == .reasoning }) {
                return String(localized: "Thinking", bundle: HanlinLocalization.bundle)
            }
            return String(localized: "Working…", bundle: HanlinLocalization.bundle)
        case .awaitingApproval:
            return String(localized: "Waiting for your confirmation", bundle: HanlinLocalization.bundle)
        case .history:
            let duration = run.map {
                AgentActivityDurationFormatter.string(
                    max(0, ($0.activityCompletedAt ?? $0.startedAt).timeIntervalSince($0.startedAt)))
            } ?? reasoningTime ?? AgentActivityDurationFormatter.string(0)
            return String(format: String(localized: "Worked for %@", bundle: HanlinLocalization.bundle), duration)
        }
    }

    /// A provider can send commentary before another tool. Its first text delta
    /// is provisional, and must not collapse the activity as though work ended.
    @MainActor
    private var hasFinalAnswer: Bool {
        if let run { return run.finalAnswerStartedAt != nil }
        return hasAnswerText
    }

    @MainActor
    private var hasLiveModelRequest: Bool {
        AgentActivityHeaderPhase.showsModelRequestStatus(isRunActive: isActive,
            requestID: run?.pendingModelRequestID, hasAnswerText: hasFinalAnswer,
            hasPendingApproval: toolApproval != nil || run?.approvals.contains {
                $0.disposition == .awaiting || $0.disposition == .providerRequired
            } == true)
    }

    @MainActor
    private var disclosureRunID: UUID { run?.id ?? messageState?.identity.messageID ?? legacyRunID }

    @MainActor
    private var disclosurePhase: HanlinActivityDisclosureState.Phase {
        !isActive ? .finished : hasFinalAnswer ? .answering : .active
    }

    @MainActor
    private var disclosureLifecycle: HanlinActivityDisclosureState {
        .init(runID: disclosureRunID, phase: disclosurePhase)
    }

    @MainActor
    private var currentDisclosure: HanlinActivityDisclosureState? {
        let value = messageState?.activityDisclosure ?? localDisclosure
        return value?.runID == disclosureRunID ? value : nil
    }

    @MainActor
    private var hierarchyIsExpanded: Bool { currentDisclosure?.isExpanded ?? isExpanded }

    @MainActor
    private func storeDisclosure(_ value: HanlinActivityDisclosureState) {
        if let messageState { messageState.setActivityDisclosure(value) }
        else { localDisclosure = value }
        if isExpanded != value.isExpanded { isExpanded = value.isExpanded }
    }

    @MainActor
    private func synchronizeDisclosure() {
        let previous = messageState?.activityDisclosure ?? localDisclosure
        let next = previous?.reconciled(runID: disclosureRunID, phase: disclosurePhase)
            ?? .init(runID: disclosureRunID, phase: disclosurePhase,
                     isExpanded: disclosurePhase == .active ? true : isExpanded)
        storeDisclosure(next)
    }

    @MainActor
    private func setHierarchyExpanded(_ expanded: Bool) {
        var value = currentDisclosure
            ?? .init(runID: disclosureRunID, phase: disclosurePhase)
        value.isExpanded = expanded
        storeDisclosure(value)
    }

    @MainActor
    private func liveActivities(in activities: [AgentDisplayActivity],
                                  phase: AgentActivityHeaderPhase,
                                  approvals: [String: AgentToolApproval]) -> [AgentDisplayActivity] {
        guard phase == .working else { return [] }
        return activities.filter { activity in
            AgentActivityVisibilityPolicy.animatesActivity(kind: activity.kind.rawValue,
                status: activity.status.rawValue, isRunActive: isActive, hasAnswerText: hasFinalAnswer,
                isAwaitingApproval: toolApproval?.callID == activity.id
                    || approvals[activity.id]?.disposition == .awaiting
                    || approvals[activity.id]?.disposition == .providerRequired)
        }
    }

    @MainActor
    public var body: some View {
        let timeline = run.map(AgentActivityComposer.compose)
        let activities = (timeline?.activities ?? []).filter { activity in
            activity.kind != .reasoning || (isActive && activity.status == .running)
                || run.map { !AgentActivityComposer.reasoningDisplayText(for: activity, in: $0).isEmpty } == true
        }
        let approvals = Dictionary((run?.approvals ?? []).map { ($0.callID, $0) },
            uniquingKeysWith: { _, latest in latest })
        let phase = headerPhase(for: activities, approvals: approvals)
        let activeActivities = liveActivities(in: activities, phase: phase, approvals: approvals)
        let paths = activeActivities.map {
            AgentActivityShimmerOwner.Path(activityID: $0.id, roundID: nil, isRoundExpanded: true)
        }
        let shimmerOwners = AgentActivityShimmerOwner.resolve(isWorking: phase.showsShimmer,
            isHierarchyExpanded: hierarchyIsExpanded, activePaths: paths)
        let legacyReasoning = run == nil
            ? ProgressSummarySanitizer.sanitizeProviderReasoningDisplay(reasoning) ?? "" : ""
        let hasHistory = !activities.isEmpty || !legacyReasoning.isEmpty
            || (run == nil && !legacyToolContent.isEmpty) || toolApproval != nil
        return Group {
            if hasHistory {
                DisclosureGroup(isExpanded: Binding(
                    get: { hierarchyIsExpanded }, set: { setHierarchyExpanded($0) }
                )) {
                    if let run {
                        // Model round IDs stay in the canonical transcript. They
                        // are not user work, so never become empty generic nodes.
                        ForEach(activities) { activity in
                            if activity.kind == .reasoning {
                                reasoningRow(activity, run: run,
                                    isCurrent: shimmerOwners.contains(.activity(activity.id)))
                            } else {
                                activityRow(activity, approval: approvals[activity.id],
                                    isCurrent: shimmerOwners.contains(.activity(activity.id)))
                            }
                        }
                    } else {
                        if !legacyReasoning.isEmpty {
                            ReasoningDisplayText(text: legacyReasoning)
                        }
                        if !legacyToolContent.isEmpty {
                            DisclosureGroup(isExpanded: $legacyDetailsExpanded) {
                                Self.technicalText(ClassicProjectedToolCallEntry.sanitizeUserFacingToolOutput(legacyToolContent))
                            } label: {
                                HanlinActivityHierarchyHeader(title: String(localized: "Tool details", bundle: HanlinLocalization.bundle),
                                    symbol: "wrench.and.screwdriver", depth: 1,
                                    isExpanded: legacyDetailsExpanded, isActive: false)
                            }
                            .disclosureGroupStyle(HanlinActivityDisclosureStyle())
                        }
                    }
                    if let pending = toolApproval,
                       !activities.contains(where: { $0.id == pending.callID }) {
                        approvalView(pending)
                    }
                } label: {
                    HanlinActivityHierarchyHeader(title: headerTitle(for: phase, activeActivities: activeActivities),
                        symbol: "sparkles", isExpanded: hierarchyIsExpanded,
                        isActive: shimmerOwners.contains(.root))
                        .accessibilityIdentifier("hanlin-reasoning-toggle")
                }
                .disclosureGroupStyle(HanlinActivityDisclosureStyle(depth: 0))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("hanlin-agent-activity-toggle")
            } else if hasLiveModelRequest {
                // Request latency is a temporary root status, never a stored or
                // expandable activity node and never evidence of actual thinking.
                HanlinActivityTitle(String(localized: "Working…", bundle: HanlinLocalization.bundle),
                    font: HanlinTypography.footnote, baseColor: .secondary, isActive: false)
                    .accessibilityIdentifier("hanlin-model-request-status")
            }
        }
        .onChange(of: disclosureLifecycle, initial: true) { _, _ in
            synchronizeDisclosure()
        }
    }

    @MainActor
    private func reasoningRow(_ activity: AgentDisplayActivity, run: AgentRun,
                              isCurrent: Bool) -> some View {
        let summary = AgentActivityComposer.reasoningDisplayText(for: activity, in: run)
        return VStack(alignment: .leading, spacing: 5) {
            if isCurrent {
                HanlinToolActivityHeader(
                    title: String(localized: "Thinking", bundle: HanlinLocalization.bundle),
                    status: "", symbol: "sparkles", isActive: true, showsShimmer: true,
                    startedAt: activity.startedAt, completedAt: activity.completedAt)
                    .accessibilityIdentifier("hanlin-reasoning-live-status")
            }
            if !summary.isEmpty {
                ReasoningDisplayText(text: summary)
            }
        }
    }

    /// Read visibility inside the disclosure branch. Keep the text's natural
    /// height for animation while hiding its leaf; tool and consent state stays
    /// mounted in the surrounding hierarchy.
    nonisolated private struct ReasoningDisplayText: View {
        let text: String
        @Environment(\.hanlinActivityBranchVisible) private var branchIsVisible

        @MainActor
        var body: some View {
            if branchIsVisible {
                selectableText
            } else {
                selectableText.hidden()
            }
        }

        @MainActor
        private var selectableText: some View {
            Text(text)
                .font(HanlinTypography.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("hanlin-reasoning-expanded-text")
        }
    }

    @MainActor
    private func activityIsExpanded(_ id: String) -> Bool {
        messageState?.expandedActivityIDs.contains(id) ?? expandedActivityIDs.contains(id)
    }

    @MainActor
    private func activityDisplayTitle(_ activity: AgentDisplayActivity) -> String {
        guard !isActive, activity.status == .running || activity.status == .pending else {
            return activity.title
        }
        // An interrupted historical step may never receive a terminal
        // event. Keep its actual outcome; do not advertise live work or
        // fabricate success from the parent run's completion.
        let sourceIDs = Set(activity.sourceStepIDs)
        let steps = (run?.steps ?? []).filter { sourceIDs.contains($0.id) }
        let profile = steps.compactMap(\.presentationProfile).first
        let name = steps.compactMap(\.subtitle).first ?? ""
        return ToolPresentationRegistry.presentation(for: name, profile: profile).title
    }

    @ViewBuilder
    @MainActor
    private func activityRow(_ activity: AgentDisplayActivity,
                             approval: AgentToolApproval?, isCurrent: Bool) -> some View {
        let pending = toolApproval.flatMap { $0.callID == activity.id ? $0 : nil }
        VStack(alignment: .leading, spacing: 0) {
            if let pending {
                approvalView(pending)
            } else {
                DisclosureGroup(isExpanded: Binding(
                    get: { activityIsExpanded(activity.id) },
                    set: { expanded in
                        if let state = messageState { state.setExpanded(expanded, activityID: activity.id) }
                        else if expanded { expandedActivityIDs.insert(activity.id) }
                        else { expandedActivityIDs.remove(activity.id) }
                    }
                )) {
                    // Projection belongs to mounted details, not to the
                    // target expansion flag. Closing must retain the same
                    // ScrollView subtree until the height reveal finishes.
                    AgentActivityDetailsView(activity: activity, run: run).equatable()
                } label: {
                    HanlinToolActivityHeader(title: activityDisplayTitle(activity),
                        status: statusText(activity, approval: approval),
                        symbol: activity.executionPresentation?.resolvedSystemImage
                            ?? activity.systemImage ?? "wrench.and.screwdriver",
                        family: trustedActivityFamily(activity),
                        isActive: isActive && activity.status == .running
                            && approval?.disposition != .awaiting && approval?.disposition != .providerRequired,
                        showsShimmer: isCurrent,
                        isExpanded: activityIsExpanded(activity.id),
                        isFailure: activity.status == .failed,
                        isCancelled: activity.status == .cancelled,
                        startedAt: activity.startedAt, completedAt: activity.completedAt,
                        sources: Self.sourceReferences(for: activity), icons: activity.icons)
                }
                .disclosureGroupStyle(HanlinActivityDisclosureStyle(isTool: true))
            }
        }
        .accessibilityElement(children: .contain)
        // SwiftUI can expose this wrapper as the approval's sole AX
        // container. Preserve its immutable request owner at that boundary.
        .accessibilityIdentifier(pending.map { "hanlin-tool-approval-\($0.requestID)" }
            ?? "hanlin-agent-activity-\(activity.id)")
    }

    /// A dedicated body keeps projection lazy even when DisclosureGroup
    /// constructs its content value. Expansion is intentionally not an input:
    /// closing a parent retains this exact payload until it unmounts.
    nonisolated private struct AgentActivityDetailsView: View, Equatable {
        let activity: AgentDisplayActivity
        let run: AgentRun?

        @MainActor
        var body: some View {
            let entries = AgentActivityToolProjection.projectToolEntries(from: run, callID: activity.id)
            return VStack(alignment: .leading, spacing: 8) {
                if !activity.queries.isEmpty {
                    Text(activity.queries.joined(separator: "\n"))
                        .font(HanlinTypography.footnote).textSelection(.enabled)
                }
                ForEach(HanlinAgentActivityView.sourceReferences(for: activity)) { source in
                    if let url = source.url {
                        Link(destination: url) { Label(source.title, systemImage: "link") }
                            .font(HanlinTypography.footnote)
                    }
                }
                if let input = activity.inputPreview { HanlinAgentActivityView.technicalText(input) }
                if entries.isEmpty {
                    if let output = activity.outputPreview { HanlinAgentActivityView.technicalText(output) }
                    if let error = activity.errorDescription {
                        Text(AgentDiagnosticsRedactor.sanitize(error))
                            .font(HanlinTypography.caption).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
                ForEach(entries) { HanlinAgentActivityView.toolCallDetails($0) }
            }
        }
    }

    @MainActor
    private func approvalView(_ pending: ChatToolApprovalPresentation) -> some View {
        let summary = AgentToolApprovalSummary.make(toolName: pending.toolName, reviewText: pending.reviewText)
        return HanlinInlineToolApproval(requestID: pending.requestID, toolName: pending.toolName,
            reviewText: pending.reviewText, remembersDecision: pending.remembersDecision,
            displayTitle: summary.title, systemImage: summary.systemImage,
            scopeSummary: summary.scope, requiresDetailedReview: summary.requiresDetailedReview,
            answer: pending.answer)
            .id(pending.requestID)
    }

    @MainActor
    private func statusText(_ activity: AgentDisplayActivity, approval: AgentToolApproval?) -> String {
        if approval?.disposition == .notApproved { return String(localized: "Not approved", bundle: HanlinLocalization.bundle) }
        if approval?.disposition == .awaiting || approval?.disposition == .providerRequired {
            return String(localized: "Awaiting approval", bundle: HanlinLocalization.bundle)
        }
        switch activity.status {
        case .pending: return isActive ? String(localized: "Pending", bundle: HanlinLocalization.bundle) : ""
        case .running: return ""
        case .completed: return ""
        case .failed: return String(localized: "Failed", bundle: HanlinLocalization.bundle)
        case .cancelled: return String(localized: "Cancelled", bundle: HanlinLocalization.bundle)
        }
    }

    @MainActor
    private func trustedActivityFamily(_ activity: AgentDisplayActivity) -> HanlinToolActivityHeader.Family {
        // Explicit family metadata has precedence over its generic motion
        // preset; otherwise map/file/image tools lose their family identity.
        if let family = activity.executionPresentation?.familyID {
            switch family {
            case .webSearch: return .webSearch
            case .sourceSearch: return .sourceSearch
            case .fileOperation: return .fileOperation
            case .codeExecution: return .codeExecution
            case .command: return .command
            case .imageGeneration: return .imageGeneration
            case .map: return .map
            case .calendarSearch: return .calendarSearch
            case .calendarRead: return .calendarRead
            case .calendarCreate: return .calendarCreate
            case .calendarUpdate: return .calendarUpdate
            case .calendarDelete: return .calendarDelete
            case .calendarComplete: return .calendarComplete
            case .calendarAccess: return .calendarAccess
            case .memorySave: return .memorySave
            case .memoryRecall: return .memoryRecall
            case .memoryUpdate: return .memoryUpdate
            default: break
            }
        }
        if activity.kind == .map { return .map }
        if let animation = activity.executionPresentation?.animation {
            switch animation {
            case .search: return .webSearch
            case .execution: return .codeExecution
            case .common: return .generic
            }
        }
        return switch activity.executionPresentation?.familyID {
        case .webSearch?: .webSearch
        case .sourceSearch?: .sourceSearch
        case .fileOperation?: .fileOperation
        case .codeExecution?: .codeExecution
        case .command?: .command
        case .imageGeneration?: .imageGeneration
        case .map?: .map
        case .calendarSearch?: .calendarSearch
        case .calendarRead?: .calendarRead
        case .calendarCreate?: .calendarCreate
        case .calendarUpdate?: .calendarUpdate
        case .calendarDelete?: .calendarDelete
        case .calendarComplete?: .calendarComplete
        case .calendarAccess?: .calendarAccess
        case .memorySave?: .memorySave
        case .memoryRecall?: .memoryRecall
        case .memoryUpdate?: .memoryUpdate
        default: .generic
        }
    }

    @MainActor
    private static func sourceReferences(for activity: AgentDisplayActivity) -> [HanlinSourceReference] {
        activity.sources.compactMap { source in
            guard let rawURL = source.url, let url = URL(string: rawURL),
                  ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                  let host = url.host, host.lowercased() != "search.local" else { return nil }
            var icon = URLComponents()
            // Use the existing resource favicon service; many verified
            // sources have no icon at the historical /favicon.ico path.
            icon.scheme = "https"; icon.host = "www.google.com"; icon.path = "/s2/favicons"
            icon.queryItems = [.init(name: "domain", value: host), .init(name: "sz", value: "64")]
            return HanlinSourceReference(id: source.id, title: source.displayTitle, url: url, iconURL: icon.url)
        }
    }

    @MainActor
    private static func technicalText(_ text: String) -> some View {
        #if canImport(UIKit)
        HanlinToolDetailsText(AgentDiagnosticsRedactor.sanitize(text))
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        #else
        HanlinToolDetailsText(AgentDiagnosticsRedactor.sanitize(text))
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        #endif
    }

    @MainActor
    private static func toolCallDetails(_ entry: ClassicProjectedToolCallEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // The outer row owns title and outcome. Details show the real
            // call's payload once, rather than another nested status card.
            if !entry.output.isEmpty { technicalText(entry.output) }
            if let error = entry.errorDescription, !error.isEmpty, !entry.output.contains(error) {
                Text(AgentDiagnosticsRedactor.sanitize(error))
                    .font(HanlinTypography.caption).foregroundStyle(.red).textSelection(.enabled)
                    .accessibilityIdentifier("hanlin-tool-content-expanded-text")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-tool-call-row-\(entry.callID)")
    }
}
