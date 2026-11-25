// HanlinScriptMiniAppRegistrationTests.swift
// HanlinScriptStoreTests

import Foundation
import HanlinMiniAppCore
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
            descriptorRevision: try HanlinDescriptorRevision(1),
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
            descriptorRevision: try HanlinDescriptorRevision(1),
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

    @Test("Legacy-format NativeScript package with hanlinRuntime manifest field resolves to .nativeScript")
    func legacyFormatNativeScriptPackageResolvesProperly() throws {
        let packageID = try HanlinPackageID(validating: "sefaria-reader-core")
        let installedID = try HanlinInstalledPackageID(validating: "inst.sefaria-reader-core")
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
            entrypoints: [],
            enabled: true,
            availableGenerations: [1],
            manifest: .init(
                name: "Sefaria Library & Texts (Core)",
                version: "1.0.0",
                entry: "nativescript/app/bundle.mjs",
                runInApp: true,
                unknownFields: ["hanlinRuntime": .string("hanlin-nativescript")]
            )
        )

        let descriptor = try snapshot.appDescriptor()
        try descriptor.validate()

        guard case let .nativeScript(pkgID) = descriptor.implementation else {
            Issue.record("Expected .nativeScript implementation, got \(descriptor.implementation)")
            return
        }
        #expect(pkgID == packageID)

        let appEP = descriptor.entryPoints.first { $0.kind == .app }
        #expect(appEP?.runtimeProfile == .hanlinNativeScript)
        #expect(appEP?.handler == "nativescript/app/bundle.mjs")
    }

    @Test("Manifest declared supportedExposures (translation_ui, widget, app_intent) are exposed in appDescriptor")
    func manifestDeclaredSupportedExposures() throws {
        let packageID = try HanlinPackageID(validating: "hanlin.demo.script-parity")
        let version = try HanlinPackageVersion(validating: "1.0.0")
        let record = HanlinInstalledPackageRecord(
            installedPackageID: try .init(validating: "installed.script-parity"),
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
            entrypoints: [],
            enabled: true,
            availableGenerations: [1],
            manifest: .init(
                name: "HanlinScript Parity",
                version: "1.0.0",
                entry: "nativescript/app/bundle.mjs",
                runInApp: true,
                unknownFields: [
                    "hanlinRuntime": .string("hanlin-nativescript"),
                    "supportedExposures": .array([
                        .string("translation_ui"),
                        .string("widget"),
                        .string("app_intent")
                    ]),
                    "actions": .array([
                        .object([
                            "id": .string("parity.intent"),
                            "capability": .string("inter-app.share"),
                            "handler": .string("nativescript/app/bundle.mjs"),
                            "title": .string("Perform parity intent")
                        ])
                    ])
                ]
            )
        )

        let descriptor = try snapshot.appDescriptor()
        try descriptor.validate()

        #expect(descriptor.supportedExposures.contains(.translationUI))
        #expect(descriptor.supportedExposures.contains(.widget))
        #expect(descriptor.supportedExposures.contains(.appIntent))
        #expect(descriptor.actions.first?.id.rawValue == "parity.intent")
        #expect(descriptor.actions.first?.capabilities.map(\.rawValue) == ["inter-app.share"])
        #expect(descriptor.actions.first?.handler == "nativescript/app/bundle.mjs")
    }
    @Test("Prepared action handlers resolve to the installed bundle without a second source prefix")
    func preparedActionHandlersUseInstalledEntrypointPath() throws {
        let record = HanlinInstalledPackageRecord(schemaVersion: 1,
            installedPackageID: try .init(validating: "installed.expo"),
            packageID: try .init(validating: "package.expo"), version: try .init(validating: "1.0.0"),
            sourceDigest: String(repeating: "a", count: 64), artifactDigest: String(repeating: "b", count: 64),
            activeGeneration: 1, installedAt: .now, updatedAt: .now)
        for declared in ["bundle.js", "source/bundle.js"] {
            let manifest = HanlinScriptingManifest(name: "Action test", version: "1.0.0",
                unknownFields: ["hanlinRuntime": .string("hanlin-expo"), "actions": .array([
                    .object(["id": .string("search"), "handler": .string(declared),
                             "capability": .string("inter-app.share")])
                ])])
            let snapshot = HanlinStoredPackageSnapshot(record: record, entrypoints: [
                .init(id: "app", kind: .app, sourcePath: "source/bundle.js",
                      supportedContexts: [.mainApplication], runtimePolicyID: "foreground-app-v1",
                      runtimeProfile: .hanlinExpo, compatibility: .supported)
            ], enabled: true, availableGenerations: [1], manifest: manifest)
            #expect(try snapshot.appDescriptor().actions.first?.handler == "source/bundle.js")
        }
    }



    @Test("Prepared action exports retain their identities behind one canonical App Intent bridge")
    func preparedActionExportsShareCanonicalBridge() throws {
        let actionIDs = ["hostServicesEcho", "hostServicesFail", "hostServicesPublishWidget"]
        for runtime in [HanlinRuntimeProfile.hanlinExpo, .hanlinNativeScript] {
            let app = HanlinPackageEntrypointDescriptor(
                id: "app", kind: .app, sourcePath: "source/bundle.js",
                supportedContexts: [.mainApplication], runtimePolicyID: "foreground-app-v1",
                runtimeProfile: runtime, compatibility: .supported)
            let actions = actionIDs.map { id in
                HanlinPackageEntrypointDescriptor(
                    id: id, kind: .appIntent, sourcePath: "source/bundle.js", exportedSymbol: id,
                    supportedContexts: [.appIntent, .mainApplication],
                    runtimePolicyID: "prepared-foreground-action-v1",
                    runtimeProfile: runtime, compatibility: .supported)
            }
            let snapshot = try preparedActionSnapshot(entrypoints: [app] + actions, runtime: runtime)
            let descriptor = try snapshot.appDescriptor()
            let bridges = descriptor.entryPoints.filter { $0.kind == .appIntentBridge }
            let bridge = try #require(bridges.first)
            #expect(bridges.count == 1)
            #expect(bridge.handler == "source/bundle.js")
            #expect(bridge.runtimeProfile == runtime)
            #expect(Set(bridge.allowedContexts) == [.appIntent, .mainApplication])
            #expect(descriptor.entryPoints.filter { $0.kind == .app }.count == 1)
            #expect(snapshot.hasLaunchableApp)
            #expect(snapshot.entrypoints == [app] + actions)
            #expect(snapshot.entrypoints.filter { $0.kind == .appIntent }.map(\.exportedSymbol) == actionIDs.map(Optional.some))
            #expect(descriptor.actions.map(\.id.rawValue) == actionIDs)
            #expect(descriptor.actions.allSatisfy { $0.handler == "source/bundle.js" })
        }
    }

    @Test("Different App Intent handlers, runtimes and context sets remain conflicting canonical routes")
    func conflictingAppIntentBridgesRemainInvalid() throws {
        let original = HanlinPackageEntrypointDescriptor(
            id: "first", kind: .appIntent, sourcePath: "source/bundle.js", exportedSymbol: "first",
            supportedContexts: [.appIntent, .mainApplication], runtimePolicyID: "prepared-foreground-action-v1",
            runtimeProfile: .hanlinExpo, compatibility: .supported)
        let conflicts = [
            HanlinPackageEntrypointDescriptor(
                id: "otherHandler", kind: .appIntent, sourcePath: "source/other.js",
                supportedContexts: [.appIntent, .mainApplication], runtimePolicyID: "prepared-foreground-action-v1",
                runtimeProfile: .hanlinExpo, compatibility: .supported),
            HanlinPackageEntrypointDescriptor(
                id: "otherRuntime", kind: .appIntent, sourcePath: "source/bundle.js",
                supportedContexts: [.appIntent, .mainApplication], runtimePolicyID: "prepared-foreground-action-v1",
                runtimeProfile: .hanlinNativeScript, compatibility: .supported),
            HanlinPackageEntrypointDescriptor(
                id: "otherContext", kind: .appIntent, sourcePath: "source/bundle.js",
                supportedContexts: [.mainApplication], runtimePolicyID: "prepared-foreground-action-v1",
                runtimeProfile: .hanlinExpo, compatibility: .supported)
        ]
        for conflict in conflicts {
            let snapshot = try preparedActionSnapshot(entrypoints: [original, conflict])
            do {
                _ = try snapshot.appDescriptor()
                Issue.record("Conflicting App Intent routes must not be silently merged")
            } catch HanlinContractError.invalidManifest(let issues) {
                #expect(issues.contains { $0.code == .duplicateEntryPoint })
            }
        }
    }

    @Test("Identical foreground entries still violate the canonical unique-kind contract")
    func duplicateForegroundEntrypointsRemainInvalid() throws {
        let app = HanlinPackageEntrypointDescriptor(
            id: "app", kind: .app, sourcePath: "source/bundle.js",
            supportedContexts: [.mainApplication], runtimePolicyID: "foreground-app-v1",
            runtimeProfile: .hanlinExpo, compatibility: .supported)
        let snapshot = try preparedActionSnapshot(entrypoints: [app, app])
        do {
            _ = try snapshot.appDescriptor()
            Issue.record("Only shared App Intent bridges are coalesced")
        } catch HanlinContractError.invalidManifest(let issues) {
            #expect(issues.contains { $0.code == .duplicateEntryPoint })
        }
    }

    @Test("Prepared action identifiers preserve export case, round trip, and reject malformed values")
    func preparedActionIdentifiersPreserveCaseAndRejectMalformedValues() throws {
        let names = ["hostServicesEcho", "hostServicesFail", "hostServicesPublishWidget"]
        for name in names {
            let actionID = try HanlinActionID(validating: name)
            #expect(actionID.rawValue == name)
            #expect(actionID != HanlinActionID(rawValue: name.lowercased()))
            let encoded = try JSONEncoder().encode(actionID)
            #expect(try JSONDecoder().decode(HanlinActionID.self, from: encoded) == actionID)
            #expect(HanlinAppID(rawValue: name) == nil)
            #expect(HanlinCapabilityID(rawValue: name) == nil)
        }
        let invalidNames = ["", ".Echo", "Echo-", "Echo..Value", "Echo/_Value",
                            "Echo Value", "Echo\n", "הד", String(repeating: "A", count: 256)]
        for name in invalidNames {
            #expect(HanlinActionID(rawValue: name) == nil)
            let encoded = try JSONEncoder().encode(name)
            #expect(throws: HanlinContractError.self) {
                try JSONDecoder().decode(HanlinActionID.self, from: encoded)
            }
        }
        let schema = try #require(JSONSerialization.jsonObject(with: HanlinManifestSchema.data()) as? [String: Any])
        let definitions = try #require(schema["$defs"] as? [String: Any])
        let action = try #require(definitions["action"] as? [String: Any])
        let properties = try #require(action["properties"] as? [String: Any])
        let identity = try #require(properties["id"] as? [String: Any])
        #expect(identity["$ref"] as? String == "#/$defs/actionIdentifier")
        let actionIdentity = try #require(definitions["actionIdentifier"] as? [String: Any])
        let pattern = try #require(actionIdentity["pattern"] as? String)
        let expression = try NSRegularExpression(pattern: pattern)
        for name in names + ["share.value", "Action_1", "A"] {
            let range = NSRange(name.startIndex..., in: name)
            #expect(expression.firstMatch(in: name, range: range)?.range == range)
        }
        for name in invalidNames.dropLast() {
            let range = NSRange(name.startIndex..., in: name)
            #expect(expression.firstMatch(in: name, range: range) == nil)
        }
        #expect(actionIdentity["maxLength"] as? Int == 255)
    }

    @Test("Several dedicated assistant tools preserve their sources, configuration and installed identities")
    func preparedAssistantEntrypointsRemainDistinctInCatalog() async throws {
        for runtime in [HanlinRuntimeProfile.hanlinExpo, .hanlinNativeScript] {
            let snapshot = try preparedAssistantSnapshot(runtime: runtime)
            let descriptor = try snapshot.appDescriptor()
            let tools = descriptor.entryPoints.filter { $0.kind == .assistantTool }
            #expect(tools.count == 2)
            #expect(snapshot.entrypoints.map(\.id) == ["app", "catalog", "places"])
            #expect(tools.map(\.handler) == snapshot.entrypoints.dropFirst().map(\.sourcePath))
            #expect(tools.map(\.assistantTool) == snapshot.entrypoints.dropFirst().map(\.assistantTool))
            #expect(tools.compactMap { $0.assistantTool?.configuration?.defaultValues } == [
                .object(["scope": .string("catalog")]), .object(["scope": .string("places")])
            ])
            // Reusing an action name in independent tools is not a collision.
            #expect(tools.compactMap { $0.assistantTool?.actions.first?.id } == ["search", "search"])
            let restored = try HanlinAppDescriptor.decodeAndValidate(descriptor.canonicalJSONData())
            #expect(restored.entryPoints == descriptor.entryPoints)
            let catalog = HanlinCanonicalMiniAppCatalog(
                discovery: HanlinScriptPackageDiscovery(snapshots: [snapshot]))
            let items = try await catalog.items()
            let item = try #require(items.first)
            #expect(items.count == 1)
            #expect(item.id == snapshot.appID)
            #expect(item.descriptor.entryPoints == descriptor.entryPoints)
            #expect(try HanlinMiniAppLaunchPlan(descriptor: descriptor).entryPoint.kind == .app)
        }
    }

    @Test("Ambiguous assistant kinds need an exact registered handler without foreground fallback")
    func assistantEntrypointResolutionRequiresExactHandler() throws {
        let snapshot = try preparedAssistantSnapshot()
        let descriptor = try snapshot.appDescriptor()
        #expect(throws: HanlinMiniAppCatalogError.ambiguousEntrypoint(snapshot.appID, .assistantTool)) {
            try HanlinMiniAppLaunchPlan(descriptor: descriptor, entryPointKind: .assistantTool)
        }
        for entry in descriptor.entryPoints where entry.kind == .assistantTool {
            let plan = try HanlinMiniAppLaunchPlan(descriptor: descriptor,
                entryPointKind: .assistantTool, entryPointHandler: entry.handler)
            #expect(plan.entryPoint == entry)
            #expect(plan.engine == .expo)
        }
        for missing in ["source/assistant/missing/bundle.js", "source/app/bundle.js"] {
            #expect(throws: HanlinMiniAppCatalogError.missingEntrypoint(snapshot.appID, .assistantTool)) {
                try HanlinMiniAppLaunchPlan(descriptor: descriptor,
                    entryPointKind: .assistantTool, entryPointHandler: missing)
            }
        }
        let toolsOnly = try preparedAssistantSnapshot(includeApp: false).appDescriptor()
        // Classifying a shared engine never chooses a tool to execute.
        #expect(HanlinCanonicalMiniAppCatalog.foregroundEngine(for: toolsOnly) == .expo)
        #expect(throws: HanlinMiniAppCatalogError.ambiguousEntrypoint(snapshot.appID, .assistantTool)) {
            try HanlinMiniAppLaunchPlan(descriptor: toolsOnly, entryPointKind: .assistantTool)
        }
        let mixedTools = try preparedAssistantSnapshot(
            includeApp: false, secondaryRuntime: .hanlinNativeScript).appDescriptor()
        #expect(HanlinCanonicalMiniAppCatalog.foregroundEngine(for: mixedTools) == nil)
        let native = try HanlinMiniAppLaunchPlan(descriptor: mixedTools, entryPointKind: .assistantTool,
            entryPointHandler: "source/assistant/places/bundle.mjs")
        #expect(native.engine == .nativeScript)
    }

    @Test("Different assistant identities cannot alias the same dedicated handler")
    func duplicateAssistantHandlersRemainInvalid() throws {
        let snapshot = try preparedAssistantSnapshot(duplicateHandler: true)
        do {
            _ = try snapshot.appDescriptor()
            Issue.record("Assistant entrypoints require distinct registered handler paths")
        } catch HanlinContractError.invalidManifest(let issues) {
            #expect(issues.contains { $0.code == .duplicateEntryPoint })
        }
    }

    private func preparedAssistantSnapshot(
        runtime: HanlinRuntimeProfile = .hanlinExpo,
        duplicateHandler: Bool = false,
        includeApp: Bool = true,
        secondaryRuntime: HanlinRuntimeProfile? = nil
    ) throws -> HanlinStoredPackageSnapshot {
        let main = runtime == .hanlinNativeScript ? "bundle.mjs" : "bundle.js"
        let inputSchema = try HanlinJSONSchemaDocument.decodeCanonicalJSON(
            Data(#"{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object"}"#.utf8))
        let app = HanlinPackageEntrypointDescriptor(
            id: "app", kind: .app, sourcePath: "source/app/\(main)",
            supportedContexts: [.mainApplication], runtimePolicyID: "foreground-app-v1",
            runtimeProfile: runtime, compatibility: .supported)
        let tools = ["catalog", "places"].map { id in
            let sourceID = duplicateHandler ? "shared" : id
            let toolRuntime = id == "places" ? secondaryRuntime ?? runtime : runtime
            let toolMain = toolRuntime == .hanlinNativeScript ? "bundle.mjs" : "bundle.js"
            return HanlinPackageEntrypointDescriptor(
                id: id, kind: .assistantTool, sourcePath: "source/assistant/\(sourceID)/\(toolMain)",
                supportedContexts: [.mainApplication], runtimePolicyID: "prepared-assistant-tool-v1",
                runtimeProfile: toolRuntime, compatibility: .supported,
                assistantTool: .init(title: id, summary: "Search \(id)", actions: [
                    .init(id: "search", title: "Search", summary: "Search \(id)", inputSchema: inputSchema)
                ], configuration: .init(panels: [
                    .init(id: "options", title: "Options", fields: [
                        .init(key: "scope", title: "Scope", kind: .text,
                            required: true, defaultValue: .string(id))
                    ])
                ])))
        }
        return try preparedActionSnapshot(entrypoints: (includeApp ? [app] : []) + tools, runtime: runtime)
    }

    private func preparedActionSnapshot(
        entrypoints: [HanlinPackageEntrypointDescriptor],
        runtime: HanlinRuntimeProfile = .hanlinExpo
    ) throws -> HanlinStoredPackageSnapshot {
        let actionIDs = ["hostServicesEcho", "hostServicesFail", "hostServicesPublishWidget"]
        let manifest = HanlinScriptingManifest(
            name: "Expo SwiftUI Probe A", version: "1.0.0", entry: "bundle.js",
            hanlinRuntime: runtime.rawValue,
            unknownFields: ["actions": .array(actionIDs.map { id in
                .object(["id": .string(id), "handler": .string("bundle.js"),
                         "capability": .string("inter-app.share")])
            })])
        let record = HanlinInstalledPackageRecord(
            installedPackageID: try .init(validating: "installed.prepared.actions"),
            packageID: try .init(validating: "prepared.actions"), version: try .init(validating: "1.0.0"),
            sourceDigest: String(repeating: "a", count: 64), artifactDigest: String(repeating: "b", count: 64),
            activeGeneration: 1, installedAt: .distantPast, updatedAt: .distantPast)
        return HanlinStoredPackageSnapshot(
            record: record, entrypoints: entrypoints, enabled: true, availableGenerations: [1],
            grantedCapabilities: [try .init(validating: "inter-app.share")], manifest: manifest)
    }

}
