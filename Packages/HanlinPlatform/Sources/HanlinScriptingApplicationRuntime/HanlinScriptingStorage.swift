import CryptoKit
import Foundation
import HanlinMiniAppCore
import HanlinPlatformContracts

final class HanlinScriptingPackageStorage: @unchecked Sendable {
    private let lock = NSLock()
    private let root: URL
    private let privateStore: HanlinMiniAppKeyValueStore?
    private var sharedStore: HanlinMiniAppKeyValueStore?

    init(installedPackageID: HanlinInstalledPackageID, canonicalAppID: HanlinAppID?,
         allowed: Bool, runtimeRoot: URL?) throws {
        let resolvedRoot = try runtimeRoot.map { $0.appending(path: "MiniApps", directoryHint: .isDirectory) }
            ?? HanlinMiniAppDataStore.applicationSupportRoot()
        root = resolvedRoot
        guard allowed else { privateStore = nil; return }
        let digest = SHA256.hash(data: Data(installedPackageID.rawValue.utf8)).map { String(format: "%02x", $0) }.joined()
        let appID = try canonicalAppID ?? HanlinAppID(validating: "scripting.\(digest)")
        let store = try HanlinMiniAppKeyValueStore(root: resolvedRoot, appID: appID)
        let legacySuite = "com.hanlin.scripting.storage.\(installedPackageID.rawValue)"
        guard let defaults = UserDefaults(suiteName: legacySuite) else {
            throw HanlinScriptingNativeError(name: "Error", code: "storage_initialization_failed", message: "Legacy storage could not be opened; existing data was preserved.")
        }
        try store.migrateLegacy(defaults.persistentDomain(forName: legacySuite) ?? [:], identity: legacySuite)
        privateStore = store
    }

    func perform(operation: String, payload: [String: Any]) throws -> Any {
        lock.lock(); defer { lock.unlock() }
        guard let privateStore else {
            throw HanlinScriptingNativeError(name: "Error", code: "storage_not_allowed", message: "HANLIN_PERMISSION:storage")
        }
        let store: HanlinMiniAppKeyValueStore
        if payload["shared"] as? Bool == true {
            if sharedStore == nil { sharedStore = try HanlinMiniAppKeyValueStore(root: root, appID: nil) }
            store = sharedStore!
        } else { store = privateStore }
        if operation == "clear" { try store.clear(); return NSNull() }
        if operation == "keys" { return try store.keys() }
        guard let key = payload["key"] as? String, !key.isEmpty, !key.contains("\0") else {
            throw HanlinScriptingNativeError(name: "TypeError", code: "invalid_storage_key", message: "Storage requires a nonempty key without NUL bytes.")
        }
        switch operation {
        case "get", "getData":
            let kind: HanlinMiniAppKeyValueStore.Value.Kind = operation == "get" ? .json : .data
            guard let value = try store.value(for: key), value.kind == kind else { return ["found": false] }
            return ["found": true, (operation == "get" ? "json" : "base64"): value.content] as [String: Any]
        case "set":
            guard let json = payload["json"] as? String, let data = json.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil else {
                throw HanlinScriptingNativeError(name: "TypeError", code: "invalid_storage_value", message: "The storage value must be valid JSON.")
            }
            try store.set(.init(kind: .json, content: json), for: key)
            return true
        case "setData":
            guard let base64 = payload["base64"] as? String, Data(base64Encoded: base64) != nil else {
                throw HanlinScriptingNativeError(name: "TypeError", code: "invalid_storage_value", message: "The storage value must contain valid base64 data.")
            }
            try store.set(.init(kind: .data, content: base64), for: key)
            return NSNull()
        case "remove": try store.remove(key: key); return NSNull()
        case "contains": return try store.contains(key: key)
        default: throw HanlinScriptingNativeError(name: "TypeError", code: "invalid_storage_operation", message: "Unknown storage operation: \(operation)")
        }
    }
}
