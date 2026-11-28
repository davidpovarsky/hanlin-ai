import Foundation
import XCTest
import HanlinPlatformContracts
import HanlinMiniAppCore
import HanlinNativeScriptCoreSupport
@testable import HanlinMiniApps

@MainActor
final class NativeScriptHostServicesLifetimeTests: XCTestCase {
    func testBridgeInvalidationReleasesPendingCallbacksBeforeProviderCancellation() throws {
        let sessionID = UUID().uuidString.lowercased()
        let provider = DeferredNativeServicesProvider()
        HanlinNativeServicesBridge.register(provider, forSessionID: sessionID)
        defer { HanlinNativeServicesBridge.unregisterProvider(forSessionID: sessionID) }
        let token = try XCTUnwrap(HanlinNativeServicesPrepareSessionBootstrap(sessionID))
        let firstBridge = try XCTUnwrap(HanlinNativeServicesBridge.claimSessionBridge(withToken: token))
        let secondToken = try XCTUnwrap(HanlinNativeServicesPrepareSessionBootstrap(sessionID))
        let secondBridge = try XCTUnwrap(HanlinNativeServicesBridge.claimSessionBridge(withToken: secondToken))
        let invocations = NSMutableArray()
        var captures: [WeakHandlerCapture] = []
        func stringCompletion() -> (String?, String?) -> Void {
            let capture = NSObject()
            captures.append(WeakHandlerCapture(capture))
            return { _, _ in invocations.add(capture) }
        }

        autoreleasepool {
            for bridge in [firstBridge, secondBridge] {
                XCTAssertNotNil(bridge.executeRuntime("{}", completion: stringCompletion()))
                bridge.executeJavaScript("1", completion: stringCompletion())
                bridge.executeNode("1", completion: stringCompletion())
                bridge.executePython("1", completion: stringCompletion())
                bridge.fetchURL("https://example.invalid", completion: stringCompletion())
                bridge.sendRequest("fixture", action: "echo", capability: "network",
                                   payloadJSON: "{}", completion: stringCompletion())
                let capture = NSObject()
                captures.append(WeakHandlerCapture(capture))
                bridge.nodeHealthCheck { _, _ in invocations.add(capture) }
            }
        }
        XCTAssertEqual(provider.pendingCount, 14)
        XCTAssertEqual(captures.count, 14)
        XCTAssertTrue(captures.allSatisfy { $0.value != nil })

        // The provider deliberately calls every native completion synchronously
        // during cancellation, and retains them afterward to emulate late work.
        firstBridge.invalidate()
        XCTAssertEqual(provider.invalidationCount, 1)
        XCTAssertTrue(captures.allSatisfy { $0.value == nil },
                      "No native pending operation may retain a JS completion after bridge invalidation.")
        XCTAssertEqual(invocations.count, 0,
                       "JS callbacks must be detached before cancellation can synchronously complete work.")

        provider.deliverRetainedCompletions()
        XCTAssertEqual(invocations.count, 0, "A late completion must not invoke a closed session's JS.")
        XCTAssertTrue(captures.allSatisfy { $0.value == nil })
    }

