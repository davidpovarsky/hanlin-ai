import Foundation

final class RuntimeAvailabilityStore: @unchecked Sendable {
    static let shared = RuntimeAvailabilityStore()
    
    private let lock = NSLock()
    private var activeRuntimes: Set<RuntimeKind> = []
    
    private init() {
        // Fresh app process: all runtimes visually OFF/stopped.
        // Process lifecycle is never persisted across launches via UserDefaults.
        activeRuntimes = []
    }
    
    func isAvailable(_ kind: RuntimeKind) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeRuntimes.contains(kind)
    }
    
    func setAvailable(_ available: Bool, for kind: RuntimeKind) {
        lock.lock()
        if available {
            activeRuntimes.insert(kind)
        } else {
            activeRuntimes.remove(kind)
        }
        lock.unlock()
    }
    
    func reset() {
        lock.lock()
        activeRuntimes.removeAll()
        lock.unlock()
    }
    
    // TypeScript depends on Node - report dependency
    func dependencyWarning(for kind: RuntimeKind) -> String? {
        if kind == .typeScript && !isAvailable(.node) {
            return "TypeScript execution requires Node.js, which is currently stopped. Starting TypeScript will activate Node."
        }
        return nil
    }
}
