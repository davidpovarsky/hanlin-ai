import Foundation

enum AgentActivityComposer {
    static func compose(_ run: AgentRun) -> AgentDisplayTimeline {
        let meaningful = run.steps
            .sorted { $0.sequence < $1.sequence }
            .filter { !AgentActivityCompositionPolicy.isInternalTransport($0) }
            .filter { AgentActivityCompositionPolicy.displayKind(for: $0.kind) != nil }

        var groups: [[AgentActivityStep]] = []
        for step in meaningful {
            if let index = matchingGroupIndex(for: step, in: groups) {
                groups[index].append(step)
            } else {
                groups.append([step])
            }
        }

        var activities = groups.compactMap(makeActivity)
        activities = mergeAdjacentSearches(activities)
        activities = removeNarrativeDuplicates(activities)

        let duration = run.completedAt.map { max(0, $0.timeIntervalSince(run.startedAt)) }
        return AgentDisplayTimeline(
            summaryTitle: summaryTitle(for: run, duration: duration),
            activities: activities,
            totalDuration: duration,
            status: run.status
        )
    }

    private static func matchingGroupIndex(for step: AgentActivityStep, in groups: [[AgentActivityStep]]) -> Int? {
        guard step.kind == .toolCall || step.kind == .toolExecution || step.kind == .webSearch else { return nil }
        let key = lifecycleKey(step)
        if let exact = groups.lastIndex(where: { group in group.contains { lifecycleKey($0) == key } }) {
            return exact
        }

        guard let tool = AgentActivityDeduplicator.normalized(step.subtitle),
              let index = groups.lastIndex(where: { group in
                  guard let last = group.last,
                        abs(last.startedAt.timeIntervalSince(step.startedAt)) < 8 else { return false }
                  return AgentActivityDeduplicator.normalized(last.subtitle) == tool
                      && normalizedInput(last) == normalizedInput(step)
              }) else { return nil }
        return index
    }

    private static func lifecycleKey(_ step: AgentActivityStep) -> String {
        guard var id = step.externalID else { return step.id.uuidString }
        id = id.replacingOccurrences(of: "call:", with: "")
        id = id.replacingOccurrences(of: "execution:", with: "")
        id = id.replacingOccurrences(of: ":execution", with: "")
        return id
    }

    private static func normalizedInput(_ step: AgentActivityStep) -> String? {
        AgentActivityDeduplicator.normalized(step.input)
    }

    private static func makeActivity(_ steps: [AgentActivityStep]) -> AgentDisplayActivity? {
        guard let first = steps.first,
              let kind = AgentActivityCompositionPolicy.displayKind(for: first.kind) else { return nil }
        let status = combinedStatus(steps)
        let queries = AgentActivityDeduplicator.uniqueStrings(
            steps.flatMap(\.queryItems) + steps.compactMap { query(from: $0.input) }
        )
        let sources = AgentActivityDeduplicator.uniqueSources(steps.flatMap(\.sourceItems))
        let input = friendlyInput(steps.compactMap(\.input).first(where: { !$0.isEmpty }))
        let output = friendlyOutput(steps.compactMap(\.output).last(where: { !$0.isEmpty }))
        let error = steps.compactMap(\.errorDescription).last
        let title: String
        switch kind {
        case .narrative:
            title = steps.compactMap(\.userFacingSummary).first ?? first.title
        case .reasoning:
            title = first.title
        default:
            title = AgentActivityTitleBuilder.title(for: steps, kind: kind, queries: queries, status: status)
        }
        guard ProgressSummarySanitizer.sanitize(title) != nil || kind != .narrative else { return nil }

        return AgentDisplayActivity(
            id: lifecycleKey(first),
            kind: kind,
            title: title,
            subtitle: nil,
            narrativeText: kind == .narrative ? title : nil,
            status: status,
            startedAt: steps.map(\.startedAt).min(),
            completedAt: steps.compactMap(\.completedAt).max(),
            queries: queries,
            sources: sources,
            inputPreview: input,
            outputPreview: output,
            errorDescription: error,
            isExpandable: AgentActivityDetailPolicy.isExpandable(
                queries: queries, sources: sources, input: input, output: output,
                error: error
            ),
            sourceStepIDs: steps.map(\.id)
        )
    }

