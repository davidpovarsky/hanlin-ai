import Foundation

enum AgentActivityDetailPolicy {
    static func isExpandable(
        queries: [String],
        sources: [AgentActivitySource],
        input: String?,
        output: String?,
        error: String?,
        richBlocks: [NativeUIBlock]
    ) -> Bool {
        queries.count > 1
            || !sources.isEmpty
            || useful(input)
            || useful(output)
            || useful(error)
            || !richBlocks.isEmpty
    }

    private static func useful(_ value: String?) -> Bool {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !value.isEmpty && value != "{}" && value != "[]"
    }
}
