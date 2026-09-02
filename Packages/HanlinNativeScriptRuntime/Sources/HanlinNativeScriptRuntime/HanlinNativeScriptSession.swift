import Foundation
import HanlinNativeScriptCoreSupport
import UIKit

@MainActor
public final class HanlinNativeScriptSession {
    private static let supportedRuntimeVersion = "9.1.0"
    private static let supportedSwiftUIVersion = "4.0.2"
    private static weak var activeSession: HanlinNativeScriptSession?

    public let applicationRoot: URL
    public let containerController: UIViewController

    private let presenter: HanlinNativeScriptPresenter
    private var runtime: HanlinNativeScriptRuntimeHost?
    private(set) public var isActive = false

    public init(applicationRoot: URL) throws {
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
        try Self.validateNativePluginRequirements(
            packageJSONURL: root.appending(path: "package.json", directoryHint: .notDirectory)
        )
        self.applicationRoot = root
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
            let host = try HanlinNativeScriptRuntimeHost(
                baseDirectory: applicationRoot.deletingLastPathComponent().path(percentEncoded: false),
                applicationPath: applicationRoot.lastPathComponent
            )
            runtime = host
            Self.activeSession = self
            isActive = true

            try host.runMainApplication()
            print("HANLIN_NS_INITIALIZED_EXTERNAL_ROOT path=\(applicationRoot.path(percentEncoded: false))")
        } catch {
            shutdown()
            throw HanlinNativeScriptError.bootstrapFailed(error.localizedDescription)
        }
    }

    public func shutdown() {
        guard isActive || runtime != nil else {
            presenter.detach()
            return
        }
        presenter.detach()
        runtime?.shutdown()
        runtime = nil
        isActive = false
        if Self.activeSession === self { Self.activeSession = nil }
    }

    deinit {
        MainActor.assumeIsolated {
            shutdown()
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
