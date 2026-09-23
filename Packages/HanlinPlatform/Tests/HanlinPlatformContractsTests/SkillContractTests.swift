import Foundation
import Testing
@testable import HanlinPlatformContracts

@Test
func skillIDsValidateAndRoundTripCanonically() throws {
    let skillID = try HanlinSkillID(validating: "code-analysis")
    #expect(skillID.rawValue == "code-analysis")
    #expect(HanlinSkillID(rawValue: "Code-Analysis") == nil)
    #expect(HanlinSkillID(rawValue: ".code.analysis") == nil)
    #expect(HanlinSkillID(rawValue: "code..analysis") == nil)
    #expect(HanlinSkillID(rawValue: "code/analysis") == nil)
    #expect(HanlinSkillID(rawValue: "מיומנות") == nil)

    let data = try JSONEncoder().encode(skillID)
    #expect(try JSONDecoder().decode(HanlinSkillID.self, from: data) == skillID)

    let malformed = Data(#""code..analysis""#.utf8)
    #expect(throws: HanlinContractError.self) {
        try JSONDecoder().decode(HanlinSkillID.self, from: malformed)
    }
}

@Test
func skillDescriptorEncodesAndDecodesCorrectly() throws {
    let skillID = try HanlinSkillID(validating: "translation-skill")
    let descriptor = try HanlinSkillDescriptor(
        id: skillID,
        title: "Translation",
        summary: "Translates text between languages",
        instructions: .inline("# Translation Guidelines\nAlways preserve nuances."),
        keywords: ["translate", "language"],
        triggerHints: ["translate this sentence"],
        preferredToolIDs: ["translate_text"]
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(descriptor)

    let decoded = try JSONDecoder().decode(HanlinSkillDescriptor.self, from: data)
    #expect(decoded.id == skillID)
    #expect(decoded.keywords == ["translate", "language"])
    #expect(decoded.triggerHints == ["translate this sentence"])
    #expect(decoded.preferredToolIDs == ["translate_text"])
    if case let .inline(text) = decoded.instructions {
        #expect(text.contains("Translation Guidelines"))
    } else {
        Issue.record("Expected inline instructions")
    }

    let resourceSkill = try HanlinSkillDescriptor(
        id: try HanlinSkillID(validating: "resource-skill"),
        title: "Resource Skill",
        summary: "Uses markdown resource file",
        instructions: .resource(path: "skills/guide.md"),
        keywords: ["guide"],
        triggerHints: ["help me"],
        preferredToolIDs: []
    )
    let resData = try encoder.encode(resourceSkill)
    let decodedRes = try JSONDecoder().decode(HanlinSkillDescriptor.self, from: resData)
    if case let .resource(path) = decodedRes.instructions {
        #expect(path == "skills/guide.md")
    } else {
        Issue.record("Expected resource instructions")
    }
}

@Test
func appDescriptorDecodesLegacyPayloadWithoutSkills() throws {
    let fixture = try ContractFixtures.descriptor()
    let data = try fixture.canonicalJSONData()

    // Decode without skills field explicitly present in original fixture
    let decoded = try JSONDecoder().decode(HanlinAppDescriptor.self, from: data)
    #expect(decoded.skills.isEmpty)
}

@Test
func appDescriptorRejectsDuplicateSkillIDs() throws {
    let base = try ContractFixtures.descriptor()
    let skillID = try HanlinSkillID(validating: "duplicate-skill")
    let skill1 = try HanlinSkillDescriptor(
        id: skillID,
        title: "Skill 1",
        summary: "First instance",
        instructions: .inline("Do something")
    )
    let skill2 = try HanlinSkillDescriptor(
        id: skillID,
        title: "Skill 2",
        summary: "Second instance",
        instructions: .inline("Do something else")
    )

    let descriptor = HanlinAppDescriptor(
        schemaVersion: base.schemaVersion,
        descriptorRevision: base.descriptorRevision,
        id: base.id,
        name: base.name,
        summary: base.summary,
        description: base.description,
        version: base.version,
        minimumHostVersion: base.minimumHostVersion,
        apiVersion: base.apiVersion,
        icon: base.icon,
        appearance: base.appearance,
        category: base.category,
        implementation: base.implementation,
        entryPoints: base.entryPoints,
        supportedExposures: base.supportedExposures,
        routes: base.routes,
        actions: base.actions,
        tools: base.tools,
        skills: [skill1, skill2],
        capabilities: base.capabilities,
        dependencies: base.dependencies,
        extensions: base.extensions,
        authors: base.authors,
        distribution: base.distribution,
        integrity: base.integrity
    )

    #expect(throws: HanlinContractError.self) {
        try descriptor.validate()
    }
}

@Test
func appDescriptorRejectsUnsafeResourcePaths() throws {
    let base = try ContractFixtures.descriptor()
    let unsafeSkill = try HanlinSkillDescriptor(
        id: try HanlinSkillID(validating: "unsafe-path-skill"),
        title: "Unsafe Skill",
        summary: "Attempts directory traversal",
        instructions: .resource(path: "../secret.md")
    )

    let descriptor = HanlinAppDescriptor(
        schemaVersion: base.schemaVersion,
        descriptorRevision: base.descriptorRevision,
        id: base.id,
        name: base.name,
        summary: base.summary,
        description: base.description,
        version: base.version,
        minimumHostVersion: base.minimumHostVersion,
        apiVersion: base.apiVersion,
        icon: base.icon,
        appearance: base.appearance,
        category: base.category,
        implementation: base.implementation,
        entryPoints: base.entryPoints,
        supportedExposures: base.supportedExposures,
        routes: base.routes,
        actions: base.actions,
        tools: base.tools,
        skills: [unsafeSkill],
        capabilities: base.capabilities,
        dependencies: base.dependencies,
        extensions: base.extensions,
        authors: base.authors,
        distribution: base.distribution,
        integrity: base.integrity
    )

    #expect(throws: HanlinContractError.self) {
        try descriptor.validate()
    }
}
