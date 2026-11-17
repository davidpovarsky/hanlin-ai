import Foundation
import Testing
@testable import HanlinPresentationKit

private func host(app: String = "hanlin", version: Int = 1,
                  targets: Set<OpenUIRenderTarget> = [.react, .swiftui]) -> HostPresentationDescriptor {
    let catalog = ComponentCatalogDescriptor(reference: .init("test.catalog", version: version),
        renderTargets: [.react, .swiftui], componentNames: ["Text", "Slider"], modelInstructions: "catalog v\(version)")
    let profile = PresentationProfile(id: "standard", version: version, shellID: "standard",
        catalogIDs: [catalog.reference], capabilities: ["read", "write"])
    return .init(appID: app, defaultProfile: profile.reference, availableProfiles: [profile],
        catalogProviders: [catalog], shells: [.init(id: "standard", title: "Standard")],
        hostCapabilities: ["read"], renderTargets: targets)
}

@Test func hostCapabilitiesBoundModelPresentation() throws {
    let value = try ProfileResolver.resolve(host: host(targets: [.swiftui]), conversationID: UUID())
    #expect(value.capabilities == ["read"])
    #expect(value.renderTargets == [.swiftui])
}

@Test func conversationAssignmentCannotCrossConversation() throws {
    let assignment = ConversationPresentationAssignment(conversationID: UUID(), profile: .init("standard"))
    #expect(throws: PresentationResolutionError.conversationMismatch) {
        try ProfileResolver.resolve(host: host(), conversationID: UUID(), assignment: assignment)
    }
}

@Test func previousCatalogVersionSurvivesNewConversationProfile() throws {
    let conversationID = UUID()
    let original = try ProfileResolver.resolve(host: host(), conversationID: conversationID)
    let bytes = try JSONEncoder().encode(original)
    let next = try ProfileResolver.resolve(host: host(version: 2), conversationID: conversationID)
    let restored = try JSONDecoder().decode(ResolvedPresentationProfile.self, from: bytes)
    #expect(next.profile.version == 2)
    #expect(restored.profile.version == 1)
    #expect(restored.catalogs.first?.modelInstructions == "catalog v1")
}

@Test func unknownProfileDoesNotSilentlyChangeTheConversation() throws {
    let id = UUID()
    #expect(throws: PresentationResolutionError.profileUnavailable) {
        try ProfileResolver.resolve(host: host(), conversationID: id,
            assignment: .init(conversationID: id, profile: .init("other-host-profile")))
    }
}

@MainActor @Test func bothRenderersShareStateWithoutFeedbackOrSiblingDataLoss() throws {
    let conversationID = UUID()
    let profile = try ProfileResolver.resolve(host: host(), conversationID: conversationID)
    let store = MessageOpenUIStateStore(snapshot: .init(
        identity: .init(appID: "hanlin", conversationID: conversationID, messageID: UUID()), profile: profile))
    var observed: [MessagePresentationSnapshot] = []
    store.onChange = { observed.append($0) }
    store.merge(["budget": .number(1200)]) // original React onStateUpdate
    store.set(.number(3), for: "nights") // native control
    store.merge(["budget": .number(1200)]) // identical bridge echo
    #expect(store.values == ["budget": .number(1200), "nights": .number(3)])
    #expect(observed.count == 2)
    let restored = try JSONDecoder().decode(MessagePresentationSnapshot.self,
        from: JSONEncoder().encode(store.snapshot))
    #expect(restored.values == store.values)
}

@MainActor @Test func messageAndHostStateAreIsolated() throws {
    let conversationID = UUID()
    let profile = try ProfileResolver.resolve(host: host(), conversationID: conversationID)
    let one = MessageOpenUIStateStore(snapshot: .init(
        identity: .init(appID: "hanlin", conversationID: conversationID, messageID: UUID()), profile: profile))
    let two = MessageOpenUIStateStore(snapshot: .init(
        identity: .init(appID: "torah-fixture", conversationID: conversationID, messageID: UUID()), profile: profile))
    one.set(.string("private input"), for: "query")
    #expect(two.values.isEmpty)
    #expect(one.identity != two.identity)
}

@MainActor @Test func detailsRemainClosedUntilTheUserExpandsThem() throws {
    let id = UUID()
    let store = MessageOpenUIStateStore(snapshot: .init(
        identity: .init(appID: "hanlin", conversationID: id, messageID: UUID()),
        profile: try ProfileResolver.resolve(host: host(), conversationID: id)))
    #expect(store.expandedActivityIDs.isEmpty)
    store.setExpanded(true, activityID: "run-1/call-2")
    store.merge(["result": .string("completed")])
    #expect(store.snapshot.expandedActivityIDs == ["run-1/call-2"])
    store.setExpanded(false, activityID: "run-1/call-2")
    #expect(store.expandedActivityIDs.isEmpty)
}

@Test func plainJSONStatePreservesBooleanAndNumberTypes() throws {
    let value = try JSONDecoder().decode(PresentationValue.self, from: Data(#"{"enabled":true,"count":1,"items":[null,"x"]}"#.utf8))
    #expect(value.object?["enabled"] == .bool(true))
    #expect(value.object?["count"] == .number(1))
    #expect(try JSONDecoder().decode(PresentationValue.self, from: JSONEncoder().encode(value)) == value)
}
