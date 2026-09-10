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
}
