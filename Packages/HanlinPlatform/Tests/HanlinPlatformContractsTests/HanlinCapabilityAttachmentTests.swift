import Foundation
import HanlinPlatformContracts
import Testing

@Suite("Explicit composer capability contracts")
struct HanlinCapabilityAttachmentTests {
    @Test("Provider-scoped identities cannot collide through separators or titles")
    func identityIncludesProviderButRevisionRemainsSeparate() {
        let a = HanlinCapabilityReference(kind: .mcp, sourceID: "a:b", capabilityID: "c", revision: "1")
        let b = HanlinCapabilityReference(kind: .mcp, sourceID: "a", capabilityID: "b:c", revision: "1")
        var updated = a
        updated.revision = "2"
        #expect(a.id != b.id)
        #expect(a.id == updated.id)
        #expect(a != updated)
    }

    @Test("Default configuration is a value snapshot, independent between drafts")
    func draftConfigurationDoesNotMutateDescriptorOrSentSnapshot() throws {
        let descriptor = fixture()
        var draft = descriptor.makeAttachment(actionID: "search")
        let sent = draft
        draft.setValue(.array([.string("talmud")]), forKey: "collections")
        #expect(sent.value(forKey: "collections") == .array([.string("tanakh")]))
        #expect(descriptor.configuration?.defaultValues != draft.configuration)
        let restored = try JSONDecoder().decode(HanlinCapabilityAttachment.self, from: JSONEncoder().encode(sent))
        #expect(restored == sent)
    }

    @Test("Catalog and map input cannot silently carry invalid or undeclared values")
    func catalogAndMapValidation() throws {
        let config = try #require(fixture().configuration)
        #expect(config.validationIssues(for: config.defaultValues).isEmpty)
        var values: HanlinObject<HanlinJSONValue> = [
            "collections": .array([.string("missing")]),
            "area": .object(["latitude": .number(91), "longitude": .number(35), "radiusMeters": .number(-1)])
        ]
        #expect(Set(config.validationIssues(for: .object(values)).map(\.key)) == ["collections", "area"])
        values["collections"] = .array([.string("talmud"), .string("talmud")])
        values["unexpected"] = .bool(true)
        #expect(config.validationIssues(for: .object(values)).contains { $0.key == "unexpected" })
        #expect(config.validationIssues(for: .object(values)).contains { $0.key == "collections" })
    }

    @Test("Stale versions and actions are rejected independently of catalog display labels")
    func staleAttachmentRequiresReselection() {
        let descriptor = fixture()
        var attachment = descriptor.makeAttachment(actionID: "removed")
        attachment.reference.revision = "old"
        attachment.configurationVersion = 2
        let keys = Set(descriptor.validationIssues(for: attachment).map(\.key))
        #expect(keys.contains("reference"))
        #expect(keys.contains("actionID"))
        #expect(keys.contains("configurationVersion"))
    }

    @Test("Configuration decoder defaults support minimal author manifests")
    func minimalManifestDecoding() throws {
        let data = Data(#"{"panels":[{"id":"search","title":"Search","fields":[{"key":"query","title":"Query","kind":"text","required":true}]}]}"#.utf8)
        let configuration = try JSONDecoder().decode(HanlinComposerConfiguration.self, from: data)
        try configuration.validateDefinition()
        #expect(configuration.schemaVersion == 1)
        #expect(configuration.validationIssues(for: .object([:])).map(\.key) == ["query"])
        #expect(configuration.validationIssues(for: .object(["query": .string("שלום")])).isEmpty)
    }

    @Test("Duplicate fields across panels and invalid defaults fail declaration validation")
    func declarationValidation() throws {
        let configuration = HanlinComposerConfiguration(panels: [
            .init(id: "one", title: "One", fields: [.init(key: "limit", title: "Limit", kind: .number, defaultValue: .integer(-1), minimum: 0)]),
            .init(id: "two", title: "Two", fields: [.init(key: "limit", title: "Limit", kind: .text)])
        ])
        #expect(throws: HanlinContractError.self) { try configuration.validateDefinition() }
    }

    @Test("Assistant metadata preserves raw schemas and declared rich result IDs")
    func assistantDeclarationRoundTrip() throws {
        let raw = Data(#"{"title":"Text search","summary":"Search selected collections","actions":[{"id":"search","title":"Search","summary":"Find text","inputSchema":{"type":"object","properties":{"query":{"type":"string"}},"required":["query"]},"embeddedResultID":"results"}]}"#.utf8)
        let metadata = try JSONDecoder().decode(HanlinAssistantToolDeclaration.self, from: raw)
        try metadata.validateDefinition()
        #expect(metadata.actions[0].embeddedResultID == "results")
        let encoded = try JSONEncoder().encode(metadata)
        let restored = try JSONDecoder().decode(HanlinAssistantToolDeclaration.self, from: encoded)
        #expect(restored == metadata)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let actions = try #require(object["actions"] as? [[String: Any]])
        let schema = try #require(actions[0]["inputSchema"] as? [String: Any])
        #expect(schema["type"] as? String == "object")
        #expect(schema["root"] == nil)
    }

    private func fixture() -> HanlinComposerCapabilityDescriptor {
        .init(reference: .init(kind: .miniApp, sourceID: "installed-a", capabilityID: "search", revision: "7"),
              title: "Search", actions: [.init(id: "search", title: "Search")],
              configuration: .init(panels: [
                .init(id: "catalog", title: "Collections", fields: [
                    .init(key: "collections", title: "Collections", kind: .catalog, required: true,
                          defaultValue: .array([.string("tanakh")]),
                          options: [.init(id: "tanakh", title: "Tanakh"), .init(id: "talmud", title: "Talmud")])
                ]),
                .init(id: "map", title: "Area", fields: [
                    .init(key: "area", title: "Area", kind: .location,
                          defaultValue: .object(["latitude": .number(31.78), "longitude": .number(35.22), "radiusMeters": .integer(1000)]),
                          minimum: 100, maximum: 10000)
                ])
              ]))
    }
}
