import Foundation

/// A capability explicitly selected for one message, independently of the
/// provider's catalog visibility. Selection never executes the capability.
public enum HanlinCapabilityKind: String, Codable, CaseIterable, Hashable, Sendable {
    case tool, miniApp, skill, mcp
}

/// Provider-scoped identity. A display title is never used for dispatch.
/// For installed MiniApps, sourceID is the installed package ID,
/// capabilityID is the assistantTool entrypoint ID, and revision is its generation.
public struct HanlinCapabilityReference: Codable, Hashable, Sendable, Identifiable {
    public var kind: HanlinCapabilityKind
    public var sourceID: String
    public var capabilityID: String
    public var revision: String?

    public init(kind: HanlinCapabilityKind, sourceID: String, capabilityID: String, revision: String? = nil) {
        self.kind = kind
        self.sourceID = sourceID
        self.capabilityID = capabilityID
        self.revision = revision
    }

    /// Length-prefixed components preserve identity even when names contain separators.
    public var id: String {
        [kind.rawValue, sourceID, capabilityID].map { "\($0.utf8.count):\($0)" }.joined()
    }
}

/// A value snapshot attached to a draft and copied into a sent message.
/// Editing a later draft cannot change the configuration of an earlier request.
public struct HanlinCapabilityAttachment: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var reference: HanlinCapabilityReference
    public var title: String
    public var actionID: String?
    public var configuration: HanlinJSONValue
    public var configurationVersion: Int

    public init(
        id: UUID = UUID(),
        reference: HanlinCapabilityReference,
        title: String,
        actionID: String? = nil,
        configuration: HanlinJSONValue = .object([:]),
        configurationVersion: Int = 1
    ) {
        self.id = id
        self.reference = reference
        self.title = title
        self.actionID = actionID
        self.configuration = configuration
        self.configurationVersion = configurationVersion
    }

    public var selectionKey: String {
        let action = actionID ?? ""
        return reference.id + "\(action.utf8.count):\(action)"
    }

    public func value(forKey key: String) -> HanlinJSONValue? {
        guard case let .object(values) = configuration else { return nil }
        return values[key]
    }

    public mutating func setValue(_ value: HanlinJSONValue?, forKey key: String) {
        guard case var .object(values) = configuration else { return }
        values[key] = value
        configuration = .object(values)
    }

    private enum CodingKeys: String, CodingKey {
        case id, reference, title, actionID, configuration, configurationVersion
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        reference = try values.decode(HanlinCapabilityReference.self, forKey: .reference)
        title = try values.decode(String.self, forKey: .title)
        actionID = try values.decodeIfPresent(String.self, forKey: .actionID)
        configuration = try values.decodeIfPresent(HanlinJSONValue.self, forKey: .configuration) ?? .object([:])
        configurationVersion = try values.decodeIfPresent(Int.self, forKey: .configurationVersion) ?? 1
    }
}

public struct HanlinComposerAction: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var summary: String

    public init(id: String, title: String, summary: String = "") {
        self.id = id
        self.title = title
        self.summary = summary
    }
}

/// Shared catalog data for picker, mentions, slash commands and embedded hosts.
/// Runtime aliases are resolved from reference/actionID by the live host.
public struct HanlinComposerCapabilityDescriptor: Codable, Hashable, Sendable, Identifiable {
    public var reference: HanlinCapabilityReference
    public var title: String
    public var summary: String
    public var systemImage: String
    public var actions: [HanlinComposerAction]
    public var configuration: HanlinComposerConfiguration?

    public var id: String { reference.id }

    public init(
        reference: HanlinCapabilityReference,
        title: String,
        summary: String = "",
        systemImage: String = "wrench",
        actions: [HanlinComposerAction] = [],
        configuration: HanlinComposerConfiguration? = nil
    ) {
        self.reference = reference
        self.title = title
        self.summary = summary
        self.systemImage = systemImage
        self.actions = actions
        self.configuration = configuration
    }

    public func makeAttachment(actionID: String? = nil) -> HanlinCapabilityAttachment {
        .init(reference: reference, title: title, actionID: actionID,
              configuration: configuration?.defaultValues ?? .object([:]),
              configurationVersion: configuration?.schemaVersion ?? 1)
    }

    public func validationIssues(for attachment: HanlinCapabilityAttachment) -> [HanlinComposerValidationIssue] {
        var issues: [HanlinComposerValidationIssue] = []
        if attachment.reference != reference {
            issues.append(.init(key: "reference", message: "This capability changed. Select it again."))
        }
        if let actionID = attachment.actionID, !actions.contains(where: { $0.id == actionID }) {
            issues.append(.init(key: "actionID", message: "The selected action is no longer available."))
        }
        if attachment.configurationVersion != (configuration?.schemaVersion ?? 1) {
            issues.append(.init(key: "configurationVersion", message: "The configuration version changed. Select it again."))
        }
        if let configuration {
            issues += configuration.validationIssues(for: attachment.configuration)
        } else if attachment.configuration != .object([:]) {
            issues.append(.init(key: "configuration", message: "This capability does not accept composer configuration."))
        }
        return issues
    }
}
