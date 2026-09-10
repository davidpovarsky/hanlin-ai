// HanlinScriptMiniAppRegistrationTests.swift
// HanlinScriptStoreTests

import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinScriptStore
import Testing

@Suite("Script Mini App registration and discovery")
struct HanlinScriptMiniAppRegistrationTests {
    @Test("Stored package snapshot conforms to HanlinMiniAppRegistration and validates")
    func storedPackageProducesValidDescriptor() throws {
        let packageID = try HanlinPackageID(validating: "com.example.transit")
        let installedID = try HanlinInstalledPackageID(validating: "inst.com.example.transit")
        let version = try HanlinPackageVersion(validating: "1.2.3")
        let capID = try HanlinCapabilityID(validating: "network.fetch")

        let record = HanlinInstalledPackageRecord(
            schemaVersion: 1,
            installedPackageID: installedID,
            packageID: packageID,
            version: version,
            sourceDigest: String(repeating: "b", count: 64),
            artifactDigest: String(repeating: "c", count: 64),
            activeGeneration: 1,
            installedAt: .now,
            updatedAt: .now
        )

        let entrypoints = [
            HanlinPackageEntrypointDescriptor(
                id: "app",
                kind: .app,
                sourcePath: "src/index.tsx",
                supportedContexts: [.mainApplication],
                runtimePolicyID: "foreground-app-v1",
                compatibility: .supported
            ),
            HanlinPackageEntrypointDescriptor(
                id: "embeddedResult",
                kind: .embeddedResult,
                sourcePath: "src/embedded_result.tsx",
                supportedContexts: [.mainApplication],
                runtimePolicyID: "embedded-result-v1",
                compatibility: .supported
            ),
            HanlinPackageEntrypointDescriptor(
                id: "widget",
                kind: .widget,
                sourcePath: "src/widget.tsx",
                supportedContexts: [.widget],
                runtimePolicyID: "widget-v1",
                compatibility: .supported
            ),
            HanlinPackageEntrypointDescriptor(
                id: "translationUI",
                kind: .translationUI,
                sourcePath: "src/translation_ui_provider.tsx",
                supportedContexts: [.translationUI],
                runtimePolicyID: "translation-ui-v1",
                compatibility: .supported
            )
        ]

        let manifest = HanlinScriptingManifest(
            name: "Transit Assistant",
            version: "1.2.3",
            description: "Nearby arrivals and route finding",
            author: .init(name: "Transit Team", email: "team@transit.example", homepage: "https://transit.example"),
            icon: "bus.fill",
            color: "3366FF"
        )

        let snapshot = HanlinStoredPackageSnapshot(
            record: record,
            entrypoints: entrypoints,
            enabled: true,
            availableGenerations: [1],
            grantedCapabilities: [capID],
            manifest: manifest
        )

        // Verify HanlinMiniAppRegistration conformance
        let registration: any HanlinMiniAppRegistration = snapshot
        #expect(registration.appID.rawValue == packageID.rawValue)

        let descriptor = try registration.appDescriptor()
        try descriptor.validate()

        #expect(descriptor.id.rawValue == "com.example.transit")
        #expect(descriptor.version == version)
        #expect(descriptor.entryPoints.count == 4)

        let kinds = Set(descriptor.entryPoints.map(\.kind))
        #expect(kinds.contains(.app))
        #expect(kinds.contains(.embeddedResult))
        #expect(kinds.contains(.widget))
        #expect(kinds.contains(.translationUI))

        #expect(descriptor.capabilities.map(\.id) == [capID])
        #expect(descriptor.appearance.accentHex == "#3366FF")
    }

