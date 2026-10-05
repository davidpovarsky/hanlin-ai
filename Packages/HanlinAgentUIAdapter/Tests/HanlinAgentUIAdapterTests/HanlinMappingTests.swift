// Packages/HanlinAgentUIAdapter/Tests/HanlinAgentUIAdapterTests/HanlinMappingTests.swift
import Testing
import Foundation
@testable import HanlinAgentUIAdapter
import HanlinPlatformContracts
import AgentUI

@Suite("Hanlin to AgentUI Contract Mapping Tests")
struct HanlinMappingTests {
    @Test("Verify embedded presentation descriptor mapping")
    func testEmbeddedDescriptorMapping() {
        let hanlinDescriptor = HanlinEmbeddedPresentationDescriptor(
            handler: "hanlin.swift.miniapp",
            sizing: HanlinEmbeddedSizingPreference(preset: .regular, preferredWidth: 320, preferredHeight: 250),
            expansion: HanlinExpansionDescriptor(supportedModes: [.sheet, .fullScreen])
        )

        let agentUIDescriptor = HanlinPresentationMapping.map(descriptor: hanlinDescriptor)

        #expect(agentUIDescriptor.handlerID == "hanlin.swift.miniapp")
        #expect(agentUIDescriptor.sizing.preset == .regular)
        #expect(agentUIDescriptor.sizing.idealHeight == 250)
        #expect(agentUIDescriptor.expansion.allowedModes.contains(.sheet))
        #expect(agentUIDescriptor.expansion.allowedModes.contains(.fullScreen))
    }

    @Test("Verify tool execution descriptor mapping")
    func testToolExecutionMapping() {
        let toolDescriptor = HanlinToolExecutionPresentationDescriptor(
            familyID: .webSearch,
            customHandler: nil
        )

        let execution = HanlinPresentationMapping.map(
            toolDescriptor: toolDescriptor,
            toolName: "web_search",
            arguments: "{\"q\": \"swift\"}"
        )

        #expect(execution.handlerID == "web-search")
        #expect(execution.inspection.toolName == "web_search")
        #expect(execution.status == .running)
    }

    @Test("Verify payload mapping")
    func testPayloadMapping() {
        let payload = HanlinEmbeddedResultPayload(
            title: "Result Title",
            metadata: ["version": "1.0"],
            ownerID: "app.sefaria",
            actions: [
                HanlinEmbeddedContentAction(id: "act-1", title: "Open", systemImage: "arrow.right")
            ]
        )

        let mapped = HanlinPresentationMapping.map(payload: payload)

        #expect(mapped.dictionary["title"] == "Result Title")
        #expect(mapped.dictionary["version"] == "1.0")
        #expect(mapped.dictionary["ownerID"] == "app.sefaria")
        #expect(mapped.actions.count == 1)
        #expect(mapped.actions.first?.title == "Open")
    }
}