    func testInvalidationReleasesHandlersAndRejectsLateActions() async throws {
        let appID = try HanlinAppID(validating: "hanlin.nativescript.handler-lifetime")
        let action = try HanlinActionID(validating: "echo")
        let lateAction = try HanlinActionID(validating: "late-echo")
        let capability = try HanlinCapabilityID(validating: "network")
        let adapter = NativeScriptHostServicesAdapter(
            appID: appID, grantedCapabilities: [capability.rawValue])
        let invocations = NSMutableArray()
        weak var retainedHandlerCapture: NSObject?

        do {
            let capture = NSObject()
            retainedHandlerCapture = capture
            adapter.registerRequestHandler(action.rawValue, capability: capability.rawValue) {
                _, _, completion in
                invocations.add(capture)
                completion("{}", nil)
            }
        }
        XCTAssertNotNil(retainedHandlerCapture)
        XCTAssertTrue(adapter.hasRegisteredAction(action))
        XCTAssertEqual(adapter.allRegisteredActionIDs, [action])

        adapter.invalidateRuntimeRequests()
        XCTAssertNil(retainedHandlerCapture, "The closed session must release its JS handler captures before VM teardown.")
        XCTAssertFalse(adapter.hasRegisteredAction(action))
        XCTAssertTrue(adapter.allRegisteredActionIDs.isEmpty)

        weak var rejectedHandlerCapture: NSObject?
        do {
            let capture = NSObject()
            rejectedHandlerCapture = capture
            adapter.registerRequestHandler(lateAction.rawValue, capability: capability.rawValue) {
                _, _, completion in
                invocations.add(capture)
                completion("{}", nil)
            }
        }
        XCTAssertNil(rejectedHandlerCapture, "A late registration must not retain a callback in an invalidated adapter.")
        XCTAssertTrue(adapter.allRegisteredActionIDs.isEmpty)
        for candidate in [action, lateAction] {
            do {
                _ = try await adapter.invokeRegisteredAction(
                    candidate, capability: capability, caller: appID, payload: .object([:]))
                XCTFail("An invalidated session invoked a registered NativeScript action.")
            } catch {
                XCTAssertEqual(error as? HanlinMiniAppRequestError, .routeNotFound)
            }
        }
        XCTAssertEqual(invocations.count, 0)
        adapter.invalidateRuntimeRequests()
        XCTAssertTrue(adapter.allRegisteredActionIDs.isEmpty)
    }
}


private final class WeakHandlerCapture {
    weak var value: NSObject?
    init(_ value: NSObject) { self.value = value }
}

private final class DeferredNativeServicesProvider: NSObject, @unchecked Sendable, HanlinNativeServicesProvider {
    private let lock = NSLock()
    private var strings: [(String?, String?) -> Void] = []
    private var bools: [(Bool, String?) -> Void] = []
    private var invalidations = 0

    var pendingCount: Int { lock.withLock { strings.count + bools.count } }
    var invalidationCount: Int { lock.withLock { invalidations } }
    private func holdCompletion(_ completion: @escaping (String?, String?) -> Void) {
        lock.withLock { strings.append(completion) }
    }
    func deliverRetainedCompletions() {
        let callbacks = lock.withLock { (strings, bools) }
        for completion in callbacks.0 { completion("late-native-result", nil) }
        for completion in callbacks.1 { completion(true, nil) }
    }
    func executeRuntime(_ payloadJSON: String, completion: @escaping (String?, String?) -> Void) -> String? {
        holdCompletion(completion)
        return "retained-native-runtime-request"
    }
    func cancelRuntime(_ requestID: String) -> Bool { true }
    func invalidateRuntimeRequests() {
        lock.withLock { invalidations += 1 }
        deliverRetainedCompletions()
    }
    func dataRootDirectory() -> String? { nil }
    func stateDirectory() -> String? { nil }
    func documentsDirectory() -> String? { nil }
    func cacheDirectory() -> String? { nil }
    func executeJavaScript(_ source: String, completion: @escaping (String?, String?) -> Void) { holdCompletion(completion) }
    func executeNode(_ source: String, completion: @escaping (String?, String?) -> Void) { holdCompletion(completion) }
    func nodeHealthCheck(completion: @escaping (Bool, String?) -> Void) {
        lock.withLock { bools.append(completion) }
    }
    func executePython(_ source: String, completion: @escaping (String?, String?) -> Void) { holdCompletion(completion) }
    func pythonVersion() -> String? { nil }
    func fetchURL(_ urlString: String, completion: @escaping (String?, String?) -> Void) { holdCompletion(completion) }
    func sendRequest(_ targetID: String, action: String, capability: String,
                     payloadJSON: String, completion: @escaping (String?, String?) -> Void) { holdCompletion(completion) }
    func registerRequestHandler(_ action: String, capability: String,
                                handler: @escaping (String, String, @escaping (String?, String?) -> Void) -> Void) {}
}
