import Foundation
import HanlinExpoRuntime
import HanlinMiniAppCore
import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinScriptExtensions
import HanlinScriptStore
import XCTest
@testable import AI_Hanlin

/// Actual installed Metro/Hermes bundle -> Expo module -> owning platform/store.
/// WidgetKit preparation is checked separately from an OS placement/render claim.
@MainActor
final class HanlinExpoHostServicesAcceptanceTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 240
    }

    func testInstalledExpoActionsReturnActualReplyAndFailure() async throws {
        let fixture = try await installedFixture()
        defer { fixture.platform.dismissActiveApplication(); try? FileManager.default.removeItem(at: fixture.root) }
        let id = UUID()
        let payload: HanlinValue = .object(["ordinal": .integer(19), "unicode": .string("שלום"),
            "nested": .array([.null, .bool(true)])])
        let value = try await invoke(fixture, action: "hostServicesEcho", id: id, payload: payload)
        guard case let .object(reply) = value else { return XCTFail("Actual JS action returned no object") }
        XCTAssertEqual(reply["id"], .string(id.uuidString))
        XCTAssertEqual(reply["caller"], .string("hanlin.host"))
        XCTAssertEqual(reply["action"], .string("hostServicesEcho"))
        XCTAssertEqual(reply["parameters"], payload)
        XCTAssertEqual(reply["computed"], .integer(20))
        XCTAssertEqual(reply["storageVerified"], .bool(true))
        let failureID = UUID()
        do {
            _ = try await invoke(fixture, action: "hostServicesFail", id: failureID, payload: .null)
            XCTFail("An actual JS rejection must not become a successful acknowledgement")
        } catch let error as HanlinMiniAppActionChannel.ChannelError {
            XCTAssertEqual(error, .executionFailed("HOST_SERVICES_EXPECTED_FAILURE:" + failureID.uuidString))
        }
        // The failure must not poison the next request/response or reuse its UUID.
        let next = try await invoke(fixture, action: "hostServicesEcho", id: UUID(), payload: payload)
        guard case let .object(nextReply) = next else { return XCTFail("Action channel did not recover") }
        XCTAssertEqual(nextReply["computed"], .integer(20))
        XCTAssertNotEqual(nextReply["id"], reply["id"])
        attach(value, name: "expo-installed-action-reply")
    }

    func testPreparedExpoWidgetPublicationReachesExistingConsumer() async throws {
        let fixture = try await installedFixture()
        defer { fixture.platform.dismissActiveApplication(); try? FileManager.default.removeItem(at: fixture.root) }
        let before = try XCTUnwrap(fixture.extensions.load())
        let instance = try XCTUnwrap(before.widgetInstances.first(where: {
            $0.identity.installedPackageID == fixture.package.record.installedPackageID && $0.engine == .expo && $0.isDefault
        }))
        let template = try XCTUnwrap(before.widgets.first(where: { $0.identity == instance.identity && $0.family == "systemMedium" }))
        let (_, originalDigest) = try fixture.extensions.loadProgram(for: template)
        let props: HanlinValue = .object(["title": .string("HOST_SERVICES_PUBLISHED_WIDGET"), "counter": .integer(31)])
        let invocationID = UUID()
        // The real JS handler calls the public tagged facade; only its native
        // acknowledgement can complete this installed-package invocation.
        let value = try await invoke(fixture, action: "hostServicesPublishWidget", id: invocationID, payload: props)
        guard case let .object(receipt) = value else { return XCTFail("Missing publication receipt") }
        XCTAssertEqual(receipt["invocationID"], .string(invocationID.uuidString))
        XCTAssertEqual(receipt["installedPackageID"], .string(fixture.package.record.installedPackageID.rawValue))
        XCTAssertEqual(receipt["packageID"], .string(fixture.package.record.packageID.rawValue))
        XCTAssertEqual(receipt["generation"], .integer(Int64(fixture.package.record.activeGeneration)))
        XCTAssertEqual(receipt["entityID"], .string(instance.entityID))
        XCTAssertEqual(receipt["artifactSHA256"], .string(originalDigest))
        XCTAssertEqual(receipt["publication"], .string("prepared-expo-state"))
        for key in ["ok", "published", "stateCommitted", "catalogVisible", "reloadRequested"] {
            XCTAssertEqual(receipt[key], .bool(true), key)
        }
        XCTAssertEqual(receipt["osRendered"], .null)
        let reopened = HanlinScriptExtensions.HanlinScriptExtensionStore(root: fixture.extensions.root)
        let state = try XCTUnwrap(reopened.load()?.widgetStates.first(where: { $0.identity == instance.identity && $0.engine == .expo }))
        XCTAssertEqual(.object(state.values), props)
        XCTAssertEqual(receipt["revision"], .integer(Int64(state.revision)))
        XCTAssertEqual(state.artifactSHA256, originalDigest)
        let prepared = HanlinWidgetPreparation.prepare(store: reopened, entityID: instance.entityID, family: "systemMedium")
        guard case let .expo(node, context) = prepared else { return XCTFail("The actual Expo program consumer failed: \(prepared)") }
        XCTAssertEqual(context.identity, instance.identity)
        XCTAssertEqual(context.artifactSHA256, originalDigest)
        let texts = nativeTexts(node)
        XCTAssertTrue(texts.contains("HOST_SERVICES_PUBLISHED_WIDGET"), "The original layout must consume the new title")
        XCTAssertTrue(texts.contains("Counter: 31"), "The original layout must consume the new counter")
        let stale = HanlinScriptExtensionIdentity(installedPackageID: instance.identity.installedPackageID,
            packageID: instance.identity.packageID, generation: instance.identity.generation + 1,
            entrypointID: instance.identity.entrypointID, variantID: instance.identity.variantID)
        XCTAssertThrowsError(try reopened.publishExpoWidgetProps(identity: stale, props: [:])) { error in
            XCTAssertEqual(error as? HanlinWidgetActionError, .inactiveInstance)
        }
        let unchanged = try XCTUnwrap(reopened.load()?.widgetStates.first(where: { $0.identity == instance.identity && $0.engine == .expo }))
        XCTAssertEqual(unchanged, state)
        attach(value, name: "expo-prepared-widget-state-receipt")
        attach(node, name: "expo-prepared-widget-actual-consumer")
    }

    private struct Fixture {
        let root: URL
        let platform: HanlinScriptingPlatform
        let extensions: HanlinScriptExtensions.HanlinScriptExtensionStore
        let package: HanlinStoredPackageSnapshot
    }

    private func installedFixture() async throws -> Fixture {
        let bundle = Bundle(for: Self.self)
        let resources = try XCTUnwrap(bundle.url(forResource: "HostServicesProbe", withExtension: "bundle", subdirectory: "Fixtures")
            ?? bundle.url(forResource: "HostServicesProbe", withExtension: "bundle"))
        let archive = resources.appending(path: "ExpoSwiftUIProbeA.hanlinExpo")
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path), "The original Metro preparation must stage the actual fixture")
        let root = FileManager.default.temporaryDirectory.appending(path: "ExpoHostServices-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let extensions = HanlinScriptExtensions.HanlinScriptExtensionStore(root: root.appending(path: "Extensions"))
        let platform = HanlinScriptingPlatform(rootOverride: root.appending(path: "InstalledPlatform"), initialization: .init(
            registerExpoDefines: { HanlinExpoSession.ensureAppDefinesLoaded() },
            makeExtensionStore: { extensions }, enqueuePublication: { work in work() }))
        do {
            XCTAssertNil(platform.bootstrapError)
            await platform.importPackage(from: archive)
            XCTAssertTrue(platform.canInstallPreview, platform.importDiagnostics.map(\.message).joined(separator: "\n"))
            await platform.installPreview()
            let package = try XCTUnwrap(platform.installedPackages.first)
            XCTAssertTrue(package.enabled)
            XCTAssertGreaterThan(package.record.activeGeneration, 0)
            let descriptor = try package.appDescriptor()
            let app = try XCTUnwrap(package.entrypoints.first(where: { $0.kind == .app && $0.runtimeProfile == .hanlinExpo }))
            for name in ["hostServicesEcho", "hostServicesFail", "hostServicesPublishWidget"] {
                let action = try XCTUnwrap(descriptor.actions.first(where: { $0.id.rawValue == name }))
                XCTAssertEqual(action.handler, app.sourcePath)
                XCTAssertTrue(action.capabilities.contains(try .init(validating: "inter-app.share")))
            }
            XCTAssertTrue(package.entrypoints.contains(where: { $0.kind == .widget && $0.widgetEngine == .expo }))
            await platform.launch(package.record.installedPackageID)
            XCTAssertEqual(platform.activeApplicationID, package.record.installedPackageID)
            XCTAssertNotNil(platform.activeExpoController)
            return Fixture(root: root, platform: platform, extensions: extensions, package: package)
        } catch {
            platform.dismissActiveApplication()
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    private func invoke(_ fixture: Fixture, action: String, id: UUID, payload: HanlinValue) async throws -> HanlinValue {
        let completed = XCTestExpectation(description: "Real Expo action acknowledgement: " + action)
        var result: Result<HanlinValue, any Error>?
        let task = Task { @MainActor in
            defer { completed.fulfill() }
            do {
                result = .success(try await fixture.platform.executeHeadlessAction(
                    caller: try .init(validating: "hanlin.host"), targetAppID: fixture.package.appID,
                    action: try .init(validating: action), capability: try .init(validating: "inter-app.share"),
                    payload: payload, invocationID: id))
            } catch { result = .failure(error) }
        }
        let completion = await XCTWaiter.fulfillment(of: [completed], timeout: 60)
        task.cancel()
        XCTAssertEqual(completion, .completed, "The actual installed action must acknowledge before the test deadline")
        return try XCTUnwrap(result, "No native acknowledgement was received").get()
    }

    private func nativeTexts(_ value: HanlinValue) -> [String] {
        switch value {
        case let .object(fields):
            let own: [String]
            if case let .string(type)? = fields["type"], type == "TextView",
               case let .object(props)? = fields["props"], case let .string(text)? = props["text"] { own = [text] }
            else { own = [] }
            return own + fields.values.flatMap(nativeTexts)
        case let .array(values): return values.flatMap(nativeTexts)
        default: return []
        }
    }

    private func attach(_ value: HanlinValue, name: String) {
        if let data = try? value.jsonValue(destination: .javaScriptBinary64).canonicalJSONData(limits: .unbounded) {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