    @Test("Package entrypoint kinds bridge bidirectionally to canonical kinds")
    func entrypointKindBridging() {
        #expect(HanlinPackageEntrypointKind.app.canonicalKind == .app)
        #expect(HanlinPackageEntrypointKind.assistantTool.canonicalKind == .assistantTool)
        #expect(HanlinPackageEntrypointKind.embeddedResult.canonicalKind == .embeddedResult)
        #expect(HanlinPackageEntrypointKind.widget.canonicalKind == .widget)
        #expect(HanlinPackageEntrypointKind.appIntent.canonicalKind == .appIntentBridge)
        #expect(HanlinPackageEntrypointKind.liveActivity.canonicalKind == .liveActivity)
        #expect(HanlinPackageEntrypointKind.translationUI.canonicalKind == .translationUI)
        #expect(HanlinPackageEntrypointKind.spotlight.canonicalKind == .spotlight)
        #expect(HanlinPackageEntrypointKind.share.canonicalKind == .shareExtension)

        #expect(HanlinPackageEntrypointKind(canonicalKind: .app) == .app)
        #expect(HanlinPackageEntrypointKind(canonicalKind: .assistantTool) == .assistantTool)
        #expect(HanlinPackageEntrypointKind(canonicalKind: .embeddedResult) == .embeddedResult)
        #expect(HanlinPackageEntrypointKind(canonicalKind: .widget) == .widget)
        #expect(HanlinPackageEntrypointKind(canonicalKind: .appIntentBridge) == .appIntent)
        #expect(HanlinPackageEntrypointKind(canonicalKind: .liveActivity) == .liveActivity)
        #expect(HanlinPackageEntrypointKind(canonicalKind: .translationUI) == .translationUI)
        #expect(HanlinPackageEntrypointKind(canonicalKind: .spotlight) == .spotlight)
        #expect(HanlinPackageEntrypointKind(canonicalKind: .shareExtension) == .share)

        for kind in HanlinPackageEntrypointKind.allCases {
            #expect(!kind.exposureKind.rawValue.isEmpty)
        }
    }

    @Test("HanlinScriptPackageDiscovery discovers registrations and builds catalog snapshot")
    func scriptPackageDiscovery() async throws {
        let packageID = try HanlinPackageID(validating: "com.example.notes")
        let installedID = try HanlinInstalledPackageID(validating: "inst.com.example.notes")
        let version = try HanlinPackageVersion(validating: "2.0.0")

        let record = HanlinInstalledPackageRecord(
            schemaVersion: 1,
            installedPackageID: installedID,
            packageID: packageID,
            version: version,
            sourceDigest: String(repeating: "d", count: 64),
            artifactDigest: String(repeating: "e", count: 64),
            activeGeneration: 1,
            installedAt: .now,
            updatedAt: .now
        )

        let snapshot = HanlinStoredPackageSnapshot(
            record: record,
            entrypoints: [
                .init(
                    id: "app",
                    kind: .app,
                    sourcePath: "index.tsx",
                    supportedContexts: [.mainApplication],
                    runtimePolicyID: "foreground-app-v1",
                    compatibility: .supported
                )
            ],
            enabled: true,
            availableGenerations: [1],
            manifest: .init(name: "Notes", version: "2.0.0")
        )

        let discovery = HanlinScriptPackageDiscovery(snapshots: [snapshot])
        let registrations = try await discovery.registrations()
        #expect(registrations.count == 1)
        #expect(registrations[0].appID.rawValue == "com.example.notes")

        let found = try await discovery.registration(for: try HanlinAppID(validating: "com.example.notes"))
        #expect(found != nil)

        let notFound = try await discovery.registration(for: try HanlinAppID(validating: "com.example.missing"))
        #expect(notFound == nil)

        let catalog = try await discovery.catalogSnapshot(revision: .init(1))
        #expect(catalog.apps.count == 1)
        #expect(catalog.apps[0].id.rawValue == "com.example.notes")
    }

