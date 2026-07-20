import Foundation

struct MCPEnvironmentDraft: Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var value: String
    var isSecret: Bool
}