    private static func query(from input: String?) -> String? {
        guard let input else { return nil }
        for line in input.components(separatedBy: .newlines) {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2, ["query", "q", "search_query"].contains(parts[0].lowercased()) {
                return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private static func friendlyInput(_ value: String?) -> String? {
        guard let value else { return nil }
        let lines = value.components(separatedBy: .newlines).filter {
            let key = $0.split(separator: ":", maxSplits: 1).first?.lowercased() ?? ""
            return !["query", "q", "search_query"].contains(String(key))
        }
        let result = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func friendlyOutput(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(trimmed.hasPrefix("{") && trimmed.hasSuffix("}")),
              !(trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) else { return nil }
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func combinedStatus(_ steps: [AgentActivityStep]) -> AgentActivityStatus {
        if steps.contains(where: { $0.status == .failed }) { return .failed }
        if steps.contains(where: { $0.status == .running }) { return .running }
        if steps.contains(where: { $0.status == .pending }) { return .pending }
        if steps.allSatisfy({ $0.status == .cancelled }) { return .cancelled }
        return .completed
    }

    private static func mergeAdjacentSearches(_ activities: [AgentDisplayActivity]) -> [AgentDisplayActivity] {
        var result: [AgentDisplayActivity] = []
        for activity in activities {
            guard activity.kind == .search,
                  var previous = result.last,
                  previous.kind == .search,
                  let previousStart = previous.startedAt,
                  let currentStart = activity.startedAt,
                  abs(currentStart.timeIntervalSince(previousStart)) < 20 else {
                result.append(activity)
                continue
            }
            result.removeLast()
            previous.queries = AgentActivityDeduplicator.uniqueStrings(previous.queries + activity.queries)
            previous.sources = AgentActivityDeduplicator.uniqueSources(previous.sources + activity.sources)
            previous.sourceStepIDs += activity.sourceStepIDs
            previous.completedAt = [previous.completedAt, activity.completedAt].compactMap { $0 }.max()
            previous.status = combinedDisplayStatus(previous.status, activity.status)
            previous.title = AgentActivityTitleBuilder.title(for: [], kind: .search, queries: previous.queries, status: previous.status)
            previous.isExpandable = AgentActivityDetailPolicy.isExpandable(
                queries: previous.queries, sources: previous.sources, input: previous.inputPreview,
                output: previous.outputPreview, error: previous.errorDescription
            )
            result.append(previous)
        }
        return result
    }

    private static func combinedDisplayStatus(_ lhs: AgentActivityStatus, _ rhs: AgentActivityStatus) -> AgentActivityStatus {
        if lhs == .failed || rhs == .failed { return .failed }
        if lhs == .running || rhs == .running { return .running }
        return .completed
    }

    private static func removeNarrativeDuplicates(_ activities: [AgentDisplayActivity]) -> [AgentDisplayActivity] {
        var result: [AgentDisplayActivity] = []
        var seenNarratives = Set<String>()
        for (index, activity) in activities.enumerated() {
            if activity.kind == .narrative {
                guard let key = AgentActivityDeduplicator.normalized(activity.narrativeText),
                      !seenNarratives.contains(key) else { continue }
                let nextToolTitle = activities.dropFirst(index + 1).first(where: { $0.kind != .narrative })?.title
                if key == AgentActivityDeduplicator.normalized(nextToolTitle) { continue }
                seenNarratives.insert(key)
            }
            result.append(activity)
        }
        return result
    }

    private static func summaryTitle(for run: AgentRun, duration: TimeInterval?) -> String {
        switch run.status {
        case .pending, .running: return String(localized: "Working…")
        case .completed:
            return String(format: String(localized: "Worked for %@"), AgentActivityDurationFormatter.string(duration ?? run.elapsedTime))
        case .failed:
            return String(format: String(localized: "Stopped after %@"), AgentActivityDurationFormatter.string(duration ?? run.elapsedTime))
        case .cancelled:
            return String(format: String(localized: "Cancelled after %@"), AgentActivityDurationFormatter.string(duration ?? run.elapsedTime))
        }
    }
}
