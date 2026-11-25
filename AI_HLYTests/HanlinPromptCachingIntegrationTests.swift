import Foundation
import HanlinChatCore
import HanlinPlatformContracts
import Testing
@testable import AI_Hanlin

@Suite("Native prompt cache integration")
struct HanlinPromptCachingIntegrationTests {
    @Test("Current time and retrieved memory change only the trailing system block")
    func stableInstructionsSurviveContextChanges() {
        let stable = ["Identity", "User preferences", "Citation rules", "Presentation rules"]
        let first = HanlinSystemPromptSections(
            stableSections: stable, contextSections: ["2026-11-25 10:00", "Memory for request A"])
        let second = HanlinSystemPromptSections(
            stableSections: stable, contextSections: ["2026-11-25 10:01", "Memory for request B"])
        #expect(first.messageTexts.count == 2)
        #expect(first.stable == second.stable)
        #expect(first.context != second.context)
        #expect(first.rendered.hasPrefix(first.stable + "\n\n"))
        #expect(first.rendered.hasSuffix("Memory for request A"))
        #expect(second.rendered.hasSuffix("Memory for request B"))
        #expect(!second.stable.contains("2026-11-25"))
    }

    @MainActor
    @Test("SDK conversion preserves system authority and one stable cache boundary")
    func distinctSystemBlocks() {
        let converted = APIManager.convertFormattedMessagesToSDKMessages([
            ["role": "developer", "content": "Stable instructions"],
            ["role": "developer", "content": "Time and current retrieved memory"],
            ["role": "user", "content": "Question"],
            ["role": "system", "content": "Loaded skill"],
            ["role": "assistant", "content": "Answer"]
        ])
        #expect(converted.baseSystemPrompt == nil)
        #expect(converted.messages.map(\.role) == [.system, .system, .user, .system, .assistant])
        #expect(converted.messages.map(\.cacheBreakpoint) == [true, false, false, false, false])
        #expect(converted.messages[1].parts == [.text("Time and current retrieved memory")])
        #expect(converted.messages[3].parts == [.text("Loaded skill")])
    }

    @Test("No synthetic delimiters or empty context are added to prompt text")
    func emptyAndVerbatimSections() {
        let source = "  user-defined instructions\nwith original whitespace  "
        let parts = HanlinSystemPromptSections(stableSections: ["", source], contextSections: [""])
        #expect(parts.messageTexts == [source])
        #expect(parts.rendered == source)
    }

    @MainActor
    @Test("Skill discovery order is stable across catalog enumeration order")
    func stableSkillCatalogOrder() throws {
        let a = try HanlinSkillDescriptor(id: HanlinSkillID(validating: "alpha"),
            title: "Alpha", summary: "First", instructions: .inline("A"))
        let z = try HanlinSkillDescriptor(id: HanlinSkillID(validating: "zeta"),
            title: "Zeta", summary: "Last", instructions: .inline("Z"))
        let first = HanlinSkillIndex.prompt(for: [z, a])
        let second = HanlinSkillIndex.prompt(for: [a, z])
        #expect(first == second)
        let alpha = try #require(first.range(of: "`alpha`"))
        let zeta = try #require(first.range(of: "`zeta`"))
        #expect(alpha.lowerBound < zeta.lowerBound)
    }
}
