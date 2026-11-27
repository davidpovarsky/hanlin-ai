import Foundation
import Observation

public struct PresentationMessageIdentity: Codable, Hashable, Sendable {
    public let appID: String
    public let conversationID: UUID
    public let messageID: UUID
    public init(appID: String, conversationID: UUID, messageID: UUID) {
        self.appID = appID; self.conversationID = conversationID; self.messageID = messageID
    }
}

public struct MessagePresentationSnapshot: Codable, Hashable, Sendable {
    public let identity: PresentationMessageIdentity
    public var profile: ResolvedPresentationProfile
    public var values: [String: PresentationValue]
    public var expandedActivityIDs: Set<String>
    public var activityDisclosure: HanlinActivityDisclosureState?
    public init(identity: PresentationMessageIdentity, profile: ResolvedPresentationProfile,
                values: [String: PresentationValue] = [:], expandedActivityIDs: Set<String> = [],
                activityDisclosure: HanlinActivityDisclosureState? = nil) {
        self.identity = identity; self.profile = profile; self.values = values
        self.expandedActivityIDs = expandedActivityIDs
        self.activityDisclosure = activityDisclosure
    }
}

/// The host owns exactly one instance per message, shared by every React and native
/// block. Hosts persist `snapshot` in their existing message store. No singleton,
/// separate chat database, network call or engine is introduced by presentation.
@MainActor @Observable
public final class MessageOpenUIStateStore {
    public let identity: PresentationMessageIdentity
    public let profile: ResolvedPresentationProfile
    public private(set) var values: [String: PresentationValue]
    public private(set) var expandedActivityIDs: Set<String>
    public private(set) var activityDisclosure: HanlinActivityDisclosureState?
    public private(set) var revision: UInt64 = 0
    @ObservationIgnored public var onChange: (@MainActor (MessagePresentationSnapshot) -> Void)?

    public init(snapshot: MessagePresentationSnapshot) {
        self.identity = snapshot.identity; self.profile = snapshot.profile
        self.values = snapshot.values; self.expandedActivityIDs = snapshot.expandedActivityIDs
        self.activityDisclosure = snapshot.activityDisclosure
    }
    public var snapshot: MessagePresentationSnapshot {
        .init(identity: identity, profile: profile, values: values, expandedActivityIDs: expandedActivityIDs,
              activityDisclosure: activityDisclosure)
    }

    /// Runtime field changes are deltas against the same message's raw state map.
    /// Preserve values owned by sibling blocks when an upstream renderer reports
    /// only the fields it has mounted. Exact equal updates do not echo forever.
    public func merge(_ updates: [String: PresentationValue]) {
        let merged = values.merging(updates) { _, new in new }
        guard merged != values else { return }
        values = merged; changed()
    }
    public func set(_ value: PresentationValue, for key: String) { merge([key: value]) }
    /// Apply only fields changed by this renderer. A delayed sibling snapshot must
    /// not roll back a more recent edit in another block. $variables are atomic;
    /// ordinary form maps merge their independently changed fields.
    public func mergeRendererState(_ next: [String: PresentationValue], previous: [String: PresentationValue]) {
        var updates: [String: PresentationValue] = [:]
        for (key, value) in next where value != previous[key] {
            if !key.hasPrefix("$"), let fields = value.object, fields["componentType"] == nil {
                let oldFields = previous[key]?.object ?? [:]
                var currentFields = values[key]?.object ?? [:]
                for (field, fieldValue) in fields where fieldValue != oldFields[field] {
                    currentFields[field] = fieldValue
                }
                updates[key] = .object(currentFields)
            } else { updates[key] = value }
        }
        merge(updates)
    }
    public func setExpanded(_ expanded: Bool, activityID: String) {
        let wasExpanded = expandedActivityIDs.contains(activityID)
        guard expanded != wasExpanded else { return }
        if expanded { expandedActivityIDs.insert(activityID) }
        else { expandedActivityIDs.remove(activityID) }
        changed()
    }
    public func setActivityDisclosure(_ value: HanlinActivityDisclosureState) {
        guard activityDisclosure != value else { return }
        activityDisclosure = value
        changed()
    }
    private func changed() { revision &+= 1; onChange?(snapshot) }
}

public struct MessageRichPart: Codable, Hashable, Sendable, Identifiable {
    public enum Payload: Codable, Hashable, Sendable {
        case markdown(String)
        case openUI(program: String, target: OpenUIRenderTarget)
    }
    public let id: String
    public let identity: PresentationMessageIdentity
    public let streamOrder: Int
    public let catalogVersions: [PresentationReference]
    public let payload: Payload
    public let isComplete: Bool
    public init(id: String, identity: PresentationMessageIdentity, streamOrder: Int,
                catalogVersions: [PresentationReference], payload: Payload, isComplete: Bool) {
        self.id = id; self.identity = identity; self.streamOrder = streamOrder
        self.catalogVersions = catalogVersions; self.payload = payload; self.isComplete = isComplete
    }
}

/// A UI event returns to the host with its originating message and part. The host
/// resolves its existing live session and permission broker; this object has none.
public struct PresentationAction: Codable, Hashable, Sendable {
    public let identity: PresentationMessageIdentity
    public let partID: String
    public let name: String
    public let parameters: [String: PresentationValue]
    public init(identity: PresentationMessageIdentity, partID: String, name: String,
                parameters: [String: PresentationValue]) {
        self.identity = identity; self.partID = partID; self.name = name; self.parameters = parameters
    }
}

@MainActor
public protocol HanlinPresentationHost: AnyObject {
    var presentationDescriptor: HostPresentationDescriptor { get }
    func performPresentationAction(_ action: PresentationAction) async throws -> PresentationValue
    func openPresentationDestination(_ destination: String, origin: PresentationMessageIdentity) async throws
}
