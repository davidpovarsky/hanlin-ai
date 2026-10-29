import Foundation

final class RuntimeAvailabilityStore: @unchecked Sendable {
    static let shared = RuntimeAvailabilityStore()
    
    public static let didChangeNotification = Notification.Name("HanlinRuntimeAvailabilityDidChange")
    
    private let lock = NSLock()
    private var activeRuntimes: Set<RuntimeKind> = []
    
    private init() {
        // Legacy process-local observation only. This is not a user permission
        // gate, and execution must initialize an authorized runtime on demand.
        activeRuntimes = []
    }
    
    func isAvailable(_ kind: RuntimeKind) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeRuntimes.contains(kind)
    }

    func activeRuntimeKinds() -> Set<RuntimeKind> {
        lock.lock()
        defer { lock.unlock() }
        return activeRuntimes
    }
    
    func setAvailable(_ available: Bool, for kind: RuntimeKind) {
        lock.lock()
        let changed: Bool
        if available {
            changed = activeRuntimes.insert(kind).inserted
        } else {
            changed = activeRuntimes.remove(kind) != nil
        }
        lock.unlock()

        if changed {
            NotificationCenter.default.post(
                name: Self.didChangeNotification,
                object: self,
                userInfo: ["kind": kind.rawValue, "available": available]
            )
        }
    }
    
    func reset() {
        lock.lock()
        let wasEmpty = activeRuntimes.isEmpty
        activeRuntimes.removeAll()
        lock.unlock()

        if !wasEmpty {
            NotificationCenter.default.post(
                name: Self.didChangeNotification,
                object: self
            )
        }
    }
    
    // TypeScript depends on Node - report dependency
    func dependencyWarning(for kind: RuntimeKind) -> String? {
        if kind == .typeScript && !isAvailable(.node) {
            return "TypeScript execution requires Node.js, which is currently disabled. Please enable the Node runtime."
        }
        return nil
    }

    // Availability flags remain for legacy observers; runtime authorization
    // is handled separately by HanlinHostCapabilityAuthority.
}
