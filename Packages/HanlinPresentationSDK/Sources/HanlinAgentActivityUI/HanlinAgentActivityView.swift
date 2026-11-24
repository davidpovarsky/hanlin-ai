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
    @State private var collapsedRoundIDs: Set<String> = []
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
            hasAnswerText: hasAnswerText,
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
            return hierarchyIsExpanded ? String(localized: "Thinking & tools", bundle: HanlinLocalization.bundle)
                : (activeActivities.map(\.title) + (hasLiveModelRequest
                    ? [String(localized: "Waiting for model response", bundle: HanlinLocalization.bundle)] : [])).joined(separator: " · ")
        case .awaitingApproval: return String(localized: "Waiting for your confirmation", bundle: HanlinLocalization.bundle)
        case .history: return String(localized: "Activity history", bundle: HanlinLocalization.bundle)
        }
    }

    @MainActor
    private var hasLiveModelRequest: Bool {
        AgentActivityHeaderPhase.showsModelRequestStatus(isRunActive: isActive,
            requestID: run?.pendingModelRequestID, hasAnswerText: hasAnswerText,
            hasPendingApproval: toolApproval != nil || run?.approvals.contains {
                $0.disposition == .awaiting || $0.disposition == .providerRequired
            } == true)
    }

    @MainActor
    private var modelRequestActivityID: String { "model-request:" + (run?.pendingModelRequestID ?? "") }
    @MainActor
    private var hierarchyIsExpanded: Bool { isExpanded || toolApproval != nil }

    @MainActor
    private func roundHasHeader(_ round: AgentDisplayRound) -> Bool {
        round.hasHierarchyHeader
    }

    @MainActor
    private func roundIsWaiting(_ round: AgentDisplayRound,
                                approvals: [String: AgentToolApproval]) -> Bool {
        round.activities.contains { activity in
            toolApproval?.callID == activity.id
                || approvals[activity.id]?.disposition == .awaiting
                || approvals[activity.id]?.disposition == .providerRequired
        }
    }

    @MainActor
    private func liveActivities(in activities: [AgentDisplayActivity],
                                  phase: AgentActivityHeaderPhase,
                                  approvals: [String: AgentToolApproval]) -> [AgentDisplayActivity] {
        guard phase == .working else { return [] }
        return activities.filter { activity in
            AgentActivityVisibilityPolicy.animatesActivity(kind: activity.kind.rawValue,
                status: activity.status.rawValue, isRunActive: isActive, hasAnswerText: hasAnswerText,
                isAwaitingApproval: toolApproval?.callID == activity.id
                    || approvals[activity.id]?.disposition == .awaiting
                    || approvals[activity.id]?.disposition == .providerRequired)
        }
    }

    @MainActor
    private func shimmerPaths(rounds: [AgentDisplayRound], activeIDs: Set<String>,
                              approvals: [String: AgentToolApproval]) -> [AgentActivityShimmerOwner.Path] {
        var paths = rounds.flatMap { round in
            round.activities.filter { activeIDs.contains($0.id) }.map { activity in
                AgentActivityShimmerOwner.Path(activityID: activity.id,
                    roundID: roundHasHeader(round) ? round.id : nil,
                    isRoundExpanded: !collapsedRoundIDs.contains(round.id)
                        || roundIsWaiting(round, approvals: approvals))
            }
        }
        if hasLiveModelRequest {
            paths.append(.init(activityID: modelRequestActivityID, roundID: nil, isRoundExpanded: true))
        }
        return paths
    }

    @MainActor
    public var body: some View {
        let timeline = run.map(AgentActivityComposer.compose)
        let activities = timeline?.activities ?? []
        let approvals = Dictionary((run?.approvals ?? []).map { ($0.callID, $0) },
            uniquingKeysWith: { _, latest in latest })
        let phase = headerPhase(for: activities, approvals: approvals)
        let activeActivities = liveActivities(in: activities, phase: phase, approvals: approvals)
        let activeIDs = Set(activeActivities.map(\.id))
        let rounds = run.flatMap { run in timeline.map { AgentActivityComposer.rounds(for: run, timeline: $0) } } ?? []
        let paths = shimmerPaths(rounds: rounds, activeIDs: activeIDs, approvals: approvals)
        let shimmerOwners = AgentActivityShimmerOwner.resolve(isWorking: phase.showsShimmer,
            isHierarchyExpanded: hierarchyIsExpanded, activePaths: paths)
        if timeline?.activities.isEmpty == false
            || (run == nil && !legacyToolContent.isEmpty) || toolApproval != nil || hasLiveModelRequest {
            DisclosureGroup(isExpanded: Binding(
                get: { hierarchyIsExpanded }, set: { isExpanded = $0 }
            )) {
                if let timeline, let run, !timeline.activities.isEmpty {
                    ForEach(rounds) { round in
                        roundView(round, run: run, approvals: approvals, shimmerOwners: shimmerOwners)
                    }
                } else {
                    if run == nil && !legacyToolContent.isEmpty {
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
                if hasLiveModelRequest {
                    HanlinActivityTitle(String(localized: "Waiting for model response", bundle: HanlinLocalization.bundle),
                        font: HanlinTypography.footnote, baseColor: .secondary,
                        isActive: shimmerOwners.contains(.activity(modelRequestActivityID)))
                        .padding(.vertical, 4)
                        .accessibilityIdentifier("hanlin-model-request-status")
                }
                if let pending = toolApproval,
                   timeline?.activities.contains(where: { $0.id == pending.callID }) != true {
                    // Early delivery keeps the request attached to its real
                    // call, without guessing ownership or granting consent.
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
        }
    }

    @ViewBuilder
    @MainActor
    private func roundView(_ round: AgentDisplayRound, run: AgentRun,
                           approvals: [String: AgentToolApproval],
                           shimmerOwners: Set<AgentActivityShimmerOwner>) -> some View {
        // Nest only genuinely attributed rounds. Legacy siblings are never
        // assigned a parent because their rows happen to be adjacent.
        if roundHasHeader(round) {
            let waiting = roundIsWaiting(round, approvals: approvals)
            let expanded = !collapsedRoundIDs.contains(round.id) || waiting
            let activeTitles = round.activities.filter {
                AgentActivityVisibilityPolicy.animatesActivity(kind: $0.kind.rawValue,
                    status: $0.status.rawValue, isRunActive: isActive, hasAnswerText: hasAnswerText,
                    isAwaitingApproval: toolApproval?.callID == $0.id
                        || approvals[$0.id]?.disposition == .awaiting
                        || approvals[$0.id]?.disposition == .providerRequired)
            }.map(\.title)
            DisclosureGroup(isExpanded: Binding(
                get: { !collapsedRoundIDs.contains(round.id) || waiting },
                set: { if $0 { collapsedRoundIDs.remove(round.id) }
                    else { collapsedRoundIDs.insert(round.id) } }
            )) {
                roundRows(round, run: run, approvals: approvals, shimmerOwners: shimmerOwners)
            } label: {
                HanlinActivityHierarchyHeader(title: !expanded && !activeTitles.isEmpty
                    ? activeTitles.joined(separator: " · ")
                    : (waiting ? String(localized: "Actions requiring your approval", bundle: HanlinLocalization.bundle) : String(localized: "Thinking & tools", bundle: HanlinLocalization.bundle)),
                    symbol: "gearshape.2", depth: 1, isExpanded: expanded,
                    isActive: shimmerOwners.contains(.round(round.id)))
            }
            .disclosureGroupStyle(HanlinActivityDisclosureStyle())
        } else {
            roundRows(round, run: run, approvals: approvals, shimmerOwners: shimmerOwners)
        }
    }

    @MainActor
    private func roundRows(_ round: AgentDisplayRound, run: AgentRun,
                           approvals: [String: AgentToolApproval],
                           shimmerOwners: Set<AgentActivityShimmerOwner>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(round.activities) { activity in
                if activity.kind == .reasoning {
                    reasoningRow(activity, run: run,
                        isCurrent: shimmerOwners.contains(.activity(activity.id)))
                } else {
                    activityRow(activity, approval: approvals[activity.id],
                        isCurrent: shimmerOwners.contains(.activity(activity.id)))
                }
            }
        }
    }

    @MainActor
    private func reasoningRow(_ activity: AgentDisplayActivity, run: AgentRun,
                              isCurrent: Bool) -> some View {
        let summary = AgentActivityComposer.reasoningDisplayText(for: activity, in: run)
        let isPlaceholder = summary == String(localized: "Thinking", bundle: HanlinLocalization.bundle)
        let title = !isCurrent && isPlaceholder ? String(localized: "Reasoning", bundle: HanlinLocalization.bundle) : summary
        let duration: String = {
            guard !isCurrent, let startedAt = activity.startedAt, let completedAt = activity.completedAt,
                  completedAt.timeIntervalSince(startedAt) >= 1 else { return "" }
            return AgentActivityDurationFormatter.string(completedAt.timeIntervalSince(startedAt))
        }()
        return HanlinToolActivityHeader(title: title, status: duration, symbol: "sparkles",
            isActive: isCurrent, showsShimmer: isCurrent,
            startedAt: activity.startedAt, completedAt: activity.completedAt)
            .accessibilityIdentifier("hanlin-reasoning-expanded-text")
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
