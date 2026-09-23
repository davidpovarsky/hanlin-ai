// HanlinSkillContracts.swift
// HanlinPlatformContracts
//
// Canonical contract representing portable agent Skills.
// A Skill contains lightweight discovery and instruction metadata for an agent.
// A Skill does NOT embed full tool JSON schemas.

import Foundation

/// Defines how the instruction text for a Skill is provided.
public enum HanlinSkillInstructionSource: Codable, Hashable, Sendable {
    /// Inline raw instruction markdown/text.
    case inline(String)
    /// Normalized relative path to an instruction file inside the package/bundle.
    case resource(path: String)

    private enum CodingKeys: String, CodingKey {
        case inline
        case resource
        case path
    }

    public init(from decoder: Decoder) throws {
        if let singleContainer = try? decoder.singleValueContainer(),
           let string = try? singleContainer.decode(String.self) {
            self = .inline(string)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try container.decodeIfPresent(String.self, forKey: .inline) {
            self = .inline(text)
        } else if let path = try container.decodeIfPresent(String.self, forKey: .resource) ?? container.decodeIfPresent(String.self, forKey: .path) {
            self = .resource(path: path)
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected inline text or resource path for skill instructions"
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .inline(let text):
            try container.encode(text, forKey: .inline)
        case .resource(let path):
            try container.encode(path, forKey: .resource)
        }
    }
}

/// Portable descriptor for an agent Skill.
public struct HanlinSkillDescriptor: Codable, Hashable, Identifiable, Sendable {
    public let id: HanlinSkillID
    public let title: LocalizedValue
    public let summary: LocalizedValue
    public let instructions: HanlinSkillInstructionSource
    public let keywords: [String]
    public let triggerHints: [String]
    public let preferredToolIDs: [String]

    public init(
        id: HanlinSkillID,
        title: LocalizedValue,
        summary: LocalizedValue,
        instructions: HanlinSkillInstructionSource,
        keywords: [String] = [],
        triggerHints: [String] = [],
        preferredToolIDs: [String] = []
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.instructions = instructions
        self.keywords = keywords
        self.triggerHints = triggerHints
        self.preferredToolIDs = preferredToolIDs
    }

    public init(
        id: HanlinSkillID,
        title: String,
        summary: String,
        instructions: HanlinSkillInstructionSource,
        keywords: [String] = [],
        triggerHints: [String] = [],
        preferredToolIDs: [String] = []
    ) throws {
        self.id = id
        self.title = try LocalizedValue(["en": title], fallbackLocale: "en")
        self.summary = try LocalizedValue(["en": summary], fallbackLocale: "en")
        self.instructions = instructions
        self.keywords = keywords
        self.triggerHints = triggerHints
        self.preferredToolIDs = preferredToolIDs
    }
}
