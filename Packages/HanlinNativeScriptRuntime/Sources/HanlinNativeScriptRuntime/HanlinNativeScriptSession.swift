import Foundation
import HanlinNativeScriptCoreSupport
import UIKit

@MainActor
public final class HanlinNativeScriptSession {
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
        applicationRoot = root
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

            let entryURL = applicationRoot
                .appending(path: "bundle.mjs", directoryHint: .notDirectory)
                .absoluteString
            let packageName = try Self.packageName(at: applicationRoot)
            let encodedURL = try JSONEncoder().encode(entryURL)
            let encodedName = try JSONEncoder().encode(packageName)
            guard let quotedURL = String(data: encodedURL, encoding: .utf8),
                  let quotedName = String(data: encodedName, encoding: .utf8) else {
                throw HanlinNativeScriptError.bootstrapFailed("could not encode the entry URL")
            }
            try host.runScript(
                "globalThis.__HANLIN_NATIVESCRIPT_PACKAGE_NAME__ = \(quotedName); "
                    + "import(\(quotedURL)).catch(error => { console.error('[Hanlin NativeScript]', error && (error.stack || error.message || error)); });",
                runLoop: true
            )
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

    private static func packageName(at root: URL) throws -> String {
        struct Manifest: Decodable { let name: String }
        let data = try Data(contentsOf: root.appending(path: "package.json"))
        let name = try JSONDecoder().decode(Manifest.self, from: data).name
        guard !name.isEmpty else {
            throw HanlinNativeScriptError.invalidApplicationRoot("package.json has an empty name")
        }
        return name
    }
}
