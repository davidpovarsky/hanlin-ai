import Foundation
import CryptoKit
import JavaScriptCore

public struct HanlinOriginalScriptWidgetFailure: Error, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

/// One real upstream execution session. Its Promise callbacks and JS evaluation
/// share the upstream serial callback lane; the native caller waits outside it.
public final class HanlinOriginalScriptWidgetSession {
    private let runtime: ScriptWidgetRuntime
    private let transaction: HanlinOriginalScriptWidgetTransaction
    private let snapshot: ScriptWidgetExecutionSnapshot
    let installedPackage: ScriptWidgetPackage

    public static func supportScript(_ name: String) -> String? { ScriptManager.readBundleFile(bundle: "support", fileName: name) }

    public static var globalAPIs: [String] { ScriptWidgetRuntimeContract.globalAPIs }
    public static var apiVersion: String { ScriptWidgetBuildContract.nativeRuntimeAPIVersion }
    public static var maximumSourceBytes: Int { ScriptWidgetRuntimeContract.maximumSourceBytes }
    public static var maximumElementNodes: Int { ScriptWidgetRuntimeContract.maximumElementNodes }
    public static var maximumElementDepth: Int { ScriptWidgetRuntimeContract.maximumElementDepth }
    public static var maximumPropsPerElement: Int { ScriptWidgetRuntimeContract.maximumPropsPerElement }
    public static var compileTimeout: TimeInterval { ScriptWidgetRuntimeContract.compileTimeout }

    public static func validateSource(_ source: String) throws {
        if let error = ScriptWidgetRuntimeContract.validateSource(source) {
            throw HanlinOriginalScriptWidgetFailure(error.localizedDescription)
        }
    }

    public static func validatePreparedJavaScript(_ source: String) throws {
        if let error = ScriptWidgetRuntimeContract.validateTranspiled(source) {
            throw HanlinOriginalScriptWidgetFailure(error.localizedDescription)
        }
    }
    public static var executionTimeout: TimeInterval {
        switch ScriptWidgetRuntimeContract.executionTimeout {
        case let .seconds(value): return Double(value)
        case let .milliseconds(value): return Double(value) / 1_000
        case let .microseconds(value): return Double(value) / 1_000_000
        case let .nanoseconds(value): return Double(value) / 1_000_000_000
        case .never: return .infinity
        @unknown default: return 5
        }
    }

    public init(context: JSContext, root: URL, identity: String,
                preparedJavaScript: String, files: [String: Data],
                values: [String: Any], environment: [String: String],
                isUserInitiatedAction: Bool) throws {
        let prepared = try Self.prepare(root: root, identity: identity, javaScript: preparedJavaScript, files: files, values: values)
        self.transaction = prepared.transaction
        self.snapshot = prepared.snapshot
        self.installedPackage = prepared.package
        self.runtime = ScriptWidgetRuntime(package: prepared.snapshot.package,
            environments: environment, executionSnapshot: prepared.snapshot,
            isUserInitiatedAction: isUserInitiatedAction, hostContext: context)
    }

    public func onJavaScriptQueue<T>(_ work: () throws -> T) rethrows -> T {
        try runtime.runningState!.executionSession.callbackQueue.sync(execute: work)
    }

    /// Registers the upstream classes, including real EventKit, HealthKit,
    /// Contacts, HomeKit, Photos, Location, Music, storage and URLSession APIs.
    public func installAPIs() { runtime.installBaseAPIs() }

    public func values() throws -> [String: Any] { try transaction.exportValues() }
    public func value(forKey key: String) throws -> Any? {
        try snapshot.validateIdentity()
        return try transaction.exportValue(forKey: key)
    }
    public func setValue(_ value: Any, forKey key: String) throws {
        try snapshot.validateIdentity()
        try transaction.setExportedValue(value, forKey: key)
    }
    public func finish() { runtime.runningState?.executionSession.finish() }
    public func cancel() { runtime.cancel(.explicit) }

