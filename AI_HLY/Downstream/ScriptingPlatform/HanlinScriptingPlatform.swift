import CryptoKit
import Foundation
import HanlinPlatformContracts
import HanlinScriptCompiler
import HanlinScriptContracts
import HanlinScriptStore
import HanlinScriptingSDK
import Observation

@MainActor
@Observable
final class HanlinScriptingPlatform {
    enum Activity: Equatable {
        case idle
        case importing
        case previewReady
        case installing
        case failed(String)
    }

    static let shared = HanlinScriptingPlatform()

    private(set) var activity: Activity = .idle
    private(set) var preview: HanlinImportPreview?
    private(set) var installedPackages: [HanlinStoredPackageSnapshot] = []
    private(set) var bootstrapError: String?

    private let packageCenter = HanlinPackageCenter()
    private var stagedPackage: HanlinStagedPackage?
    private var analyzer: HanlinScriptAnalyzer?
    private var store: HanlinAtomicScriptStore?
    private let stagingRoot: URL?

    private init() {
        do {
            let metadata = try HanlinScriptingSDK.metadata()
            analyzer = HanlinScriptAnalyzer(inventory: .init(
                baselineID: metadata.baselineID,
                baselineDigest: metadata.baselineDigest,
                symbols: try metadata.records.map { record in
                    .init(
                        symbol: record.symbol,
                        state: record.state,
                        requiredCapability: try record.capability.map(HanlinCapabilityID.init(validating:)),
                        allowedContexts: record.contexts.contains("all")
                            ? Set(HanlinExecutionContext.allCases)
                            : Set(record.contexts.compactMap(HanlinExecutionContext.init(rawValue:)))
                    )
                }
            ))
            let applicationSupport = try Self.applicationSupportDirectory()
            let platformRoot = applicationSupport.appending(path: "ScriptingPlatform", directoryHint: .isDirectory)
            let staging = platformRoot.appending(path: "ImportStaging", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            stagingRoot = staging
            store = try HanlinAtomicScriptStore(
                root: platformRoot.appending(path: "Installed", directoryHint: .isDirectory)
            )
        } catch {
            stagingRoot = nil
            bootstrapError = Self.safeMessage(error)
        }
    }

    func restore() async {
        guard let store else { return }
        do {
            installedPackages = try await store.restore()
        } catch {
            bootstrapError = Self.safeMessage(error)
        }
    }

    func importPackage(from sourceURL: URL) async {
        discardPreview()
        guard let analyzer, let stagingRoot else {
            activity = .failed(bootstrapError ?? "Scripting platform is unavailable.")
            return
        }
        activity = .importing
        do {
            let center = packageCenter
            let result = try await Task.detached(priority: .userInitiated) {
                let staged = try center.stageAndInspect(
                    sourceURL: sourceURL,
                    stagingParent: stagingRoot
                )
                do {
                    return (staged, try analyzer.analyze(staged))
                } catch {
                    try? center.discard(staged)
                    throw error
                }
            }.value
            stagedPackage = result.0
            preview = result.1
            activity = .previewReady
        } catch {
            activity = .failed(Self.safeMessage(error))
        }
    }

    func installPreview() async {
        guard let preview, preview.canInstall, stagedPackage != nil else {
            activity = .failed("This package did not pass Import Preview.")
            return
        }
        activity = .installing
        // Installation deliberately remains closed until Commit 7 can provide a
        // signed, in-process iOS build of the exact TypeScript 7.0.2 compiler.
        activity = .failed(
            "TypeScript 7.0.2 has no iOS compiler artifact. The package remains staged and no catalog state was changed."
        )
    }

    func discardPreview() {
        if let stagedPackage { try? packageCenter.discard(stagedPackage) }
        stagedPackage = nil
        preview = nil
        if case .failed = activity {} else { activity = .idle }
    }

    func reportImportFailure(_ error: Error) {
        discardPreview()
        activity = .failed(Self.safeMessage(error))
    }

    func uninstall(_ id: HanlinInstalledPackageID) async {
        guard let store else { return }
        do {
            try await store.uninstall(id)
            installedPackages = try await store.snapshots()
        } catch {
            activity = .failed(Self.safeMessage(error))
        }
    }

    func setEnabled(_ enabled: Bool, for id: HanlinInstalledPackageID) async {
        guard let store else { return }
        do {
            try await store.setEnabled(enabled, for: id)
            installedPackages = try await store.snapshots()
        } catch {
            activity = .failed(Self.safeMessage(error))
        }
    }

    static func stablePackageID(for manifest: HanlinScriptingManifest) throws -> HanlinPackageID {
        let digest = SHA256.hash(data: Data(manifest.name.precomposedStringWithCanonicalMapping.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return try HanlinPackageID(validating: "script-\(digest.prefix(24))")
    }

    private static func applicationSupportDirectory() throws -> URL {
        guard let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw HanlinPackageCenterError.stagingFailed
        }
        return url.appending(path: "Hanlin", directoryHint: .isDirectory)
    }

    private static func safeMessage(_ error: Error) -> String {
        String(String(describing: error).prefix(512))
    }
}
