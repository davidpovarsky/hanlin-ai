import Foundation

public protocol HanlinExpoHostServicesProvider: AnyObject, Sendable {
    func executeRuntime(kind: String, source: String) async throws -> String
    func executeNode(source: String) async throws -> String
    func executePython(source: String) async throws -> String
    func readFile(path: String, area: String) async throws -> String
    func writeFile(path: String, content: String, area: String) async throws
    func executeSQLite(sql: String, params: [String]?) async throws -> String
    func fetchURL(urlString: String) async throws -> String
}

public final class HanlinExpoHostServicesBridge: @unchecked Sendable {
    private struct AppContextBinding {
        let sessionID: String
        let provider: HanlinExpoHostServicesProvider
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _currentProvider: HanlinExpoHostServicesProvider?
    nonisolated(unsafe) private static var _sessionProviders: [String: HanlinExpoHostServicesProvider] = [:]
    nonisolated(unsafe) private static var _appContextProviders: [ObjectIdentifier: AppContextBinding] = [:]

    /// Legacy single-session fallback. Modern modules resolve by AppContext.
    public static var currentProvider: HanlinExpoHostServicesProvider? {
        lock.withLock { _currentProvider }
    }

    public static func register(provider: HanlinExpoHostServicesProvider?, forSessionID sessionID: String? = nil) {
        lock.withLock {
            if let sessionID {
                if let provider {
                    _sessionProviders[sessionID] = provider
                } else {
                    _sessionProviders.removeValue(forKey: sessionID)
                    _appContextProviders = _appContextProviders.filter { $0.value.sessionID != sessionID }
                }
            } else {
                _currentProvider = provider
            }
        }
    }

    /// Binds the host-issued session to the concrete Expo AppContext. The JS
    /// module never accepts a session or app identifier from its caller.
    @discardableResult
    public static func bind(sessionID: String, toAppContext appContext: AnyObject) -> Bool {
        lock.withLock {
            guard let provider = _sessionProviders[sessionID] else { return false }
            _appContextProviders[ObjectIdentifier(appContext)] = AppContextBinding(
                sessionID: sessionID,
                provider: provider
            )
            return true
        }
    }

    public static func provider(forSessionID sessionID: String) -> HanlinExpoHostServicesProvider? {
        lock.withLock { _sessionProviders[sessionID] }
    }

    public static func provider(forAppContext appContext: AnyObject) -> HanlinExpoHostServicesProvider? {
        lock.withLock { _appContextProviders[ObjectIdentifier(appContext)]?.provider }
    }

    public static func unbind(appContext: AnyObject) {
        lock.withLock {
            _appContextProviders.removeValue(forKey: ObjectIdentifier(appContext))
        }
    }

    public static func unregister(sessionID: String) {
        lock.withLock {
            _sessionProviders.removeValue(forKey: sessionID)
            _appContextProviders = _appContextProviders.filter { $0.value.sessionID != sessionID }
        }
    }
}
