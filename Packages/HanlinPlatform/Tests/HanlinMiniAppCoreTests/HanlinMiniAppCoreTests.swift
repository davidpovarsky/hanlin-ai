import Foundation
import HanlinMiniAppCore
import HanlinPlatformContracts
import Testing

private struct StaticRegistration: HanlinMiniAppRegistration {
    let appID: HanlinAppID
    let descriptorValue: HanlinAppDescriptor

    init(id: String, implementation: HanlinAppImplementation, runtime: HanlinRuntimeProfile?) throws {
        appID = try HanlinAppID(validating: id)
        descriptorValue = try HanlinAppDescriptor(
            schemaVersion: .init(major: 1, minor: 0),
            descriptorRevision: HanlinDescriptorRevision(1),
            id: appID,
            name: LocalizedValue(["en": id]),
            summary: LocalizedValue(["en": id]),
            description: LocalizedValue(["en": id]),
            version: HanlinPackageVersion(validating: "1.0.0"),
            apiVersion: .init(major: 1, minor: 0),
            icon: .systemSymbol(name: "app"),
            appearance: .init(accentHex: "#000000"),
            category: .utilities,
            implementation: implementation,
            entryPoints: [
                .init(
                    kind: .app,
                    handler: "main",
                    allowedContexts: [.mainApplication],
                    runtimeProfile: runtime
                )
            ],
            authors: [.init(name: "Demo")],
            distribution: .init(sourceVisible: true, sourceEditable: false, remoteUpdates: false, allowedModes: [.personalDevelopment])
        )
    }

    func appDescriptor() throws -> HanlinAppDescriptor { descriptorValue }
}

private struct StaticDiscovery: HanlinMiniAppDiscovery {
    let apps: [any HanlinMiniAppRegistration]
    init(_ apps: [any HanlinMiniAppRegistration]) { self.apps = apps }
    func registrations() async throws -> [any HanlinMiniAppRegistration] { apps }
    func registration(for appID: HanlinAppID) async throws -> (any HanlinMiniAppRegistration)? {
        apps.first { $0.appID == appID }
    }
    func catalogSnapshot(
        revision: HanlinCatalogRevision = .init(1)
    ) async throws -> HanlinCatalogSnapshot {
        let descriptors = try apps.map { try $0.appDescriptor() }
        return HanlinCatalogSnapshot(revision: revision, generatedAt: .now, apps: descriptors)
    }
}

@Suite("Canonical Mini App core")
struct HanlinMiniAppCoreTests {
    @Test("Catalog combines Swift and NativeScript engines, de-duplicates stable IDs, and omits legacy Scripting")
    func catalog() async throws {
        let swift = try StaticRegistration(id: "demo.swift", implementation: .native(
            moduleID: HanlinModuleID(validating: "demo.swift")
        ), runtime: nil)
        let nativeScript = try StaticRegistration(id: "demo.nativescript", implementation: .nativeScript(
            packageID: HanlinPackageID(validating: "demo.nativescript")
        ), runtime: .hanlinNativeScript)
        let legacy = try StaticRegistration(id: "demo.legacy", implementation: .script(
            packageID: HanlinPackageID(validating: "demo.legacy")
        ), runtime: .scriptingJSC)

        let discovery = HanlinCompositeMiniAppDiscovery(providers: [
            StaticDiscovery([swift, nativeScript]),
            StaticDiscovery([swift, legacy])
        ])
        let items = try await HanlinCanonicalMiniAppCatalog(discovery: discovery).items()
        #expect(items.map(\.id.rawValue) == ["demo.nativescript", "demo.swift"])
        #expect(items.map(\.engine) == [.nativeScript, .swift])
    }

    @Test("Launch runtime is selected from the requested entrypoint")
    func launchPlan() throws {
        let appID = try HanlinAppID(validating: "demo.multi")
        let descriptor = try HanlinAppDescriptor(
            schemaVersion: .init(major: 1, minor: 0),
            descriptorRevision: HanlinDescriptorRevision(1),
            id: appID,
            name: LocalizedValue(["en": "Multi"]),
            summary: LocalizedValue(["en": "Multi"]),
            description: LocalizedValue(["en": "Multi"]),
            version: HanlinPackageVersion(validating: "1.0.0"),
            apiVersion: .init(major: 1, minor: 0),
            icon: .systemSymbol(name: "app"),
            appearance: .init(accentHex: "#000000"),
            category: .utilities,
            implementation: .nativeScript(packageID: HanlinPackageID(validating: appID.rawValue)),
            entryPoints: [
                .init(kind: .app, handler: "index.js", allowedContexts: [.mainApplication], runtimeProfile: .hanlinNativeScript),
                .init(kind: .backgroundTask, handler: "worker.mjs", allowedContexts: [.backgroundTask], runtimeProfile: .hanlinNativeScript)
            ],
            authors: [.init(name: "Demo")],
            distribution: .init(sourceVisible: true, sourceEditable: false, remoteUpdates: false, allowedModes: [.personalDevelopment])
        )
        #expect(try HanlinMiniAppLaunchPlan(descriptor: descriptor, entryPointKind: .app).entryPoint.runtimeProfile == .hanlinNativeScript)
        #expect(try HanlinMiniAppLaunchPlan(descriptor: descriptor, entryPointKind: .backgroundTask).entryPoint.runtimeProfile == .hanlinNativeScript)
    }

