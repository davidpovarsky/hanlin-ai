import HanlinPlatformContracts
import Testing
@testable import HanlinMiniAppCore

@Suite struct HanlinMiniAppAuthorizationPolicyTests {
    @Test func unknownHostTargetIsDenied() async throws {
        let policy = HanlinMiniAppAuthorizationPolicy()
        let request = HanlinMiniAppRequest(
            caller: try HanlinAppID(validating: "hanlin.host"),
            target: try HanlinAppID(validating: "nativeapp.missing"),
            action: try HanlinActionID(validating: "share.value"),
            capability: try HanlinCapabilityID(validating: "inter-app.share"), payload: .null)
        #expect(await !policy.authorize(request))
    }

    @Test func unknownPeerCannotAuthorizeItself() async throws {
        let policy = HanlinMiniAppAuthorizationPolicy()
        let app = try HanlinAppID(validating: "nativeapp.peer")
        #expect(await !policy.authorize(HanlinMiniAppRequest(
            caller: app, target: app,
            action: try HanlinActionID(validating: "share.value"),
            capability: try HanlinCapabilityID(validating: "inter-app.share"), payload: .null)))
    }
}
