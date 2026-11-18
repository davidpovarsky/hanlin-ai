import Foundation

/// One process-wide critical section for the canonical package and MiniApp
/// stores. A checkpoint can span both stores without suspending between files.
/// Native engine sessions must also be quiescent before their host checkpoints.
public enum HanlinStoreFileAccess {
    private static let lock = NSRecursiveLock()

    public static func withExclusiveAccess<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}
