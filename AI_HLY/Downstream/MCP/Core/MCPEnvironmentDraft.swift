import Foundation

public struct MCPEnvironmentDraft: Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var name: String
    public var value: String
    public var isSecret: Bool
    public init(id: UUID = UUID(), name: String, value: String, isSecret: Bool = false) {
        self.id = id
        self.name = name
        self.value = value
        self.isSecret = isSecret
    }
}
