import Foundation

/// Actual work reported by the saved action, scoped to its Shortcuts invocation.
/// Elapsed time is never converted into a fabricated completion percentage.
public struct HanlinShortcutProgress: Codable, Equatable, Sendable {
    public let completedUnitCount: Int64
    public let totalUnitCount: Int64
    public let message: String?

    public init(completedUnitCount: Int64, totalUnitCount: Int64, message: String? = nil) {
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
        self.message = message
    }

    public func validate() throws {
        guard totalUnitCount > 0, completedUnitCount >= 0,
              completedUnitCount <= totalUnitCount else { throw ValidationError.invalidCounts }
    }

    public enum ValidationError: Error, Equatable, Sendable {
        case invalidCounts
    }
}
