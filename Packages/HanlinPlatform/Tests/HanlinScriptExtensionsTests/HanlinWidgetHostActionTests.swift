import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts
import Testing
@testable import HanlinScriptExtensions

@Suite("Declared widget Host actions and canonical delivery", .serialized)
struct HanlinWidgetHostActionTests {
    @Test func ordinaryJSONParametersKeepNullNumbersUnicodeAndOmission() throws {
        let raw = Data(#"{"entrypointID":"intent.runtime","actionName":"runRuntime","parameters":{"text":"שלום 🌍","items":[null,true,42,1.25]}}"#.utf8)
        let decoded = try JSONDecoder().decode(HanlinWidgetHostAction.self, from: raw)
        let encoded = try JSONEncoder().encode(decoded)
        #expect(try JSONSerialization.jsonObject(with: raw) as? NSDictionary ==
            JSONSerialization.jsonObject(with: encoded) as? NSDictionary)
        let null = try JSONDecoder().decode(HanlinWidgetHostAction.self,
            from: Data(#"{"entrypointID":"intent.runtime","actionName":"runRuntime","parameters":null}"#.utf8))
        let omitted = try JSONDecoder().decode(HanlinWidgetHostAction.self,
            from: Data(#"{"entrypointID":"intent.runtime","actionName":"runRuntime"}"#.utf8))
        #expect(null.parameters == .null)
        #expect(omitted.parameters == nil)
        #expect((try JSONSerialization.jsonObject(with: JSONEncoder().encode(null)) as? [String: Any])?["parameters"] is NSNull)
        #expect((try JSONSerialization.jsonObject(with: JSONEncoder().encode(omitted)) as? [String: Any])?["parameters"] == nil)
    }

    @Test(arguments: [HanlinPlatformContracts.HanlinWidgetEngine.expo, .scriptwidget])
    func currentOriginQueuesExactDeclaredTargetAndRetainsNull(engine: HanlinPlatformContracts.HanlinWidgetEngine) throws {
        let fixture = try HostActionFixture(engine: engine, parameters: .null)
        defer { fixture.remove() }
        let queued = try HanlinWidgetHostActionExecutor.enqueue(fixture.command(), store: fixture.store)
        #expect(queued.invocation.identity == fixture.target.identity)
        #expect(queued.invocation.entityID == "runRuntime")
        #expect(queued.invocation.parameters == .null)
        #expect(queued.invocation.delivery?.appID == fixture.appID)
        #expect(queued.invocation.delivery?.source == .widget)
        #expect(queued.invocation.delivery?.widgetOrigin?.identity == fixture.identity)
        #expect(try fixture.store.receipt(for: queued.id)?.status == .queued)
        #expect(try fixture.store.receipt(for: queued.id)?.value == nil)
        #expect(try fixture.store.load()?.widgetStates.isEmpty == true)
        try HanlinWidgetHostActionExecutor.validateCurrentOrigin(queued, store: fixture.store)
    }

    @Test func liveActivityParametersOverrideDefaultsWithoutChangingSourceIdentity() throws {
        let fixture = try HostActionFixture(engine: .scriptwidget, parameters: .object(["value": .integer(1)]))
        defer { fixture.remove() }
        let payload: HanlinValue = .object(["value": .integer(42), "text": .string("אבג")])
        let queued = try HanlinWidgetHostActionExecutor.enqueue(
            fixture.command(liveActivity: true, parameters: payload), store: fixture.store)
        #expect(queued.invocation.parameters == payload)
        #expect(queued.invocation.delivery?.source == .liveActivity)
        #expect(queued.invocation.delivery?.widgetOrigin?.identity.variantID == "variant.alpha")
        #expect(queued.invocation.identity.variantID == "default")
    }


    @Test func nativeNodeLiveActivityRecordsItsRealRouteAndRetainsLegacyCompatibility() throws {
        let fixture = try HostActionFixture(engine: .expo)
        defer { fixture.remove() }
        let command = try HanlinWidgetHostActionExecutor.enqueueLiveActivity(
            identity: fixture.target.identity, actionName: "runRuntime",
            parameters: .string("native ActivityKit action"), store: fixture.store)
        #expect(command.invocation.delivery?.source == .liveActivity)
        #expect(command.invocation.delivery?.appID == fixture.appID)
        #expect(command.invocation.delivery?.widgetOrigin == nil)
        #expect(command.invocation.parameters == .string("native ActivityKit action"))
        try HanlinWidgetHostActionExecutor.validateLiveActivityTarget(command, store: fixture.store)
        #expect(throws: HanlinWidgetActionError.undeclaredAction) {
            _ = try HanlinWidgetHostActionExecutor.enqueueLiveActivity(identity: fixture.target.identity,
                actionName: "notDeclared", parameters: .null, store: fixture.store)
        }
        let legacy = HanlinScriptIntentEntityRecord(identity: fixture.target.identity,
            id: "runRuntime", displayName: "Existing registered intent", appID: fixture.appID)
        try fixture.store.save(.init(schemaVersion: 2, generatedAt: .now,
            widgets: [fixture.widget], intentEntities: [legacy], widgetInstances: [fixture.instance]))
        let historical = try HanlinWidgetHostActionExecutor.enqueueLiveActivity(
            identity: legacy.identity, actionName: legacy.id, parameters: .integer(42), store: fixture.store)
        #expect(historical.invocation.delivery == nil)
        #expect(historical.invocation.identity == legacy.identity)
        #expect(historical.invocation.parameters == .integer(42))
        #expect(try fixture.store.receipt(for: historical.id)?.status == .queued)
    }


    @Test func optionalPresentationKeepsRealHandlerButPanelOnlyCannotQueue() throws {
        let fixture = try HostActionFixture(engine: .expo)
        defer { fixture.remove() }
        let presentation = HanlinNativePresentationDescriptor(engine: .expo,
            programRef: "Packages/\(fixture.identity.installedPackageID.rawValue)/generations/\(fixture.identity.generation)/artifacts/\(fixture.digest)",
            programSHA256: fixture.digest)
        let action = HanlinScriptIntentEntityRecord(identity: fixture.target.identity,
            id: fixture.target.id, displayName: "Action with optional presentation",
            appID: fixture.appID, hostActionHandler: "source/action.js", nativePresentation: presentation)
        try fixture.store.save(.init(schemaVersion: 2, generatedAt: .now,
            widgets: [fixture.widget], intentEntities: [action], widgetInstances: [fixture.instance]))
        let widget = try HanlinWidgetHostActionExecutor.enqueue(fixture.command(), store: fixture.store)
        try HanlinWidgetHostActionExecutor.validateCurrentOrigin(widget, store: fixture.store)
        let activity = try HanlinWidgetHostActionExecutor.enqueueLiveActivity(identity: action.identity,
            actionName: action.id, parameters: .null, store: fixture.store)
        try HanlinWidgetHostActionExecutor.validateLiveActivityTarget(activity, store: fixture.store)

        let panelOnly = HanlinScriptIntentEntityRecord(identity: fixture.target.identity,
            id: fixture.target.id, displayName: "Presentation only",
            appID: fixture.appID, nativePresentation: presentation)
        try fixture.store.save(.init(schemaVersion: 2, generatedAt: .now,
            widgets: [fixture.widget], intentEntities: [panelOnly], widgetInstances: [fixture.instance]))
        #expect(throws: HanlinWidgetActionError.undeclaredAction) {
            _ = try HanlinWidgetHostActionExecutor.enqueue(fixture.command(), store: fixture.store)
        }
        #expect(throws: HanlinWidgetActionError.undeclaredAction) {
            _ = try HanlinWidgetHostActionExecutor.enqueueLiveActivity(identity: panelOnly.identity,
                actionName: panelOnly.id, parameters: .null, store: fixture.store)
        }
        #expect(try fixture.store.pendingCommands().count == 2)
    }

    @Test func explicitNonceRetainsReceiptAndRejectsConflictingParameters() async throws {
        let fixture = try HostActionFixture(engine: .expo)
        defer { fixture.remove() }
        let command = fixture.command(nonce: "stable-tap", parameters: .integer(42))
        let first = try HanlinWidgetHostActionExecutor.enqueue(command, store: fixture.store)
        let counter = HostActionCounter()
        let executor = HanlinInvocationExecutor(store: fixture.store)
        let receipt = try await executor.execute(first.id) { command in
            await counter.call()
            return command.invocation.parameters
        }
        #expect(receipt?.status == .succeeded)
        #expect(receipt?.value == .integer(42))
        let again = try HanlinWidgetHostActionExecutor.enqueue(command, store: fixture.store)
        #expect(again == first)
        let completed = try await executor.execute(again.id) { _ in
            await counter.call()
            return .string("must not execute")
        }
        #expect(completed == receipt)
        #expect(await counter.count == 1)
        #expect(throws: HanlinInvocationQueueError.duplicateIdentity) {
            _ = try HanlinWidgetHostActionExecutor.enqueue(
                fixture.command(nonce: "stable-tap", parameters: .integer(99)), store: fixture.store)
        }
        #expect(try fixture.store.receipt(for: first.id) == receipt)
        let one = try HanlinWidgetHostActionExecutor.enqueue(fixture.command(), store: fixture.store)
        let two = try HanlinWidgetHostActionExecutor.enqueue(fixture.command(), store: fixture.store)
        #expect(one.id != two.id)

        // A completed receipt remains readable after disabling and removing the
        // current origin. The same nonce cannot create a fresh execution.
        try fixture.store.update { snapshot in
            try #require(snapshot).replacing(inactiveInstallations: [fixture.identity.installedPackageID.rawValue])
        }
        #expect(try HanlinWidgetHostActionExecutor.enqueue(command, store: fixture.store) == first)
        try fixture.store.save(.init(schemaVersion: 2, generatedAt: .now, widgets: [], intentEntities: []))
        #expect(try HanlinWidgetHostActionExecutor.enqueue(command, store: fixture.store) == first)
        #expect(try fixture.store.receipt(for: first.id) == receipt)
        #expect(throws: HanlinInvocationQueueError.duplicateIdentity) {
            _ = try HanlinWidgetHostActionExecutor.enqueue(fixture.command(nonce: "stable-tap"), store: fixture.store)
        }
        #expect(throws: HanlinInvocationQueueError.duplicateIdentity) {
            _ = try HanlinWidgetHostActionExecutor.enqueue(
                fixture.command(nonce: "stable-tap", parameters: .integer(99)), store: fixture.store)
        }
        let replayed = try await executor.execute(first.id) { _ in
            await counter.call()
            return .string("removed action must not execute")
        }
        #expect(replayed == receipt)
        #expect(await counter.count == 1)
    }

    @Test(arguments: ["disabled", "removedVariant", "staleProgram", "missingTarget", "wrongProduct", "duplicateTarget"])
    func invalidCurrentOriginOrTargetDoesNotEnqueue(reason: String) throws {
        let fixture = try HostActionFixture(engine: .scriptwidget)
        defer { fixture.remove() }
        var entities = [fixture.target]
        var instances = [fixture.instance]
        var inactive: [String] = []
        var context = fixture.context()
        switch reason {
        case "disabled": inactive = [fixture.identity.installedPackageID.rawValue]
        case "removedVariant": instances = []
        case "staleProgram":
            context = .init(identity: fixture.identity, engine: .scriptwidget,
                artifactSHA256: String(repeating: "f", count: 64), family: "systemMedium")
        case "missingTarget": entities = []
        case "wrongProduct":
            entities = [.init(identity: .init(installedPackageID: try .init(validating: "installed.other"),
                packageID: fixture.identity.packageID, generation: 1, entrypointID: "intent.runtime"),
                id: "runRuntime", displayName: "Other", appID: fixture.appID, hostActionHandler: "source/action.js")]
        case "duplicateTarget": entities.append(fixture.target)
        default: Issue.record("Unknown negative case")
        }
        try fixture.store.save(.init(schemaVersion: 2, generatedAt: .now, widgets: [fixture.widget],
            intentEntities: entities, widgetInstances: instances, inactiveWidgetInstallations: inactive))
        #expect(throws: HanlinWidgetActionError.self) {
            _ = try HanlinWidgetHostActionExecutor.enqueue(.init(context: context, actionID: "run"),
                                                            store: fixture.store)
        }
        #expect(try fixture.store.pendingCommands().isEmpty)
    }

    @Test func queuedOriginIsRevalidatedAfterDisableAndCancellationDoesNotExecute() async throws {
        let fixture = try HostActionFixture(engine: .expo)
        defer { fixture.remove() }
        let queued = try HanlinWidgetHostActionExecutor.enqueue(fixture.command(), store: fixture.store)
        try fixture.store.update { snapshot in
            try #require(snapshot).replacing(inactiveInstallations: [fixture.identity.installedPackageID.rawValue])
        }
        #expect(throws: HanlinInvocationDispatchError.self) {
            try HanlinWidgetHostActionExecutor.validateCurrentOrigin(queued, store: fixture.store)
        }
        _ = try fixture.store.requestCancellation(queued.id)
        let counter = HostActionCounter()
        let receipt = try await HanlinInvocationExecutor(store: fixture.store).execute(queued.id) { _ in
            await counter.call()
            return .null
        }
        #expect(receipt?.status == .cancelled)
        #expect(await counter.count == 0)
    }


    @Test @MainActor func continuationUsesCanonicalStoreRootBeforeAndAfterCreation() async throws {
        let parent = FileManager.default.temporaryDirectory.appending(path: "hanlin-host-root-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appending(path: "ScriptingExtensions", directoryHint: .isDirectory)
        let store = HanlinScriptExtensionStore(root: root)
        #expect(!FileManager.default.fileExists(atPath: store.root.path(percentEncoded: false)))
        let owner = NSObject()
        let counter = HostActionCounter()
        let executor = HanlinInvocationExecutor(store: store)
        HanlinWidgetHostActionContinuation.register(owner: owner, storeRoot: store.root) {
            for command in (try? store.pendingCommands()) ?? [] {
                _ = try? await executor.execute(command.id) { command in
                    await counter.call()
                    return command.invocation.parameters
                }
            }
        }
        let identity = HanlinScriptExtensionIdentity(
            installedPackageID: try .init(validating: "installed.cold-root"),
            packageID: try .init(validating: "package.cold-root"), generation: 1,
            entrypointID: "intent.runtime")
        let command = HanlinScriptResumeCommand(invocation: .init(identity: identity,
            entityID: "runRuntime", parameters: .integer(42), continueInForeground: true))
        try store.enqueue(command)
        let afterCreation = HanlinScriptExtensionStore(root: root)
        #expect(afterCreation.root == store.root)
        let otherProduct = HanlinScriptExtensionStore(root: parent.appending(path: "OtherProduct"))
        await HanlinWidgetHostActionContinuation.resume(storeRoot: otherProduct.root)
        #expect(await counter.count == 0)
        await HanlinWidgetHostActionContinuation.resume(storeRoot: afterCreation.root)
        #expect(try store.receipt(for: command.id)?.status == .succeeded)
        #expect(try store.receipt(for: command.id)?.value == .integer(42))
        #expect(await counter.count == 1)
        withExtendedLifetime(owner) {}
    }

    @Test @MainActor func activationBeforeEnqueueUsesExistingDrainAndMissingHostKeepsQueue() async throws {
        let fixture = try HostActionFixture(engine: .expo)
        defer { fixture.remove() }
        let executor = HanlinInvocationExecutor(store: fixture.store)
        let counter = HostActionCounter()
        var owner: NSObject? = NSObject()
        HanlinWidgetHostActionContinuation.register(owner: try #require(owner), storeRoot: fixture.store.root) {
            for command in (try? fixture.store.pendingCommands()) ?? [] {
                _ = try? await executor.execute(command.id) { command in
                    await counter.call()
                    return command.invocation.parameters
                }
            }
        }
        // This is the actual foreground-before-perform ordering of the new intent.
        await HanlinWidgetHostActionContinuation.resume(storeRoot: fixture.store.root)
        #expect(await counter.count == 0)
        let first = try HanlinWidgetHostActionExecutor.enqueue(
            fixture.command(parameters: .string("actual canonical drain")), store: fixture.store)
        await HanlinWidgetHostActionContinuation.resume(storeRoot: fixture.store.root)
        #expect(try fixture.store.receipt(for: first.id)?.value == .string("actual canonical drain"))
        #expect(try fixture.store.receipt(for: first.id)?.status == .succeeded)
        #expect(await counter.count == 1)
        owner = nil
        let second = try HanlinWidgetHostActionExecutor.enqueue(fixture.command(), store: fixture.store)
        await HanlinWidgetHostActionContinuation.resume(storeRoot: fixture.store.root)
        #expect(try fixture.store.receipt(for: second.id)?.status == .queued)
        #expect(try fixture.store.receipt(for: second.id)?.value == nil)
        #expect(await counter.count == 1)
    }
}

