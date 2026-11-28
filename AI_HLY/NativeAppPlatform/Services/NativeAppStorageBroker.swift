import Foundation

@MainActor
struct NativeAppStorageBroker {
    let appID: String?
    private let defaults: UserDefaults

    init(appID: String?, defaults: UserDefaults = .standard) {
        self.appID = appID
        self.defaults = defaults
    }

    func persistentString(forKey key: String) -> String? { defaults.string(forKey: scoped(key, area: "persistent")) }
    func setPersistentString(_ value: String?, forKey key: String) { defaults.set(value, forKey: scoped(key, area: "persistent")) }
    func persistentData(forKey key: String) -> Data? { defaults.data(forKey: scoped(key, area: "persistent")) }
    func setPersistentData(_ value: Data?, forKey key: String) { defaults.set(value, forKey: scoped(key, area: "persistent")) }
    func persistentStringArray(forKey key: String) -> [String] { defaults.stringArray(forKey: scoped(key, area: "persistent")) ?? [] }
    func setPersistentStringArray(_ value: [String], forKey key: String) { defaults.set(value, forKey: scoped(key, area: "persistent")) }
    func removePersistentValue(forKey key: String) { defaults.removeObject(forKey: scoped(key, area: "persistent")) }
    func clearPersistentAppData() { clear(area: "persistent") }
    func cacheData(forKey key: String) -> Data? { defaults.data(forKey: scoped(key, area: "cache")) }
    func setCacheData(_ value: Data?, forKey key: String) { defaults.set(value, forKey: scoped(key, area: "cache")) }
    func clearCache() { clear(area: "cache") }

    private var scope: String {
        guard let appID, !appID.isEmpty else { return "global" }
        return appID
    }
    private func scoped(_ key: String, area: String) -> String { "nativeapp.\(scope).\(area).\(key)" }
    private func clear(area: String) {
        let prefix = "nativeapp.\(scope).\(area)."
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