    @Test("Data is durable, namespaced, traversal-safe, and quota-bound")
    func dataStore() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try HanlinMiniAppDataStore(
            root: root,
            limits: .init(maximumFileBytes: 8, maximumPersistentBytes: 8, maximumCacheBytes: 8)
        )
        let appA = try HanlinAppID(validating: "demo.a")
        let appB = try HanlinAppID(validating: "demo.b")
        try await first.write(Data("hello".utf8), appID: appA, area: .state, path: "value.txt")
        #expect(try await first.read(appID: appB, area: .state, path: "value.txt") == nil)
        let recreated = try HanlinMiniAppDataStore(root: root)
        #expect(try await recreated.read(appID: appA, area: .state, path: "value.txt") == Data("hello".utf8))
        await #expect(throws: HanlinMiniAppDataError.invalidPath("../escape")) {
            try await first.write(Data(), appID: appA, area: .documents, path: "../escape")
        }
        await #expect(throws: HanlinMiniAppDataError.fileTooLarge) {
            try await first.write(Data(repeating: 0, count: 9), appID: appA, area: .state, path: "large.bin")
        }
        try await first.write(Data(repeating: 1, count: 3), appID: appA, area: .data, path: "data.bin")
        await #expect(throws: HanlinMiniAppDataError.quotaExceeded(.documents)) {
            try await first.write(Data(repeating: 2, count: 6), appID: appA, area: .documents, path: "over-quota.bin")
        }
    }

    @Test("Inter-app requests enforce routes, capability, authorization, size, and timeout")
    func broker() async throws {
        let caller = try HanlinAppID(validating: "demo.caller")
        let target = try HanlinAppID(validating: "demo.target")
        let action = try HanlinActionID(validating: "share.value")
        let capability = try HanlinCapabilityID(validating: "inter-app.share")
        let broker = HanlinMiniAppRequestBroker(
            limits: .init(maximumPayloadBytes: 256, maximumResponseBytes: 256, timeout: .milliseconds(50)),
            authorizer: { $0.caller == caller && $0.target == target }
        )
        await broker.register(target: target, action: action, capability: capability) { request in
            request.payload
        }
        let allowed = HanlinMiniAppRequest(
            caller: caller,
            target: target,
            action: action,
            capability: capability,
            payload: .string("shared")
        )
        #expect(try await broker.request(allowed).value == .string("shared"))

        let denied = HanlinMiniAppRequest(
            caller: try HanlinAppID(validating: "demo.other"),
            target: target,
            action: action,
            capability: capability,
            payload: .null
        )
        await #expect(throws: HanlinMiniAppRequestError.unauthorized) {
            try await broker.request(denied)
        }
    }

    @Test("Per-entrypoint engine resolution works for hybrid descriptors")
    func hybridPerEntrypointResolution() throws {
        let appID = try HanlinAppID(validating: "demo.hybrid")
        let descriptor = try HanlinAppDescriptor(
            schemaVersion: .init(major: 1, minor: 0),
            descriptorRevision: HanlinDescriptorRevision(1),
            id: appID,
            name: LocalizedValue(["en": "Hybrid App"]),
            summary: LocalizedValue(["en": "App with mixed entrypoint runtimes"]),
            description: LocalizedValue(["en": "App with mixed entrypoint runtimes"]),
            version: HanlinPackageVersion(validating: "1.0.0"),
            apiVersion: .init(major: 1, minor: 0),
            icon: .systemSymbol(name: "app.badge"),
            appearance: .init(accentHex: "#123456", isBeta: true),
            category: .developer,
            implementation: .hybrid(
                moduleID: HanlinModuleID(validating: "demo.hybrid.native"),
                packageID: HanlinPackageID(validating: "demo.hybrid.script")
            ),
            entryPoints: [
                .init(kind: .app, handler: "MainView", allowedContexts: [.mainApplication], runtimeProfile: nil),
                .init(kind: .backgroundTask, handler: "task.mjs", allowedContexts: [.backgroundTask], runtimeProfile: .hanlinNativeScript)
            ],
            authors: [.init(name: "Demo")],
            distribution: .init(sourceVisible: true, sourceEditable: false, remoteUpdates: false, allowedModes: [.personalDevelopment])
        )

        // Foreground engine is Swift because .app has runtimeProfile: nil and implementation is .hybrid
        #expect(HanlinCanonicalMiniAppCatalog.foregroundEngine(for: descriptor) == HanlinMiniAppEngine.swift)

        // Launch plan for .app is Swift
        let appPlan = try HanlinMiniAppLaunchPlan(descriptor: descriptor, entryPointKind: .app)
        #expect(appPlan.engine == HanlinMiniAppEngine.swift)

        // Launch plan for .backgroundTask is NativeScript
        let bgPlan = try HanlinMiniAppLaunchPlan(descriptor: descriptor, entryPointKind: .backgroundTask)
        #expect(bgPlan.engine == HanlinMiniAppEngine.nativeScript)
        #expect(bgPlan.entryPoint.runtimeProfile == HanlinRuntimeProfile.hanlinNativeScript)
    }
}