    @Test("NativeScript package preserves nativeScript implementation, runtimeProfile, and exposures")
    func nativeScriptPreservesExecutionIdentityAndExposures() throws {
        let packageID = try HanlinPackageID(validating: "com.example.nativescript.module")
        let installedID = try HanlinInstalledPackageID(validating: "inst.com.example.nativescript.module")
        let version = try HanlinPackageVersion(validating: "1.0.0")

        let record = HanlinInstalledPackageRecord(
            schemaVersion: 1,
            installedPackageID: installedID,
            packageID: packageID,
            version: version,
            sourceDigest: String(repeating: "f", count: 64),
            artifactDigest: String(repeating: "a", count: 64),
            activeGeneration: 1,
            installedAt: .now,
            updatedAt: .now
        )

        let snapshot = HanlinStoredPackageSnapshot(
            record: record,
            entrypoints: [
                .init(
                    id: "app",
                    kind: .app,
                    sourcePath: "index.swift",
                    supportedContexts: [.mainApplication],
                    runtimePolicyID: "nativescript-v1",
                    runtimeProfile: .hanlinNativeScript,
                    compatibility: .supported
                ),
                .init(
                    id: "spotlight",
                    kind: .spotlight,
                    sourcePath: "search.swift",
                    supportedContexts: [.mainApplication],
                    runtimePolicyID: "spotlight-v1",
                    runtimeProfile: .hanlinNativeScript,
                    compatibility: .supported
                ),
                .init(
                    id: "share",
                    kind: .share,
                    sourcePath: "share.swift",
                    supportedContexts: [.mainApplication],
                    runtimePolicyID: "share-v1",
                    runtimeProfile: .hanlinNativeScript,
                    compatibility: .supported
                ),
                .init(
                    id: "quickLook",
                    kind: .quickLook,
                    sourcePath: "preview.swift",
                    supportedContexts: [.mainApplication],
                    runtimePolicyID: "quicklook-v1",
                    runtimeProfile: .hanlinNativeScript,
                    compatibility: .supported
                )
            ],
            enabled: true,
            availableGenerations: [1],
            manifest: .init(name: "Native Module", version: "1.0.0")
        )

        let descriptor = try snapshot.appDescriptor()
        try descriptor.validate()

        // 1. Implementation MUST be .nativeScript, NOT .script
        guard case let .nativeScript(pkgID) = descriptor.implementation else {
            Issue.record("Expected .nativeScript implementation, got \(descriptor.implementation)")
            return
        }
        #expect(pkgID == packageID)

        // 2. Entry points MUST preserve runtimeProfile
        let appEP = descriptor.entryPoints.first { $0.kind == .app }
        #expect(appEP?.runtimeProfile == .hanlinNativeScript)

        let spotlightEP = descriptor.entryPoints.first { $0.kind == .spotlight }
        #expect(spotlightEP != nil)
        #expect(spotlightEP?.runtimeProfile == .hanlinNativeScript)

        let shareEP = descriptor.entryPoints.first { $0.kind == .shareExtension }
        #expect(shareEP != nil)
        #expect(shareEP?.runtimeProfile == .hanlinNativeScript)

        // 3. Supported exposures MUST include all declared surfaces (even secondary ones like quickLook)
        let exposures = snapshot.supportedExposures
        #expect(exposures.contains(.foregroundApp))
        #expect(exposures.contains(.spotlight))
        #expect(exposures.contains(.shareExtension))
        #expect(exposures.contains(.quickLook))
    }

    @Test("Exposure-only package does not get fake .app entrypoint and retains declared exposures in catalog snapshot")
    func exposureOnlyPackageDoesNotFabricateApp() async throws {
        let packageID = try HanlinPackageID(validating: "com.example.quicklook.viewer")
        let installedID = try HanlinInstalledPackageID(validating: "inst.com.example.quicklook.viewer")
        let version = try HanlinPackageVersion(validating: "1.0.0")

        let record = HanlinInstalledPackageRecord(
            schemaVersion: 1,
            installedPackageID: installedID,
            packageID: packageID,
            version: version,
            sourceDigest: String(repeating: "f", count: 64),
            artifactDigest: String(repeating: "1", count: 64),
            activeGeneration: 1,
            installedAt: .now,
            updatedAt: .now
        )

        // A package whose only entrypoint is quickLook (which has no executable HanlinEntryPointKind)
        let snapshot = HanlinStoredPackageSnapshot(
            record: record,
            entrypoints: [
                .init(
                    id: "preview",
                    kind: .quickLook,
                    sourcePath: "preview.js",
                    supportedContexts: [.mainApplication],
                    runtimePolicyID: "quicklook-v1",
                    compatibility: .supported
                )
            ],
            enabled: true,
            availableGenerations: [1],
            manifest: .init(name: "QuickLook Previewer", version: "1.0.0")
        )

        // b) Exposure-only package gets NO fake .app entrypoint
        let descriptor = try snapshot.appDescriptor()
        #expect(descriptor.entryPoints.isEmpty)
        #expect(!descriptor.entryPoints.contains { $0.kind == .app })

        // Descriptor itself owns the exposure declaration
        #expect(descriptor.supportedExposures == [.quickLook])

        // Registration derives from descriptor truth
        #expect(snapshot.supportedExposures == [.quickLook])

        // a) Catalog snapshot retains the declared exposure
        let discovery = HanlinScriptPackageDiscovery(snapshots: [snapshot])
        let catalog = try await discovery.catalogSnapshot(revision: .init(1))
        #expect(catalog.apps.count == 1)
        #expect(catalog.apps[0].supportedExposures == [.quickLook])
        #expect(catalog.apps[0].entryPoints.isEmpty)

        // Validation passes because supportedExposures is non-empty
        try descriptor.validate()
    }

