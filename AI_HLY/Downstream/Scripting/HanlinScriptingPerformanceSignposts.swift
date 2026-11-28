import Foundation
import os

/// Production-safe signposter for measuring critical downstream Scripting runtime paths.
/// Uses OS signposts with zero overhead when no tracer is active and logs no user data or secrets.
enum HanlinScriptingPerformanceSignposts {
    static let subsystem = "com.davidpovarsky.AI-HLY"
    static let category = "HanlinScriptingPerformance"

    static let signposter = OSSignposter(
        subsystem: subsystem,
        category: category
    )

    @discardableResult
    static func withInterval<T>(
        _ name: StaticString,
        block: () throws -> T
    ) rethrows -> T {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: signpostID)
        defer { signposter.endInterval(name, state) }
        return try block()
    }

    @discardableResult
    static func withIntervalAsync<T>(
        _ name: StaticString,
        block: () async throws -> T
    ) async rethrows -> T {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: signpostID)
        defer { signposter.endInterval(name, state) }
        return try await block()
    }
}