    /// Original storage installation and generation binding. Every supplied
    /// identity comes from the installed Hanlin artifact under its store lock.
    private static func prepare(root: URL, identity: String, javaScript: String,
                                files: [String: Data], values: [String: Any]) throws
        -> (snapshot: ScriptWidgetExecutionSnapshot, package: ScriptWidgetPackage, transaction: HanlinOriginalScriptWidgetTransaction) {
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let library = root.appendingPathComponent("Packages", isDirectory: true)
        try manager.createDirectory(at: library, withIntermediateDirectories: true)
        let originalFiles = try ScriptWidgetStorageFiles(container: root)
        let preferences = UserDefaults(suiteName: HanlinOriginalScriptWidgetEnvironment.preferencesSuite)!
        let metadata = ScriptWidgetFileStorageBackend(files: originalFiles, legacy: preferences, includesLegacy: false)
        let transaction = try HanlinOriginalScriptWidgetTransaction(metadata: metadata, values: values)
        let context = try ScriptWidgetPackageStorageContext(libraryRoot: library, container: root, defaults: transaction)
        _ = try context.recoverInstallation()
        _ = try ScriptWidgetStorageNamespaces.bootstrap(existingNames: [], inventoryIsComplete: true,
                                                        container: root, defaults: transaction)
        let name = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        if !manager.fileExists(atPath: library.appendingPathComponent(name).path) {
            let staged = root.appendingPathComponent("Prepared-" + UUID().uuidString, isDirectory: true)
            try manager.createDirectory(at: staged, withIntermediateDirectories: true)
            defer { try? manager.removeItem(at: staged) }
            for (path, data) in files {
                guard ScriptWidgetPackageFiles.write(data, root: staged, relative: path) else {
                    throw HanlinOriginalScriptWidgetFailure("ScriptWidget resource could not be materialized: \(path)")
                }
            }
            guard ScriptWidgetPackageFiles.write(Data(javaScript.utf8), root: staged, relative: "__hanlin_prepared.js") else {
                throw HanlinOriginalScriptWidgetFailure("ScriptWidget prepared entry could not be saved.")
            }
            var manifest: WidgetPackageManifest
            if files["widget.json"] != nil {
                guard let original = ScriptWidgetPackage(path: staged, readonly: false).readManifest() else {
                    throw HanlinOriginalScriptWidgetFailure("The original widget.json manifest is invalid.")
                }
                manifest = original
            } else {
                manifest = .newProject(name: name)
                manifest.minimumRuntimeVersion = ScriptWidgetBuildContract.nativeRuntimeAPIVersion
                // Existing Hanlin widgets did not have a second permission
                // manifest. The host enables its available original APIs;
                // actual Apple authorization remains owned by each provider.
                manifest.permissions = WidgetPackagePermission.allCases
                manifest.networkDomains = ["*"]
            }
            manifest.entry = "__hanlin_prepared.js"
            guard ScriptWidgetPackageFiles.write(try JSONEncoder().encode(manifest), root: staged, relative: "widget.json") else {
                throw HanlinOriginalScriptWidgetFailure("ScriptWidget native manifest could not be saved.")
            }
            let descriptor = ScriptWidgetPackage(path: staged, readonly: false)
            let report = WidgetPackageManifestValidator.validate(manifest, package: descriptor)
            guard report.isValid else {
                throw HanlinOriginalScriptWidgetFailure(report.errors.map(\.message).joined(separator: "\n"))
            }
            _ = try context.publish(staged, name: name)
        }
        let binding = try context.boundDirectory(name: name, role: .source)
        let package = ScriptWidgetPackage(path: library.appendingPathComponent(name), readonly: false,
            managedScope: .init(context: context, role: .source, binding: binding))
        let snapshot = try ScriptWidgetExecutionSnapshot(name: name, role: .source, context: context)
        transaction.namespace = snapshot.storageNamespace
        // No additional Hanlin approval screen. Upstream selection screens can
        // still select concrete Contacts, Home items and imported documents.
        let access = ScriptWidgetSystemAccessStore(container: root, owner: binding.ownerID,
                                                   validate: { try snapshot.validateIdentity() })
        if ScriptWidgetPackageFiles.kind(root: root, relative: access.path) == nil {
            let empty = try access.load()
            var granted = empty
            granted.permissions = (snapshot.package.readManifest()?.permissions ?? [])
                .map(\.rawValue).filter { ScriptWidgetSystemAccessGrant.capabilities.contains($0) }
            if !granted.permissions.isEmpty { try access.save(granted, expected: empty) }
        }
        return (snapshot, package, transaction)
    }
}