    @Test("Normal legacy foreground script package gets expected app/index.tsx behavior")
    func legacyForegroundScriptPackageGetsDefaultApp() throws {
        let packageID = try HanlinPackageID(validating: "com.example.legacy.app")
        let installedID = try HanlinInstalledPackageID(validating: "inst.com.example.legacy.app")
        let version = try HanlinPackageVersion(validating: "1.0.0")

        let record = HanlinInstalledPackageRecord(
            schemaVersion: 1,
            installedPackageID: installedID,
            packageID: packageID,
            version: version,
            sourceDigest: String(repeating: "a", count: 64),
            artifactDigest: String(repeating: "b", count: 64),
            activeGeneration: 1,
            installedAt: .now,
            updatedAt: .now
        )

        // Legacy package with empty entrypoints array but a manifest
        let snapshot = HanlinStoredPackageSnapshot(
            record: record,
            entrypoints: [],
            enabled: true,
            availableGenerations: [1],
            manifest: .init(name: "Legacy App", version: "1.0.0", entry: "main.tsx", runInApp: true)
        )

        let descriptor = try snapshot.appDescriptor()
        try descriptor.validate()

        // d) Normal legacy foreground script package still gets expected app behavior
        #expect(descriptor.entryPoints.count == 1)
        #expect(descriptor.entryPoints[0].kind == .app)
        #expect(descriptor.entryPoints[0].handler == "main.tsx")
        #expect(descriptor.supportedExposures.contains(.foregroundApp))
        #expect(snapshot.supportedExposures.contains(.foregroundApp))
    }

    @Test("Unknown and future exposure raw values survive Codable round-trip")
    func unknownExposureRawValueSurvivesCodable() throws {
        let customExposure = HanlinExposureKind(rawValue: "spatial_environment_v2")
        let packageID = try HanlinPackageID(validating: "com.example.custom.exposure")
        let appID = try HanlinAppID(validating: "com.example.custom.exposure")

        let descriptor = HanlinAppDescriptor(
            schemaVersion: .init(major: 1, minor: 0),
            descriptorRevision: HanlinDescriptorRevision(1),
            id: appID,
            name: try LocalizedValue(["en": "Spatial Mini App"]),
            summary: try LocalizedValue(["en": "Custom surface app"]),
            description: try LocalizedValue(["en": "Custom surface app"]),
            version: try HanlinPackageVersion(validating: "1.0.0"),
            apiVersion: .init(major: 1, minor: 0),
            icon: .systemSymbol(name: "cube.fill"),
            category: .utilities,
            implementation: .script(packageID: packageID),
            entryPoints: [],
            supportedExposures: [customExposure],
            authors: [HanlinAuthor(name: "Author")],
            distribution: .init(
                sourceVisible: true,
                sourceEditable: true,
                remoteUpdates: false,
                allowedModes: [.personalDevelopment]
            )
        )

        try descriptor.validate()

        // c) Unknown/future exposure raw value survives Codable round-trip
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(descriptor)
        let roundTripped = try decoder.decode(HanlinAppDescriptor.self, from: data)

        #expect(roundTripped.supportedExposures == [customExposure])
        #expect(roundTripped.supportedExposures[0].rawValue == "spatial_environment_v2")
    }

    @Test("Legacy descriptor JSON without supportedExposures decodes seamlessly with default derivation")
    func legacyDescriptorWithoutSupportedExposuresDecodes() throws {
        let packageID = try HanlinPackageID(validating: "com.example.legacy.json")
        let appID = try HanlinAppID(validating: "com.example.legacy.json")

        let descriptor = HanlinAppDescriptor(
            schemaVersion: .init(major: 1, minor: 0),
            descriptorRevision: HanlinDescriptorRevision(1),
            id: appID,
            name: try LocalizedValue(["en": "Legacy JSON App"]),
            summary: try LocalizedValue(["en": "Legacy JSON"]),
            description: try LocalizedValue(["en": "Legacy JSON"]),
            version: try HanlinPackageVersion(validating: "1.0.0"),
            apiVersion: .init(major: 1, minor: 0),
            icon: .systemSymbol(name: "app.fill"),
            category: .utilities,
            implementation: .script(packageID: packageID),
            entryPoints: [
                HanlinEntryPointDescriptor(kind: .app, handler: "index.tsx", allowedContexts: [.mainApplication])
            ],
            authors: [HanlinAuthor(name: "Author")],
            distribution: .init(
                sourceVisible: true,
                sourceEditable: true,
                remoteUpdates: false,
                allowedModes: [.personalDevelopment]
            )
        )

        var jsonObject = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(descriptor)) as! [String: Any]
        jsonObject.removeValue(forKey: "supportedExposures")
        let legacyData = try JSONSerialization.data(withJSONObject: jsonObject)

        let decoded = try JSONDecoder().decode(HanlinAppDescriptor.self, from: legacyData)
        #expect(decoded.supportedExposures == [.foregroundApp])
    }
}