private actor HostActionCounter {
    private(set) var count = 0
    func call() { count += 1 }
}

private struct HostActionFixture: Sendable {
    let root: URL
    let store: HanlinScriptExtensionStore
    let identity: HanlinScriptExtensionIdentity
    let appID: HanlinAppID
    let engine: HanlinWidgetEngine
    let digest: String
    let widget: HanlinScriptWidgetSnapshot
    let instance: HanlinWidgetInstance
    let target: HanlinScriptIntentEntityRecord

    init(engine: HanlinWidgetEngine, parameters: HanlinJSONValue? = nil) throws {
        root = FileManager.default.temporaryDirectory.appending(path: "hanlin-host-widget-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = HanlinScriptExtensionStore(root: root)
        self.engine = engine
        appID = try .init(validating: "hanlin.widget.host-action")
        identity = .init(installedPackageID: try .init(validating: "installed.host-widget"),
            packageID: try .init(validating: "package.host-widget"), generation: 1,
            entrypointID: "widget.main", variantID: "variant.alpha")
        let program = HanlinWidgetProgram(engine: engine, sourceSHA256: String(repeating: "a", count: 64),
            compilerSHA256: String(repeating: "b", count: 64), javaScript: "void 0;",
            actions: [.init(id: "run", kind: .hostAction,
                hostAction: .init(entrypointID: "intent.runtime", actionName: "runRuntime", parameters: parameters))],
            families: ["systemMedium"])
        try program.validate(engine: engine)
        let artifact = try store.storeArtifact(data: JSONEncoder().encode(program),
            installedPackageID: identity.installedPackageID, generation: identity.generation)
        digest = artifact.sha256
        let payload: HanlinWidgetPayload = engine == .expo
            ? .expo(.init(layout: "", layoutRef: artifact.ref, layoutSHA256: artifact.sha256))
            : .scriptwidget(.init(script: "", scriptRef: artifact.ref, scriptSHA256: artifact.sha256))
        widget = .init(identity: identity, displayName: "Host widget", family: "systemMedium",
            validUntil: .distantFuture, engine: engine, payload: payload, root: .init(kind: .text))
        instance = .init(identity: identity, engine: engine, displayName: "Alpha")
        target = .init(identity: .init(installedPackageID: identity.installedPackageID,
            packageID: identity.packageID, generation: identity.generation, entrypointID: "intent.runtime"),
            id: "runRuntime", displayName: "Run runtime", appID: appID, hostActionHandler: "source/action.js")
        try store.save(.init(schemaVersion: 2, generatedAt: .now, widgets: [widget],
            intentEntities: [target], widgetInstances: [instance]))
    }

    func context(liveActivity: Bool = false) -> HanlinWidgetActionContext {
        .init(identity: identity, engine: engine, artifactSHA256: digest, family: "systemMedium",
              environment: liveActivity ? ["liveActivity": .bool(true)] : [:])
    }

    func command(nonce: String = "", liveActivity: Bool = false,
                 parameters: HanlinValue? = nil) -> HanlinWidgetActionCommand {
        .init(context: context(liveActivity: liveActivity), actionID: "run", nonce: nonce, parameters: parameters)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
