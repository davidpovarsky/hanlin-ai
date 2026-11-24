import Foundation
import XCTest
import HanlinPlatformContracts
import HanlinMiniAppCore
@testable import HanlinMiniApps

@MainActor
final class NativeScriptHostServicesLifetimeTests: XCTestCase {
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
