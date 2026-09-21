import Foundation

final class RuntimeAvailabilityStore: @unchecked Sendable {
    static let shared = RuntimeAvailabilityStore()
    
    private let defaults: UserDefaults
    private let keyPrefix = "hanlin.runtime-availability."
    
    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    private func key(for kind: RuntimeKind) -> String {
        return "\(keyPrefix)\(String(describing: kind))"
    }
    
    func isAvailable(_ kind: RuntimeKind) -> Bool {
        let k = key(for: kind)
        if defaults.object(forKey: k) == nil {
            return true // ALL runtimes available by default
        }
        return defaults.bool(forKey: k)
    }
    
    func setAvailable(_ available: Bool, for kind: RuntimeKind) {
        defaults.set(available, forKey: key(for: kind))
    }
    
    // TypeScript depends on Node - report dependency
    func dependencyWarning(for kind: RuntimeKind) -> String? {
        if kind == .typeScript && !isAvailable(.node) {
            return "TypeScript execution requires Node.js, which is currently disabled. Please enable the Node runtime."
        }
        return nil
    }
}
