import Foundation

public protocol HanlinExpoHostServicesProvider: AnyObject, Sendable {
    func executeRuntime(kind: String, source: String) async throws -> String
    func executeNode(source: String) async throws -> String
    func executePython(source: String) async throws -> String
    func readFile(path: String, area: String) async throws -> String
    func writeFile(path: String, content: String, area: String) async throws
    func executeSQLite(sql: String, params: [Any]?) async throws -> [[String: Any]]
    func fetchURL(urlString: String) async throws -> String
}

public final class HanlinExpoHostServicesBridge: @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _currentProvider: HanlinExpoHostServicesProvider?
    nonisolated(unsafe) private static var _sessionProviders: [String: HanlinExpoHostServicesProvider] = [:]

    public static var currentProvider: HanlinExpoHostServicesProvider? {
        lock.lock()
        defer { lock.unlock() }
        return _currentProvider
    }

    public static func register(provider: HanlinExpoHostServicesProvider?, forSessionID sessionID: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if let sessionID {
            if let provider {
                _sessionProviders[sessionID] = provider
                _currentProvider = provider
            } else {
                _sessionProviders.removeValue(forKey: sessionID)
                if _currentProvider === provider {
                    _currentProvider = nil
                }
            }
        } else {
            _currentProvider = provider
        }
    }

    public static func provider(forSessionID sessionID: String) -> HanlinExpoHostServicesProvider? {
        lock.lock()
        defer { lock.unlock() }
        return _sessionProviders[sessionID] ?? _currentProvider
    }

    public static func unregister(sessionID: String) {
        lock.lock()
        defer { lock.unlock() }
        _sessionProviders.removeValue(forKey: sessionID)
        if _sessionProviders.isEmpty {
            _currentProvider = nil
        }
    }
}
