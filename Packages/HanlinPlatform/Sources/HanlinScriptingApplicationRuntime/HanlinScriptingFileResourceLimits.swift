import Foundation

/// Explicit host budgets, separate from path access and security scope.
/// Nil preserves complete files, subject to actual memory/disk/OS failures.
struct HanlinScriptingFileResourceLimits: Sendable {
    let maximumReadBytes: Int?
    let maximumStorageBytes: Int?

    init(maximumReadBytes: Int? = nil, maximumStorageBytes: Int? = nil) {
        self.maximumReadBytes = maximumReadBytes
        self.maximumStorageBytes = maximumStorageBytes
    }

    func validate() throws {
        guard (maximumReadBytes ?? 0) >= 0, (maximumStorageBytes ?? 0) >= 0 else {
            throw HanlinScriptingNativeError(name: "TypeError", code: "invalid_resource_budget", message: "Explicit file budgets must be nonnegative.")
        }
    }

    func validateRead(_ bytes: Int) throws {
        if let maximumReadBytes, bytes > maximumReadBytes {
            throw HanlinScriptingNativeError(name: "Error", code: "quota_exceeded", message: "File bytes exceed the explicit resource budget.")
        }
    }
}
