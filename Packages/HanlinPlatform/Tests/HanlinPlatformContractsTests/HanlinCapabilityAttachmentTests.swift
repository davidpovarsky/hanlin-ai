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
        let raw = Data(#"""
        {"title":"Text search","summary":"Search selected collections","actions":[{
          "id":"search","title":"Search","summary":"Find text",
          "inputSchema":{"type":"object","properties":{
            "query":{"type":"string"},
            "metadata":{"type":"object","default":{"type":"integer","value":7}}
          },"required":["query"]},
          "outputSchema":{"type":"object","properties":{
            "results":{"type":"array","items":{"type":"string"}},
            "score":{"type":"number","minimum":0.25},
            "state":{"enum":[true,null,"ready",3]}
          },"additionalProperties":false},
          "exportedSymbol":"searchBooks","embeddedResultID":"results"
        }]}
        """#.utf8)
        let metadata = try JSONDecoder().decode(HanlinAssistantToolDeclaration.self, from: raw)
        try metadata.validateDefinition()
        #expect(metadata.actions[0].embeddedResultID == "results")
        #expect(metadata.actions[0].exportedSymbol == "searchBooks")
        #expect(metadata.actions[0].outputSchema != nil)
        let encoded = try JSONEncoder().encode(metadata)
        let restored = try JSONDecoder().decode(HanlinAssistantToolDeclaration.self, from: encoded)
        #expect(restored == metadata)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let actions = try #require(object["actions"] as? [[String: Any]])
        let schema = try #require(actions[0]["inputSchema"] as? [String: Any])
        #expect(schema["type"] as? String == "object")
        #expect(schema["root"] == nil)
        #expect(schema["value"] == nil)
        let outputSchema = try #require(actions[0]["outputSchema"] as? [String: Any])
        #expect(outputSchema["type"] as? String == "object")
        #expect(outputSchema["additionalProperties"] as? Bool == false)
        #expect(outputSchema["root"] == nil)
        #expect(outputSchema["value"] == nil)

        // Persisted shared values retain their existing exact tagged format.
        let persisted = try JSONEncoder().encode(HanlinJSONValue.object(["value": .integer(7)]))
        let persistedObject = try #require(JSONSerialization.jsonObject(with: persisted) as? [String: Any])
        #expect(persistedObject["type"] as? String == "object")
        #expect(persistedObject["value"] is [[String: Any]])
    }

    @Test("Author defaults use ordinary JSON while preserving absent and explicit null values")
    func rawManifestDefaultsRoundTrip() throws {
        let raw = Data(#"""
        {"panels":[{"id":"search","title":"Search","fields":[
          {"key":"query","title":"Query","kind":"text","defaultValue":"שלום"},
          {"key":"enabled","title":"Enabled","kind":"toggle","defaultValue":true},
          {"key":"limit","title":"Limit","kind":"number","defaultValue":12,"minimum":1,"maximum":100},
          {"key":"weight","title":"Weight","kind":"number","defaultValue":0.5},
          {"key":"empty","title":"Optional","kind":"text","defaultValue":null},
          {"key":"absent","title":"No default","kind":"text","placeholder":"Type here"},
          {"key":"books","title":"Books","kind":"catalog","defaultValue":["tanakh"],
           "options":[{"id":"texts","title":"Texts","children":[{"id":"tanakh","title":"Tanakh"}]}]},
          {"key":"area","title":"Area","kind":"location",
           "defaultValue":{"latitude":31.78,"longitude":35.22,"radiusMeters":1000}}
        ]}]}
        """#.utf8)
        let configuration = try JSONDecoder().decode(HanlinComposerConfiguration.self, from: raw)
        try configuration.validateDefinition()
        #expect(configuration.validationIssues(for: configuration.defaultValues).isEmpty)
        #expect(configuration.panels[0].fields.first { $0.key == "empty" }?.defaultValue == .null)
        #expect(configuration.panels[0].fields.first { $0.key == "absent" }?.defaultValue == nil)
        #expect(configuration.panels[0].fields.allSatisfy { !$0.required })
        #expect(configuration.panels[0].fields.first { $0.key == "books" }?.options[0].children[0].children == [])

        let encoded = try JSONEncoder().encode(configuration)
        #expect(try JSONDecoder().decode(HanlinComposerConfiguration.self, from: encoded) == configuration)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let panels = try #require(object["panels"] as? [[String: Any]])
        let encodedFields = try #require(panels[0]["fields"] as? [[String: Any]])
        var fields: [String: [String: Any]] = [:]
        for field in encodedFields { fields[try #require(field["key"] as? String)] = field }
        #expect(fields["query"]?["defaultValue"] as? String == "שלום")
        #expect(fields["enabled"]?["defaultValue"] as? Bool == true)
        #expect(fields["limit"]?["defaultValue"] as? Int == 12)
        #expect(fields["weight"]?["defaultValue"] as? Double == 0.5)
        #expect(fields["empty"]?["defaultValue"] is NSNull)
        #expect(fields["absent"]?["defaultValue"] == nil)
        #expect(fields["books"]?["defaultValue"] as? [String] == ["tanakh"])
        let area = try #require(fields["area"]?["defaultValue"] as? [String: Any])
        #expect(Set(area.keys) == ["latitude", "longitude", "radiusMeters"])
        #expect(area["latitude"] as? Double == 31.78)
        #expect(area["radiusMeters"] as? Int == 1000)
    }

    @Test("Required metadata and optional omissions agree with the author manifest schema")
    func assistantMetadataOmissionsMatchManifestContract() throws {
        let action: [String: Any] = [
            "id": "search", "title": "Search", "summary": "Find text", "inputSchema": ["type": "object"]
        ]
        let declaration: [String: Any] = ["title": "Search", "summary": "Find text", "actions": [action]]
        func decode(_ object: [String: Any]) throws -> HanlinAssistantToolDeclaration {
            let result = try JSONDecoder().decode(
                HanlinAssistantToolDeclaration.self, from: JSONSerialization.data(withJSONObject: object)
            )
            try result.validateDefinition()
            return result
        }
        let metadata = try decode(declaration)
        #expect(metadata.configuration == nil)
        #expect(metadata.actions[0].exportedSymbol == nil)
        #expect(metadata.actions[0].outputSchema == nil)
        #expect(metadata.actions[0].embeddedResultID == nil)
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(metadata)) as? [String: Any])
        let encodedActions = try #require(encoded["actions"] as? [[String: Any]])
        #expect(encoded["configuration"] == nil)
        #expect(encodedActions[0]["exportedSymbol"] == nil)
        #expect(encodedActions[0]["outputSchema"] == nil)
        #expect(encodedActions[0]["embeddedResultID"] == nil)

        for key in ["title", "summary", "actions"] {
            var missing = declaration
            missing.removeValue(forKey: key)
            #expect(throws: (any Error).self) { try decode(missing) }
        }
        for key in ["id", "title", "summary", "inputSchema"] {
            var missing = action
            missing.removeValue(forKey: key)
            var invalid = declaration
            invalid["actions"] = [missing]
            #expect(throws: (any Error).self) { try decode(invalid) }
        }
        for key in ["exportedSymbol", "outputSchema", "embeddedResultID"] {
            var nullAction = action
            nullAction[key] = NSNull()
            var invalid = declaration
            invalid["actions"] = [nullAction]
            #expect(throws: (any Error).self) { try decode(invalid) }
        }
        var nullConfiguration = declaration
        nullConfiguration["configuration"] = NSNull()
        #expect(throws: (any Error).self) { try decode(nullConfiguration) }

        // Only defaultValue accepts explicit null. Optional typed metadata does not.
        for key in ["required", "options", "minimum", "maximum", "placeholder"] {
            let invalid: [String: Any] = ["key": "query", "title": "Query", "kind": "text", key: NSNull()]
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(HanlinComposerField.self, from: JSONSerialization.data(withJSONObject: invalid))
            }
        }
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
