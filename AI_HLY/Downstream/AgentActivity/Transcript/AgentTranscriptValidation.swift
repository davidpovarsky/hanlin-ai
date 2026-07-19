import Foundation

enum AgentTranscriptValidation {
    static func normalized(
        _ items: [AgentTranscriptItem],
        promotingFinalAnswerForCompletedRun: Bool = false
    ) -> [AgentTranscriptItem] {
        var seenIDs = Set<UUID>()
        var seenSequences = Set<Int>()
        var normalizedItems = items
            .sorted { lhs, rhs in
                lhs.sequence == rhs.sequence
                    ? lhs.startedAt < rhs.startedAt
                    : lhs.sequence < rhs.sequence
            }
            .filter { item in
                guard item.sequence >= 0,
                      seenIDs.insert(item.id).inserted,
                      seenSequences.insert(item.sequence).inserted else {
                    return false
                }
                if item.kind == .userVisibleToolResult {
                    return !item.nativeUIBlocks.isEmpty
                }
                return true
            }
        if promotingFinalAnswerForCompletedRun,
           let selected = finalAnswerIndexForCompletedRun(in: normalizedItems) {
            for index in normalizedItems.indices where normalizedItems[index].kind == .assistantText {
                guard nonemptyText(normalizedItems[index].text) != nil else { continue }
                normalizedItems[index].textRole = index == selected ? .final : .interim
                normalizedItems[index].visibilityAfterCompletion = index == selected
                    ? .remainInChat
                    : .collapseIntoThinking
            }
        }
        return normalizedItems
    }

    static func finalAnswerIndexForCompletedRun(in items: [AgentTranscriptItem]) -> Int? {
        let candidates = items.indices.filter {
            items[$0].kind == .assistantText && nonemptyText(items[$0].text) != nil
        }
        return candidates.last(where: { items[$0].textRole == .final }) ?? candidates.last
    }

    static func finalAnswer(in items: [AgentTranscriptItem]) -> String? {
        items
            .filter { $0.kind == .assistantText && $0.textRole == .final }
            .sorted { $0.sequence < $1.sequence }
            .compactMap { nonemptyText($0.text) }
            .last
    }

    static func nonemptyText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    static func satisfiesCompletedRunInvariant(_ run: AgentRun) -> Bool {
        guard run.status == .completed else { return true }
        let assistantItems = run.transcriptItems.filter {
            $0.kind == .assistantText && nonemptyText($0.text) != nil
        }
        let finals = assistantItems.filter { $0.textRole == .final }
        guard finals.count == (assistantItems.isEmpty ? 0 : 1),
              finals.allSatisfy({ $0.visibilityAfterCompletion == .remainInChat }),
              assistantItems.filter({ $0.textRole != .final }).allSatisfy({
                  $0.visibilityAfterCompletion == .collapseIntoThinking
              }) else { return false }
        return run.finalAnswer == finals.first.flatMap { nonemptyText($0.text) }
    }

    static func hasStrictlyIncreasingSequence(_ items: [AgentTranscriptItem]) -> Bool {
        let sequences = items.sorted { $0.sequence < $1.sequence }.map(\.sequence)
        return zip(sequences, sequences.dropFirst()).allSatisfy { lhs, rhs in
            lhs < rhs
        }
    }

    static func containsDuplicateNativeUIResults(_ items: [AgentTranscriptItem]) -> Bool {
        var keys = Set<String>()
        for item in items where item.kind == .userVisibleToolResult {
            let key = "\(item.callID ?? ""):\(item.nativeUIBlocks.map(\.id).joined(separator: ","))"
            if !keys.insert(key).inserted { return true }
        }
        return false
    }
}