/// Routes only this invocation's $storage namespace through Hanlin's existing
/// atomic widget-state transaction. Upstream private metadata and native service
/// receipts use the original file backend and remain durable between invocations.
private final class HanlinOriginalScriptWidgetTransaction: ScriptWidgetStorageBackend {
    let metadata: any ScriptWidgetStorageBackend
    var namespace: String?
    private var records: [String: Any]

    init(metadata: any ScriptWidgetStorageBackend, values: [String: Any]) throws {
        self.metadata = metadata
        self.records = try values.mapValues { value in
            if let dictionary = value as? [String: Any] {
                return try JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys])
            }
            return value
        }
    }

    private func key(_ key: String) -> String? {
        guard let namespace, key.utf8.starts(with: namespace.utf8) else { return nil }
        return String(decoding: key.utf8.dropFirst(namespace.utf8.count), as: UTF8.self)
    }
    func readValue(forKey key: String) throws -> Any? {
        if let key = self.key(key) { return records[key] }
        return try metadata.readValue(forKey: key)
    }
    func writeValue(_ value: Any, forKey key: String) throws {
        if let key = self.key(key) { records[key] = value; return }
        try metadata.writeValue(value, forKey: key)
    }
    func removeValue(forKey key: String) throws {
        if let key = self.key(key) { records.removeValue(forKey: key); return }
        try metadata.removeValue(forKey: key)
    }
    func legacyValues() throws -> [String: Any] { try metadata.legacyValues() }
    func values(in namespace: String) throws -> [(String, Any)] {
        if namespace == self.namespace { return records.map { (namespace + $0.key, $0.value) } }
        return try metadata.values(in: namespace)
    }
    func mutateValues(in namespace: String, operation: (any ScriptWidgetStorageBackend) throws -> Bool) throws -> Bool {
        guard namespace == self.namespace else { return try metadata.mutateValues(in: namespace, operation: operation) }
        let before = records
        do {
            let committed = try operation(self)
            if !committed { records = before }
            return committed
        } catch { records = before; throw error }
    }
    func synchronize() -> Bool { metadata.synchronize() }
    func exportValue(forKey key: String) throws -> Any? {
        guard let value = records[key] else { return nil }
        if let data = value as? Data { return try JSONSerialization.jsonObject(with: data) }
        return value
    }
    func setExportedValue(_ value: Any, forKey key: String) throws {
        guard !key.isEmpty, key.utf8.count <= ScriptWidgetAtomicPreferences.maximumKeyBytes,
              let namespace else { throw ScriptWidgetStorageNamespaceError.invalidName }
        let bytes = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
        guard bytes.count <= ScriptWidgetAtomicPreferences.maximumValueBytes else {
            throw ScriptWidgetStorageNamespaceError.limitExceeded
        }
        let stored: Any = value is [String: Any] ? bytes : value
        guard try ScriptWidgetStorageNamespaces.fitsBudget(namespace: namespace, defaults: self, replacing: [key: stored]) else {
            throw ScriptWidgetStorageNamespaceError.limitExceeded
        }
        records[key] = stored
    }
    func exportValues() throws -> [String: Any] {
        try records.mapValues { value in
            if let data = value as? Data { return try JSONSerialization.jsonObject(with: data) }
            return value
        }
    }
}
