import Foundation
import HanlinNativeScriptCoreSupport
import UIKit

@MainActor
public final class HanlinNativeScriptSession {
    private static let supportedRuntimeVersion = "9.1.0"
    private static let supportedSwiftUIVersion = "4.0.2"
    private static weak var activeSession: HanlinNativeScriptSession?

    public static var sharedRuntimeURL: URL? {
        if let envPath = ProcessInfo.processInfo.environment["HANLIN_NATIVESCRIPT_SHARED_RUNTIME_PATH"] {
            let envURL = URL(fileURLWithPath: envPath)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: envURL.path, isDirectory: &isDir), isDir.boolValue {
                return envURL
            }
        }
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "NativeScriptSharedRuntime", withExtension: nil) {
            return url
        }
        #endif
        if let url = Bundle.main.url(forResource: "NativeScriptSharedRuntime", withExtension: nil) {
            return url
        }
        if let bundleURL = Bundle.main.url(forResource: "HanlinNativeScriptRuntime_HanlinNativeScriptRuntime", withExtension: "bundle"),
           let bundle = Bundle(url: bundleURL),
           let url = bundle.url(forResource: "NativeScriptSharedRuntime", withExtension: nil) {
            return url
        }
        if let resourceURL = Bundle.main.resourceURL {
            let candidate = resourceURL.appendingPathComponent("NativeScriptSharedRuntime", isDirectory: true)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                return candidate
            }
        }
        return nil
    }

    public let applicationRoot: URL
    public let containerController: UIViewController

    private let presenter: HanlinNativeScriptPresenter
    private var runtime: HanlinNativeScriptRuntimeHost?
    private(set) public var isActive = false
    private var createdSymlinks: Set<URL> = []
    public let environment: [String: String]

    public init(applicationRoot: URL, environment: [String: String] = [:]) throws {
        let root = applicationRoot.standardizedFileURL
        guard root.isFileURL else {
            throw HanlinNativeScriptError.invalidApplicationRoot("the URL is not a file URL")
        }
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw HanlinNativeScriptError.invalidApplicationRoot("the root is not a real directory")
        }
        for required in ["package.json", "bundle.mjs"] {
            let candidate = root.appending(path: required, directoryHint: .notDirectory)
            let candidateValues = try? candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard candidateValues?.isRegularFile == true, candidateValues?.isSymbolicLink != true else {
                throw HanlinNativeScriptError.missingPreparedFile(required)
            }
        }
        let packageJSONURL = root.appending(path: "package.json", directoryHint: .notDirectory)
        try Self.validateNativePluginRequirements(packageJSONURL: packageJSONURL)
        try Self.validateCoreRequirements(packageJSONURL: packageJSONURL)
        self.applicationRoot = root
        self.environment = environment
        presenter = HanlinNativeScriptPresenter()
        containerController = presenter.containerController
    }

    public func start() throws {
        guard !isActive else { return }
        guard Self.activeSession == nil else {
            throw HanlinNativeScriptError.sessionAlreadyActive
        }

        presenter.install()
        do {
            for (key, value) in environment {
                setenv(key, value, 1)
            }
            try linkSharedRuntimeIfNeeded()
            let host = try HanlinNativeScriptRuntimeHost(
                baseDirectory: applicationRoot.deletingLastPathComponent().path(percentEncoded: false),
                applicationPath: applicationRoot.lastPathComponent
            )
            runtime = host
            Self.activeSession = self
            isActive = true

            try host.runMainApplication()
            NSLog("%@", "HANLIN_NS_INITIALIZED_EXTERNAL_ROOT path=\(applicationRoot.path(percentEncoded: false))")
        } catch {
            shutdown()
            throw HanlinNativeScriptError.bootstrapFailed(error.localizedDescription)
        }
    }

    public func shutdown() {
        for key in environment.keys {
            unsetenv(key)
        }
        guard isActive || runtime != nil else {
            unlinkSharedRuntime()
            presenter.detach()
            return
        }
        presenter.detach()
        runtime?.shutdown()
        runtime = nil
        isActive = false
        unlinkSharedRuntime()
        if Self.activeSession === self { Self.activeSession = nil }
    }

    deinit {
        MainActor.assumeIsolated {
            shutdown()
        }
    }

    private func linkSharedRuntimeIfNeeded() throws {
        guard let sharedRuntime = Self.sharedRuntimeURL else {
            return
        }
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(at: sharedRuntime, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        for sourceURL in items {
            let itemName = sourceURL.lastPathComponent
            let targetURL = applicationRoot.appending(path: itemName, directoryHint: .isDirectory)
            let targetPath = targetURL.path(percentEncoded: false)

            if let dest = try? fm.destinationOfSymbolicLink(atPath: targetPath) {
                if dest == sourceURL.path(percentEncoded: false) {
                    createdSymlinks.insert(targetURL)
                    continue
                } else {
                    try? fm.removeItem(at: targetURL)
                }
            } else if fm.fileExists(atPath: targetPath) {
                // Already provided by applicationRoot directly (not a symlink)
                continue
            }

            do {
                try fm.createSymbolicLink(at: targetURL, withDestinationURL: sourceURL)
                createdSymlinks.insert(targetURL)
            } catch {
                #if os(Windows)
                try? fm.copyItem(at: sourceURL, to: targetURL)
                createdSymlinks.insert(targetURL)
                #else
                throw error
                #endif
            }
        }

        let nodeModulesURL = applicationRoot.appending(path: "node_modules", directoryHint: .isDirectory)
        let nodeModulesPath = nodeModulesURL.path(percentEncoded: false)
        if let dest = try? fm.destinationOfSymbolicLink(atPath: nodeModulesPath) {
            if dest == sharedRuntime.path(percentEncoded: false) {
                createdSymlinks.insert(nodeModulesURL)
            } else {
                try? fm.removeItem(at: nodeModulesURL)
                try? fm.createSymbolicLink(at: nodeModulesURL, withDestinationURL: sharedRuntime)
                createdSymlinks.insert(nodeModulesURL)
            }
        } else if !fm.fileExists(atPath: nodeModulesPath) {
            do {
                try fm.createSymbolicLink(at: nodeModulesURL, withDestinationURL: sharedRuntime)
                createdSymlinks.insert(nodeModulesURL)
            } catch {
                #if os(Windows)
                try? fm.copyItem(at: sharedRuntime, to: nodeModulesURL)
                createdSymlinks.insert(nodeModulesURL)
                #else
                throw error
                #endif
            }
        }
    }

    private func unlinkSharedRuntime() {
        let fm = FileManager.default
        for url in createdSymlinks {
            try? fm.removeItem(at: url)
        }
        createdSymlinks.removeAll()
    }

    public static func isCoreVersionCompatible(_ versionString: String) -> Bool {
        let trimmed = versionString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "*" || trimmed == "latest" {
            return true
        }
        var cleaned = trimmed
        if cleaned.hasPrefix("^") || cleaned.hasPrefix("~") || cleaned.hasPrefix("=") || cleaned.hasPrefix("v") {
            cleaned = String(cleaned.dropFirst())
        }
        if cleaned.hasPrefix("9.1") {
            return true
        }
        if trimmed.hasPrefix("^9.") {
            return true
        }
        return false
    }

    private static func validateCoreRequirements(packageJSONURL: URL) throws {
        let data = try Data(contentsOf: packageJSONURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        var declaredCoreVersion: String?
        if let deps = root["dependencies"] as? [String: Any], let version = deps["@nativescript/core"] as? String {
            declaredCoreVersion = version
        } else if let devDeps = root["devDependencies"] as? [String: Any], let version = devDeps["@nativescript/core"] as? String {
            declaredCoreVersion = version
        }
        if let version = declaredCoreVersion {
            guard isCoreVersionCompatible(version) else {
                throw HanlinNativeScriptError.unsupportedCoreVersion(
                    "This Hanlin build supports @nativescript/core \(supportedRuntimeVersion), but the package requires \(version)."
                )
            }
        }
    }

    private static func validateNativePluginRequirements(packageJSONURL: URL) throws {
        let data = try Data(contentsOf: packageJSONURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HanlinNativeScriptError.invalidApplicationRoot("package.json is not an object")
        }
        guard let contractValue = root["hanlinNativeScript"] else { return }
        guard let contract = contractValue as? [String: Any] else {
            throw HanlinNativeScriptError.unsupportedNativePlugin("hanlinNativeScript must be an object.")
        }
        guard contract["runtimeVersion"] as? String == supportedRuntimeVersion else {
            throw HanlinNativeScriptError.unsupportedNativePlugin(
                "this build requires runtimeVersion \(supportedRuntimeVersion)."
            )
        }
        guard let plugins = contract["plugins"] as? [String: Any] else {
            throw HanlinNativeScriptError.unsupportedNativePlugin("plugins must be an object.")
        }
        for (name, value) in plugins.sorted(by: { $0.key < $1.key }) {
            guard name == "@nativescript/swift-ui", value as? String == supportedSwiftUIVersion else {
                throw HanlinNativeScriptError.unsupportedNativePlugin(
                    "\(name) \(value as? String ?? "<invalid>") is not embedded in this Hanlin build."
                )
            }
        }
        if plugins["@nativescript/swift-ui"] != nil {
            let providerClass: AnyClass = HanlinNativeScriptSwiftUIFixtureProvider.self
            guard NSStringFromClass(providerClass) == "HanlinNativeScriptSwiftUIFixtureProvider",
                  NSClassFromString("HanlinNativeScriptSwiftUIFixtureProvider") === providerClass else {
                throw HanlinNativeScriptError.unsupportedNativePlugin(
                    "the embedded SwiftUI provider is unavailable."
                )
            }
        }
    }
}
