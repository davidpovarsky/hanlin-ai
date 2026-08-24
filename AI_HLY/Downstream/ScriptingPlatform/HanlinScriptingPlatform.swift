import CryptoKit
import Foundation
import HanlinPlatformContracts
import HanlinScriptCompiler
import HanlinScriptContracts
import HanlinScriptExtensions
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
    private(set) var pendingResumeCommands: [HanlinScriptResumeCommand] = []
    private(set) var approvedCapabilities: Set<HanlinCapabilityID> = []

    private let packageCenter = HanlinPackageCenter()
    private var stagedPackage: HanlinStagedPackage?
    private var analyzer: HanlinScriptAnalyzer?
    private var store: HanlinAtomicScriptStore?
    private var bundler: HanlinScriptingBundler?
    private var extensionStore: HanlinScriptExtensionStore?
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
            bundler = HanlinScriptingBundler(
                baseline: .init(
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
                ),
                abiVersion: HanlinScriptContractSupport.multiRuntime.abiVersion.description,
                scriptingDeclarations: try HanlinScriptingSDK.declarations(),
                compiler: HanlinNodeMobileScriptingCompiler()
            )
            let applicationSupport = try Self.applicationSupportDirectory()
            let platformRoot = applicationSupport.appending(path: "ScriptingPlatform", directoryHint: .isDirectory)
            let staging = platformRoot.appending(path: "ImportStaging", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            store = try HanlinAtomicScriptStore(
                root: platformRoot.appending(path: "Installed", directoryHint: .isDirectory)
            )
            extensionStore = try? HanlinScriptExtensionStore()
            stagingRoot = staging
        } catch {
            stagingRoot = nil
            bootstrapError = Self.safeMessage(error)
        }
    }

    func restore() async {
        guard let store else { return }
        do {
            installedPackages = try await store.restore()
            pendingResumeCommands = try extensionStore?.pendingCommands() ?? []
        } catch {
            bootstrapError = Self.safeMessage(error)
        }
    }

    func acknowledgeResumeCommand(_ command: HanlinScriptResumeCommand) {
        do {
            try extensionStore?.acknowledge(command.id)
            pendingResumeCommands.removeAll { $0.id == command.id }
        } catch {
            activity = .failed(Self.safeMessage(error))
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
        guard let preview, preview.canInstall, let stagedPackage,
              let store, let bundler, let stagingRoot else {
            activity = .failed("This package did not pass Import Preview.")
            return
        }
        let required = Set(preview.requestedCapabilities.filter(\.required).map(\.capabilityID))
        guard required.isSubset(of: approvedCapabilities) else {
            activity = .failed("Approve every required capability before installing this package.")
            return
        }
        activity = .installing
        let artifactRoot = stagingRoot.appending(
            path: "artifact-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        let grantedCapabilities = approvedCapabilities.sorted { $0.rawValue < $1.rawValue }
        do {
            let installed = try await Task.detached(priority: .userInitiated) {
                defer { try? FileManager.default.removeItem(at: artifactRoot) }
                try Self.copyPackageSource(from: stagedPackage.packageRoot, to: artifactRoot)
                let contexts = Set(preview.entrypoints
                    .filter { $0.runtimeProfile != .hanlinPython }
                    .map(\.kind))
                    .sorted { $0.rawValue < $1.rawValue }
                guard !preview.entrypoints.isEmpty else {
                    throw HanlinScriptingBundlerError.previewRejected
                }
                var bundles: [HanlinScriptingBundle] = []
                for context in contexts {
                    bundles.append(try await bundler.bundle(
                        package: stagedPackage,
                        preview: preview,
                        context: context
                    ))
                }
                let compiled = if bundles.isEmpty {
                    try Self.pythonSourceBundle(preview: preview)
                } else {
                    try bundler.merged(bundles)
                }
                try bundler.write(compiled, to: artifactRoot)
                let completeManifest = try Self.completeArtifactManifest(
                    compiled.manifest,
                    artifactRoot: artifactRoot
                )
                try JSONEncoder.canonical.encode(completeManifest).write(
                    to: artifactRoot.appending(path: "artifact-manifest.json"),
                    options: .atomic
                )
                let packageID = try Self.stablePackageID(for: preview.manifest ?? stagedPackage.manifest)
                let installedID = try HanlinInstalledPackageID(validating: "install-\(packageID.rawValue)")
                let version = try HanlinPackageVersion(validating: stagedPackage.manifest.version)
                let entrypoints = preview.entrypoints.map { descriptor in
                    HanlinPackageEntrypointDescriptor(
                        id: descriptor.id,
                        kind: descriptor.kind,
                        sourcePath: "source/\(descriptor.sourcePath)",
                        exportedSymbol: descriptor.exportedSymbol,
                        supportedContexts: descriptor.supportedContexts,
                        requiredCapabilities: descriptor.requiredCapabilities,
                        runtimePolicyID: descriptor.runtimePolicyID,
                        runtimeProfile: descriptor.runtimeProfile,
                        artifactDigest: completeManifest.cacheFingerprint,
                        compatibility: descriptor.compatibility
                    )
                }
                let plan = HanlinInstallPlan(
                    installedPackageID: installedID,
                    packageID: packageID,
                    version: version,
                    sourceDigest: preview.source.contentSHA256,
                    entrypoints: entrypoints,
                    requestedCapabilities: preview.requestedCapabilities,
                    grantedCapabilities: grantedCapabilities,
                    manifest: stagedPackage.manifest
                )
                if try await store.snapshots().contains(where: { $0.record.installedPackageID == installedID }) {
                    return try await store.update(
                        plan: plan,
                        artifactDirectory: artifactRoot,
                        artifactManifest: completeManifest
                    )
                }
                return try await store.install(
                    plan: plan,
                    artifactDirectory: artifactRoot,
                    artifactManifest: completeManifest
                )
            }.value
            installedPackages = try await store.snapshots()
            _ = installed
            discardPreview()
            activity = .idle
        } catch {
            activity = .failed(Self.safeMessage(error))
        }
    }

    func setCapabilityApproved(_ approved: Bool, capability: HanlinCapabilityID) {
        if approved { approvedCapabilities.insert(capability) }
        else { approvedCapabilities.remove(capability) }
    }

    func discardPreview() {
        if let stagedPackage { try? packageCenter.discard(stagedPackage) }
        stagedPackage = nil
        preview = nil
        approvedCapabilities.removeAll(keepingCapacity: false)
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

    func rollback(_ id: HanlinInstalledPackageID, to generation: UInt64) async {
        guard let store else { return }
        do {
            _ = try await store.rollback(id, to: generation)
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

    func setCapabilityGranted(
        _ granted: Bool,
        capability: HanlinCapabilityID,
        for id: HanlinInstalledPackageID
    ) async {
        guard let store else { return }
        do {
            try await store.setCapabilityGranted(granted, capability: capability, for: id)
            installedPackages = try await store.snapshots()
        } catch {
            activity = .failed(Self.safeMessage(error))
        }
    }

    nonisolated static func stablePackageID(for manifest: HanlinScriptingManifest) throws -> HanlinPackageID {
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

    nonisolated private static func copyPackageSource(from source: URL, to artifactRoot: URL) throws {
        let destination = artifactRoot.appending(path: "source", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: destination)
    }

    nonisolated private static func completeArtifactManifest(
        _ compiled: HanlinPackageArtifactManifest,
        artifactRoot: URL
    ) throws -> HanlinPackageArtifactManifest {
        let sourceRoot = artifactRoot.appending(path: "source", directoryHint: .isDirectory)
        guard let enumerator = FileManager.default.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { throw HanlinScriptingPlatformError.artifactEnumerationFailed }
        var files = compiled.files
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw HanlinScriptingPlatformError.artifactEnumerationFailed }
            guard values.isRegularFile == true else { continue }
            let relative = String(url.path().dropFirst(sourceRoot.path().count + 1))
                .replacingOccurrences(of: "\\", with: "/")
            let data = try Data(contentsOf: url)
            files.append(.init(
                logicalPath: "source/\(relative)",
                sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                byteCount: Int64(data.count),
                context: .app
            ))
        }
        files.sort { $0.logicalPath < $1.logicalPath }
        guard Set(files.map(\.logicalPath)).count == files.count else {
            throw HanlinScriptingPlatformError.artifactEnumerationFailed
        }
        let fingerprint = SHA256.hash(data: Data(files.map { "\($0.logicalPath):\($0.sha256)" }.joined(separator: "\n").utf8))
            .map { String(format: "%02x", $0) }.joined()
        return .init(
            compilerVersion: compiled.compilerVersion,
            compilerIntegrity: compiled.compilerIntegrity,
            compilerOptionsHash: compiled.compilerOptionsHash,
            baselineID: compiled.baselineID,
            baselineDigest: compiled.baselineDigest,
            hanlinABIVersion: compiled.hanlinABIVersion,
            packageContentDigest: compiled.packageContentDigest,
            cacheFingerprint: fingerprint,
            files: files
        )
    }

    nonisolated private static func pythonSourceBundle(
        preview: HanlinImportPreview
    ) throws -> HanlinScriptingBundle {
        let metadata = try HanlinScriptingSDK.metadata()
        let optionsHash = SHA256.hash(data: Data("python-source-v1".utf8))
            .map { String(format: "%02x", $0) }.joined()
        let fingerprint = SHA256.hash(data: Data([
            preview.source.contentSHA256,
            "CPython-3.14.6",
            "200ef60eb67be0483ceb638daa9048f84f41a9a952707a5ad4c3198037c7b583",
            metadata.baselineID,
            metadata.baselineDigest,
            optionsHash,
        ].joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
        return .init(
            manifest: .init(
                compilerVersion: "CPython-3.14.6",
                compilerIntegrity: "200ef60eb67be0483ceb638daa9048f84f41a9a952707a5ad4c3198037c7b583",
                compilerOptionsHash: optionsHash,
                baselineID: metadata.baselineID,
                baselineDigest: metadata.baselineDigest,
                hanlinABIVersion: HanlinScriptContractSupport.multiRuntime.abiVersion.description,
                packageContentDigest: preview.source.contentSHA256,
                cacheFingerprint: fingerprint,
                files: []
            ),
            modules: [],
            diagnostics: []
        )
    }
}

private enum HanlinScriptingPlatformError: Error {
    case artifactEnumerationFailed
}

private extension JSONEncoder {
    static var canonical: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
