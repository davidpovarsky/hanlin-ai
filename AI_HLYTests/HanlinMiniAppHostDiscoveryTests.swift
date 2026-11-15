import Foundation
import HanlinMiniAppCore
import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinScriptStore
import Testing
@testable import AI_Hanlin

@MainActor
@Suite("MiniApp Host canonical package discovery")
struct HanlinMiniAppHostDiscoveryTests {
    @Test func ordinaryScriptUIUsesTheCanonicalJSCLaunchPlan() async throws {
        let package = try snapshot()
        let item = try #require(try await items([package]).first)
        let plan = try HanlinMiniAppLaunchPlan(descriptor: item.descriptor)
        #expect(item.id == package.appID)
        #expect(item.engine == .scriptingJSC)
        #expect(plan.engine == .scriptingJSC)
        #expect(plan.entryPoint.handler == "src/main.tsx")
    }

    @Test func nativeScriptAndExpoKeepTheirDeclaredEngines() async throws {
        for (runtime, engine) in [(HanlinRuntimeProfile.hanlinNativeScript, HanlinMiniAppEngine.nativeScript), (.hanlinExpo, .expo)] {
            let package = try snapshot(runtime: runtime)
            let item = try #require(try await items([package]).first)
            #expect(item.engine == engine)
            #expect(try HanlinMiniAppLaunchPlan(descriptor: item.descriptor).engine == engine)
        }
    }

    @Test func disabledPackagesStayUndiscoverable() async throws {
        #expect(try await items([snapshot(enabled: false)]).isEmpty)
    }

    @Test func nonForegroundPackagesStayUndiscoverable() async throws {
        for kind in [HanlinPackageEntrypointKind.widget, .appIntent, .quickLook] {
            #expect(try await items([snapshot(kind: kind)]).isEmpty)
        }
        let legacy = try snapshot(entrypoints: [], manifest: .init(name: "Background", version: "1.0.0"))
        #expect(try await items([legacy]).isEmpty)
    }

    @Test func unsupportedAndUnknownRuntimesStayUndiscoverable() async throws {
        for runtime in [HanlinRuntimeProfile.hanlinQuickJS, .hanlinNode, .hanlinPython] {
            #expect(try await items([snapshot(runtime: runtime)]).isEmpty)
        }
        let unknown = try snapshot(manifest: .init(name: "Unknown", version: "1.0.0", entry: "src/main.tsx", hanlinRuntime: "unknown-runtime"))
        #expect(try await items([unknown]).isEmpty)
        let malformed = try snapshot(manifest: .init(name: "Malformed", version: "1.0.0", unknownFields: ["hanlinRuntime": .integer(42)]))
        #expect(try await items([malformed]).isEmpty)
    }

    @Test func invalidCanonicalDescriptorsStayUndiscoverable() async throws {
        let invalid = try snapshot(sourcePath: "../escape.tsx")
        #expect(throws: Error.self) { try invalid.appDescriptor() }
        #expect(try await items([invalid]).isEmpty)
    }

    @Test func legacyForegroundAndExplicitRuntimeDoNotNeedFilenameHints() async throws {
        let legacy = try snapshot(entrypoints: [], manifest: .init(name: "Legacy", version: "1.0.0", entry: "src/main.tsx"))
        #expect(try await items([legacy]).first?.engine == .scriptingJSC)
        let named = try snapshot(sourcePath: "src/expo-nativescript.tsx")
        #expect(try await items([named]).first?.engine == .scriptingJSC)
    }

    private func items(_ snapshots: [HanlinStoredPackageSnapshot]) async throws -> [HanlinMiniAppCatalogItem] {
        try await HanlinCanonicalMiniAppCatalog(
            discovery: HanlinMiniAppHost.packageDiscovery(installedPackages: snapshots)
        ).items()
    }

    private func snapshot(
        runtime: HanlinRuntimeProfile = .scriptingJSC,
        kind: HanlinPackageEntrypointKind = .app,
        sourcePath: String = "src/main.tsx",
        enabled: Bool = true,
        entrypoints: [HanlinPackageEntrypointDescriptor]? = nil,
        manifest: HanlinScriptingManifest = .init(name: "Ordinary ScriptUI", version: "1.0.0")
    ) throws -> HanlinStoredPackageSnapshot {
        let record = HanlinInstalledPackageRecord(
            installedPackageID: try .init(validating: "installed.unit.discovery"),
            packageID: try .init(validating: "hanlin.unit.discovery"),
            version: try .init(validating: "1.0.0"),
            sourceDigest: String(repeating: "b", count: 64),
            artifactDigest: String(repeating: "c", count: 64),
            activeGeneration: 1, installedAt: .distantPast, updatedAt: .distantPast
        )
        return HanlinStoredPackageSnapshot(
            record: record,
            entrypoints: entrypoints ?? [.init(
                id: "unit", kind: kind, sourcePath: sourcePath,
                supportedContexts: [.mainApplication], runtimePolicyID: "foreground-app-v1",
                runtimeProfile: runtime, compatibility: .supported
            )],
            enabled: enabled, availableGenerations: [1], manifest: manifest
        )
    }
}
