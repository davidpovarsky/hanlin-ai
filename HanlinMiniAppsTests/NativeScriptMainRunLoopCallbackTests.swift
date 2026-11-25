import Foundation
import HanlinNativeScriptCoreSupport
import XCTest

/// Uses the original Objective-C session bridge with a controlled native provider.
/// This isolates callback scheduling; real engine/UI acceptance remains separate.
@MainActor
final class NativeScriptMainRunLoopCallbackTests: XCTestCase {
    func testBackgroundCompletionReentersRunLoopInsideMainQueueSynchronousCall() throws {
        let provider = RunLoopNativeServicesProvider()
        let (sessionID, bridge) = try bind(provider)
        defer { HanlinNativeServicesBridge.unregisterProvider(forSessionID: sessionID) }
        HanlinNativeServicesBridge.setActiveSession(bridge, forSessionID: sessionID)
        let finished = expectation(description: "Original synchronous bridge returned")
        DispatchQueue.main.async {
            XCTAssertTrue(Thread.isMainThread)
            let started = Date()
            let result = HanlinNativeServicesBridge.executeJavaScriptSync("native-result")
            XCTAssertEqual(result, "native-result")
            XCTAssertLessThan(Date().timeIntervalSince(started), 2,
                "An already-completed native operation must not wait for the original 20-second bridge timeout.")
            finished.fulfill()
        }
        wait(for: [finished], timeout: 25)
    }

    func testAsynchronousBackgroundCompletionStillRunsOnMainThread() throws {
        let provider = RunLoopNativeServicesProvider()
        let (sessionID, bridge) = try bind(provider)
        defer { HanlinNativeServicesBridge.unregisterProvider(forSessionID: sessionID) }
        let delivered = expectation(description: "Async native completion")
        bridge.executeJavaScript("async-result") { result, error in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(result, "async-result")
            XCTAssertNil(error)
            delivered.fulfill()
        }
        wait(for: [delivered], timeout: 2)
    }

    func testQueuedBackgroundResultLosesJSCompletionBeforeSessionInvalidationReturns() throws {
        let provider = RunLoopNativeServicesProvider()
        provider.automaticallyReplies = false
        let (sessionID, bridge) = try bind(provider)
        defer { HanlinNativeServicesBridge.unregisterProvider(forSessionID: sessionID) }
        let mustNotRun = expectation(description: "Closed-session callback")
        mustNotRun.isInverted = true
        weak var captured: RunLoopCallbackCapture?
        autoreleasepool {
            let token = RunLoopCallbackCapture()
            captured = token
            bridge.executeJavaScript("late-result") { [token] _, _ in
                _ = token
                mustNotRun.fulfill()
            }
        }
        XCTAssertNotNil(captured)
        let queued = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            provider.deliverRetained()
            queued.signal()
        }
        // Do not pump the main run loop until the native result has been queued
        // and session invalidation has synchronously detached the JS closure.
        XCTAssertEqual(queued.wait(timeout: .now() + 2), .success)
        bridge.invalidate()
        XCTAssertNil(captured)
        XCTAssertEqual(provider.invalidationCount, 1)
        wait(for: [mustNotRun], timeout: 0.15)
    }

    private func bind(_ provider: RunLoopNativeServicesProvider) throws -> (String, HanlinNativeServicesSessionBridge) {
        let sessionID = UUID().uuidString.lowercased()
        HanlinNativeServicesBridge.register(provider, forSessionID: sessionID)
        let token = try XCTUnwrap(HanlinNativeServicesPrepareSessionBootstrap(sessionID))
        return (sessionID, try XCTUnwrap(HanlinNativeServicesBridge.claimSessionBridge(withToken: token)))
    }
}

private final class RunLoopCallbackCapture: Sendable {}

private final class RunLoopNativeServicesProvider: NSObject, @unchecked Sendable, HanlinNativeServicesProvider {
    private let lock = NSLock()
    private var retained: [(String?, String?) -> Void] = []
    var automaticallyReplies = true
    private(set) var invalidationCount = 0

    func deliverRetained() {
        let callbacks = lock.withLock { retained }
        for completion in callbacks { completion("late-result", nil) }
    }

    func executeJavaScript(_ source: String, completion: @escaping (String?, String?) -> Void) {
        if automaticallyReplies {
            nonisolated(unsafe) let nativeCompletion = completion
            DispatchQueue.global(qos: .userInitiated).async {
                nativeCompletion(source, nil)
            }
        } else {
            lock.withLock { retained.append(completion) }
        }
    }

    func executeRuntime(_ payloadJSON: String, completion: @escaping (String?, String?) -> Void) -> String? {
        executeJavaScript(payloadJSON, completion: completion)
        return "native-request"
    }
    func cancelRuntime(_ requestID: String) -> Bool { false }
    func invalidateRuntimeRequests() { invalidationCount += 1 }
    func dataRootDirectory() -> String? { nil }
    func stateDirectory() -> String? { nil }
    func documentsDirectory() -> String? { nil }
    func cacheDirectory() -> String? { nil }
    func executeNode(_ source: String, completion: @escaping (String?, String?) -> Void) {
        executeJavaScript(source, completion: completion)
    }
    func nodeHealthCheck(completion: @escaping (Bool, String?) -> Void) { completion(true, nil) }
    func executePython(_ source: String, completion: @escaping (String?, String?) -> Void) {
        executeJavaScript(source, completion: completion)
    }
    func pythonVersion() -> String? { nil }
    func fetchURL(_ urlString: String, completion: @escaping (String?, String?) -> Void) {
        executeJavaScript(urlString, completion: completion)
    }
    func sendRequest(_ targetID: String, action: String, capability: String, payloadJSON: String,
                     completion: @escaping (String?, String?) -> Void) {
        executeJavaScript(payloadJSON, completion: completion)
    }
    func registerRequestHandler(_ action: String, capability: String,
                                handler: @escaping (String, String, @escaping (String?, String?) -> Void) -> Void) {}
}
