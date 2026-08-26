import CryptoKit
import Foundation
import HanlinPlatformContracts
import HanlinScriptCompiler
import HanlinScriptContracts
import HanlinScriptExtensions
import HanlinScriptDeviceServices
import HanlinScriptStore
import HanlinScriptUI
import HanlinScriptingSDK
import Observation
import SwiftData

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
    private(set) var activeApplicationID: HanlinInstalledPackageID?
    private(set) var activeApplicationModel: HanlinScriptUIModel?

    private let packageCenter = HanlinPackageCenter()
    private var stagedPackage: HanlinStagedPackage?
    private var analyzer: HanlinScriptAnalyzer?
    private var store: HanlinAtomicScriptStore?
    private var bundler: HanlinScriptingBundler?
    private var extensionStore: HanlinScriptExtensionStore?
    private var applicationSession: HanlinScriptingApplicationSession?
    private var modelContext: ModelContext?
    private let locationService = HanlinAppleLocationService()
    private let healthService = HanlinAppleHealthService()
    private let notificationService = HanlinAppleNotificationService()
    private var liveActivityRevisions: [String: UInt64] = [:]
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
                scriptingDeclarations: try HanlinScriptingSDK.declarationFiles().map {
                    HanlinVirtualSourceFile(
                        logicalPath: "virtual/\($0.name)",
                        bytes: $0.data
                    )
                },
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

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
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

    func clearFailure() {
        if case .failed = activity { activity = .idle }
    }

    func uninstall(_ id: HanlinInstalledPackageID) async {
        guard let store else { return }
        do {
            if activeApplicationID == id { dismissActiveApplication() }
            try await store.uninstall(id)
            installedPackages = try await store.snapshots()
        } catch {
            activity = .failed(Self.safeMessage(error))
        }
    }

    func rollback(_ id: HanlinInstalledPackageID, to generation: UInt64) async {
        guard let store else { return }
        do {
            if activeApplicationID == id { dismissActiveApplication() }
            _ = try await store.rollback(id, to: generation)
            installedPackages = try await store.snapshots()
        } catch {
            activity = .failed(Self.safeMessage(error))
        }
    }

    func setEnabled(_ enabled: Bool, for id: HanlinInstalledPackageID) async {
        guard let store else { return }
        do {
            if !enabled, activeApplicationID == id { dismissActiveApplication() }
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
            if !granted, activeApplicationID == id { dismissActiveApplication() }
            try await store.setCapabilityGranted(granted, capability: capability, for: id)
            installedPackages = try await store.snapshots()
        } catch {
            activity = .failed(Self.safeMessage(error))
        }
    }

    func launch(_ id: HanlinInstalledPackageID) async {
        guard let store,
              let package = installedPackages.first(where: { $0.record.installedPackageID == id }) else {
            activity = .failed("The installed package could not be found.")
            return
        }
        guard package.enabled else {
            activity = .failed("Enable this package before launching it.")
            return
        }
        guard let entrypoint = package.entrypoints.first(where: { $0.kind == .app }) else {
            activity = .failed("This package does not contain an app entrypoint.")
            return
        }
        guard entrypoint.runtimeProfile == .scriptingJSC else {
            activity = .failed("Interactive ScriptUI currently requires the scripting-jsc runtime.")
            return
        }
        let required = Set(entrypoint.requiredCapabilities.filter(\.required).map(\.capabilityID))
        guard required.isSubset(of: Set(package.grantedCapabilities)) else {
            activity = .failed("Grant every required capability before launching this package.")
            return
        }
        do {
            let artifactRoot = try await store.activeArtifactURL(for: id)
            let compiledPath = try Self.compiledPath(for: entrypoint.sourcePath)
            let compiledURL = artifactRoot.appending(path: compiledPath, directoryHint: .notDirectory)
            let attributes = try FileManager.default.attributesOfItem(atPath: compiledURL.path())
            guard let bytes = attributes[.size] as? NSNumber, bytes.intValue <= 4 * 1_024 * 1_024 else {
                throw HanlinScriptingPlatformError.compiledEntrypointTooLarge
            }
            let program = try String(contentsOf: compiledURL, encoding: .utf8)
            dismissActiveApplication()
            let storageCapability = try HanlinCapabilityID(validating: "storage")
            let filesCapability = try HanlinCapabilityID(validating: "files")
            let networkCapability = try HanlinCapabilityID(validating: "network")
            let locationCapability = try HanlinCapabilityID(validating: "location")
            let healthCapability = try HanlinCapabilityID(validating: "health")
            let notificationsCapability = try HanlinCapabilityID(validating: "notifications")
            let assistantCapability = try HanlinCapabilityID(validating: "assistant")
            let session = try HanlinScriptingApplicationSession(
                installedPackageID: id,
                program: program,
                filename: compiledPath,
                storageAllowed: package.grantedCapabilities.contains(storageCapability),
                filesAllowed: package.grantedCapabilities.contains(filesCapability),
                networkAllowed: package.grantedCapabilities.contains(networkCapability),
                packageSourceDirectory: artifactRoot.appending(path: "source", directoryHint: .isDirectory),
                locationAllowed: package.grantedCapabilities.contains(locationCapability),
                locationLoader: { [weak self] request in
                    guard let self else { throw CancellationError() }
                    return try await self.performLocation(request)
                },
                healthAllowed: package.grantedCapabilities.contains(healthCapability),
                healthDataAvailable: HanlinAppleHealthService.isHealthDataAvailable,
                healthStatisticsLoader: { [weak self] request in
                    guard let self else { throw CancellationError() }
                    return try await self.performHealthStatistics(request)
                },
                notificationsAllowed: package.grantedCapabilities.contains(notificationsCapability),
                notificationLoader: { [weak self] request in
                    guard let self else { throw CancellationError() }
                    return try await self.performNotification(request, installedPackageID: id)
                },
                assistantAllowed: package.grantedCapabilities.contains(assistantCapability),
                assistantLoader: { [weak self] request in
                    guard let self else { throw CancellationError() }
                    return try await self.performAssistant(request)
                },
                liveActivityAllowed: true,
                liveActivityLoader: { [weak self] request in
                    guard let self else { throw CancellationError() }
                    return try await self.performLiveActivity(request, installedPackageID: id)
                },
                deviceSnapshot: HanlinAppleDeviceSnapshotProvider.snapshot()
            )
            applicationSession = session
            activeApplicationID = id
            activeApplicationModel = session.model
            activity = .idle
        } catch {
            dismissActiveApplication()
            activity = .failed(Self.safeMessage(error))
        }
    }

    func dismissActiveApplication() {
        applicationSession?.dismiss()
        applicationSession = nil
        activeApplicationID = nil
        activeApplicationModel = nil
    }

    private func performLocation(
        _ request: HanlinScriptingLocationRequest
    ) async throws -> HanlinScriptingLocationResult {
        switch request.action {
        case .requestCurrent:
            let value = try await locationService.currentLocation(forceRequest: request.forceRequest)
            return .location(Self.scriptingLocation(value))
        case .geocodeAddress:
            guard let address = request.address else {
                throw HanlinScriptingPlatformError.invalidLocationPayload
            }
            let values = try await locationService.geocodeAddress(
                address,
                localeIdentifier: request.localeIdentifier
            )
            return .placemarks(values.map(Self.scriptingPlacemark))
        case .reverseGeocode:
            guard let latitude = request.latitude, let longitude = request.longitude else {
                throw HanlinScriptingPlatformError.invalidLocationPayload
            }
            let values = try await locationService.reverseGeocode(
                latitude: latitude,
                longitude: longitude,
                localeIdentifier: request.localeIdentifier
            )
            return .placemarks(values.map(Self.scriptingPlacemark))
        case .setAccuracy:
            guard let accuracy = request.accuracy else {
                throw HanlinScriptingPlatformError.invalidLocationPayload
            }
            try locationService.setAccuracy(accuracy)
            return .success
        }
    }

    private func performAssistant(
        _ request: HanlinScriptingAssistantRequest
    ) async throws -> AsyncThrowingStream<HanlinScriptingAssistantChunk, Error> {
        guard let modelContext else {
            throw HanlinScriptingNativeError(
                name: "Error",
                code: "assistant_configuration_unavailable",
                message: "The Assistant configuration is unavailable."
            )
        }
        return try await HanlinScriptingAssistantProviderAdapter(context: modelContext).load(request)
    }

    private func performHealthStatistics(
        _ request: HanlinScriptingHealthStatisticsRequest
    ) async throws -> HanlinScriptingHealthStatisticsResult? {
        let metric: HanlinScriptHealthMetric = switch request.metric {
        case .stepCount: .steps
        case .distanceWalkingRunning: .walkingRunningDistance
        case .activeEnergyBurned: .activeEnergy
        case .heartRate: .heartRate
        }
        let options = Set(request.options.map { option -> HanlinScriptHealthStatisticsOption in
            switch option {
            case .cumulativeSum: .cumulativeSum
            case .discreteAverage: .discreteAverage
            }
        })
        guard let result = try await healthService.statistics(
            metric,
            from: request.startDate,
            to: request.endDate,
            options: options
        ) else { return nil }
        return .init(
            metric: request.metric,
            unit: result.unit,
            startDate: result.startDate,
            endDate: result.endDate,
            sum: result.sum,
            average: result.average
        )
    }

    private func performNotification(
        _ request: HanlinScriptingNotificationRequest,
        installedPackageID: HanlinInstalledPackageID
    ) async throws -> Bool {
        let identifierPrefix = "hanlin.\(installedPackageID.rawValue)."
        switch request.action {
        case .removeAllPendingsOfCurrentScript:
            await notificationService.removePending(identifierPrefix: identifierPrefix)
            return true
        case .schedule:
            guard let title = request.title, let trigger = request.trigger else {
                throw HanlinScriptingPlatformError.invalidNotificationPayload
            }
            let nativeTrigger: HanlinScriptLocalNotificationTrigger = switch trigger {
            case .immediate:
                .immediate
            case let .timeInterval(seconds, repeats):
                .timeInterval(seconds: seconds, repeats: repeats)
            case let .calendar(components, timeZoneIdentifier, repeats):
                .calendar(
                    components: components,
                    timeZoneIdentifier: timeZoneIdentifier,
                    repeats: repeats
                )
            }
            try await notificationService.schedule(.init(
                id: identifierPrefix + UUID().uuidString.lowercased(),
                title: title,
                subtitle: request.subtitle ?? "",
                body: request.body ?? "",
                badge: request.badge,
                silent: request.silent,
                interruptionLevel: request.interruptionLevel,
                threadIdentifier: request.threadIdentifier ?? "",
                userInfoJSON: request.userInfoJSON,
                trigger: nativeTrigger
            ))
            return true
        }
    }

    private static func scriptingLocation(
        _ value: HanlinScriptLocationValue
    ) -> HanlinScriptingLocationInfo {
        .init(
            latitude: value.latitude,
            longitude: value.longitude,
            timestampMilliseconds: value.timestamp.timeIntervalSince1970 * 1_000
        )
    }

    private static func scriptingPlacemark(
        _ value: HanlinScriptPlacemarkValue
    ) -> HanlinScriptingLocationPlacemark {
        .init(
            location: scriptingLocation(value.location),
            timeZoneIdentifier: value.timeZoneIdentifier,
            name: value.name,
            locality: value.locality,
            isoCountryCode: value.isoCountryCode,
            country: value.country
        )
    }

    private func performLiveActivity(
        _ request: HanlinScriptingLiveActivityRequest,
        installedPackageID: HanlinInstalledPackageID
    ) async throws -> HanlinScriptingLiveActivityResult {
#if os(iOS)
        if request.action == .areActivitiesEnabled {
            return .success(HanlinScriptLiveActivityController.areActivitiesEnabled)
        }
        guard let root = request.root, let stateJSON = request.stateJSON else {
            throw HanlinScriptingPlatformError.invalidLiveActivityPayload
        }
        let state = try HanlinValue(jsonValue: HanlinJSONValue.decodeCanonicalJSON(stateJSON))
        let title = request.name ?? "Live Activity"
        switch request.action {
        case .start:
            let logicalID = UUID().uuidString.lowercased()
            let content = HanlinGenericLiveActivityAttributes.ContentState(
                revision: 1, title: title, state: state, root: root
            )
            let systemID = try HanlinScriptLiveActivityController.start(
                attributes: .init(installedPackageID: installedPackageID.rawValue, activityID: logicalID),
                state: content,
                staleDate: request.staleDate,
                relevanceScore: request.relevanceScore ?? 0
            )
            liveActivityRevisions[systemID] = 1
            return .started(activityID: systemID)
        case .update:
            guard let activityID = request.activityID else {
                throw HanlinScriptingPlatformError.invalidLiveActivityPayload
            }
            let revision = (liveActivityRevisions[activityID] ?? 0) + 1
            let success = await HanlinScriptLiveActivityController.update(
                systemActivityID: activityID,
                state: .init(revision: revision, title: title, state: state, root: root),
                staleDate: request.staleDate,
                relevanceScore: request.relevanceScore ?? 0
            )
            if success { liveActivityRevisions[activityID] = revision }
            return .success(success)
        case .end:
            guard let activityID = request.activityID else {
                throw HanlinScriptingPlatformError.invalidLiveActivityPayload
            }
            let revision = (liveActivityRevisions[activityID] ?? 0) + 1
            let success = await HanlinScriptLiveActivityController.end(
                systemActivityID: activityID,
                finalState: .init(revision: revision, title: title, state: state, root: root),
                dismissTimeInterval: request.dismissTimeInterval
            )
            if success { liveActivityRevisions[activityID] = nil }
            return .success(success)
        case .areActivitiesEnabled:
            return .success(HanlinScriptLiveActivityController.areActivitiesEnabled)
        }
#else
        _ = installedPackageID
        throw HanlinScriptingPlatformError.invalidLiveActivityPayload
#endif
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

    nonisolated private static func compiledPath(for sourcePath: String) throws -> String {
        guard sourcePath.hasPrefix("source/"), !sourcePath.contains(".."), !sourcePath.contains("\\") else {
            throw HanlinScriptingPlatformError.invalidEntrypointPath
        }
        let relative = String(sourcePath.dropFirst("source/".count))
        guard let dot = relative.lastIndex(of: "."), dot > relative.startIndex else {
            throw HanlinScriptingPlatformError.invalidEntrypointPath
        }
        let extensionName = relative[relative.index(after: dot)...].lowercased()
        guard ["ts", "tsx", "js", "jsx"].contains(extensionName) else {
            throw HanlinScriptingPlatformError.invalidEntrypointPath
        }
        return "compiled/\(relative[..<dot]).js"
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
    case compiledEntrypointTooLarge
    case invalidEntrypointPath
    case invalidLiveActivityPayload
    case invalidLocationPayload
    case invalidNotificationPayload
}

private extension JSONEncoder {
    static var canonical: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
