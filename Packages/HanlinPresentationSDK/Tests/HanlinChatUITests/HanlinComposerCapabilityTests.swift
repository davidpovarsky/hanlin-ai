import Foundation
import Testing
import HanlinChatUI
import HanlinPlatformContracts

@Suite("Composer capability token selection")
struct HanlinComposerCapabilityQueryTests {
    @Test func replacesOnlyTheWholeTokenAtTheCaretInRTLText() throws {
        let text = "שלום 🌍 @ספריא המשך"
        let token = (text as NSString).range(of: "@ספריא")
        let query = try #require(HanlinComposerCapabilityQuery.parse(
            text: text, selection: NSRange(location: token.location + 3, length: 0)))
        #expect(query.trigger == .mention)
        #expect(query.query == "ספ")
        #expect(query.range == token)
        #expect(query.replacingToken(in: text) == "שלום 🌍  המשך")
        #expect(query.selectionAfterReplacing().location == token.location)
    }

    @Test func slashSelectionPreservesFollowingTextAndProducesCorrectCaret() throws {
        let text = "Use /places near here"
        let token = (text as NSString).range(of: "/places")
        let query = try #require(HanlinComposerCapabilityQuery.parse(
            text: text, selection: NSRange(location: NSMaxRange(token), length: 0)))
        #expect(query.trigger == .command)
        #expect(query.query == "places")
        #expect(query.replacingToken(in: text, with: "chosen") == "Use chosen near here")
        #expect(query.selectionAfterReplacing(with: "chosen") == NSRange(location: 10, length: 0))
    }

    @Test func rejectsStaleChoicesAndComposition() throws {
        let text = "@catalog"
        let query = try #require(HanlinComposerCapabilityQuery.parse(
            text: text, selection: NSRange(location: text.utf16.count, length: 0)))
        #expect(query.replacingToken(in: "@different") == nil)
        #expect(HanlinComposerCapabilityQuery.parse(
            text: text, selection: NSRange(location: text.utf16.count, length: 0),
            hasMarkedText: true) == nil)
        #expect(HanlinComposerCapabilityQuery.parse(
            text: text, selection: NSRange(location: 1, length: 2)) == nil)
    }

    @Test func ignoresEmailsURLsAndInvalidUTF16Caret() {
        for text in ["person@example.com", "https://example.com/path", "plain"] {
            #expect(HanlinComposerCapabilityQuery.parse(
                text: text, selection: NSRange(location: text.utf16.count, length: 0)) == nil)
        }
        #expect(HanlinComposerCapabilityQuery.parse(
            text: "🌍 @tool", selection: NSRange(location: 1, length: 0)) == nil)
        #expect(HanlinComposerCapabilityQuery.parse(
            text: "@tool", selection: NSRange(location: NSNotFound, length: 0)) == nil)
    }

    @Test func modelMentionsRetainTheExistingTextRepresentation() throws {
        let query = try #require(HanlinComposerCapabilityQuery.parse(
            text: "Hello @mod", selection: NSRange(location: 10, length: 0)))
        #expect(query.replacingToken(in: "Hello @mod", with: "@Model Name ") == "Hello @Model Name ")
    }
}

#if canImport(UIKit)
@MainActor
@Suite("Composer attachment ownership")
struct HanlinComposerCapabilityDraftTests {
    @Test func submittedSnapshotAndOtherDraftRemainUnchanged() {
        let first = HanlinComposerDraft(text: "Find texts")
        let second = HanlinComposerDraft(text: "Find texts")
        let reference = HanlinCapabilityReference(kind: .miniApp, sourceID: "catalog", capabilityID: "search")
        let original = HanlinCapabilityAttachment(reference: reference, title: "Library",
            configuration: .object(["catalog": .array([.string("tanakh")])]))
        first.attach(original)
        let submitted = first.capabilitySnapshot
        var edited = original
        edited.configuration = .object(["catalog": .array([.string("talmud")])])
        first.updateCapability(edited)
        #expect(submitted[0].configuration == original.configuration)
        #expect(first.capabilityAttachments[0].configuration == edited.configuration)
        #expect(second.capabilityAttachments.isEmpty)
        first.clearCapabilities()
        #expect(submitted.count == 1)
        #expect(first.text == "Find texts")
    }

    @Test func changingAnActionConsolidatesOnlyItsDuplicateAndKeepsTheEditingIdentity() {
        let draft = HanlinComposerDraft()
        let reference = HanlinCapabilityReference(kind: .miniApp, sourceID: "library", capabilityID: "assistant")
        var editing = HanlinCapabilityAttachment(reference: reference, title: "Library",
            configuration: .object(["scope": .string("edited")]))
        let alreadySelected = HanlinCapabilityAttachment(reference: reference, title: "Library",
            actionID: "search", configuration: .object(["scope": .string("previous")]))
        let otherProvider = HanlinCapabilityAttachment(
            reference: .init(kind: .miniApp, sourceID: "other", capabilityID: "assistant"),
            title: "Other library", actionID: "search")
        draft.attach(editing)
        draft.attach(alreadySelected)
        draft.attach(otherProvider)
        let submitted = draft.capabilitySnapshot

        editing.actionID = "search"
        draft.updateCapability(editing)

        #expect(draft.capabilityAttachments.count == 2)
        #expect(draft.capabilityAttachments.first?.id == editing.id)
        #expect(draft.capabilityAttachments.first?.configuration == editing.configuration)
        #expect(draft.capabilityAttachments.last == otherProvider)
        #expect(submitted.count == 3)
        #expect(submitted[1].configuration == alreadySelected.configuration)
    }

    @Test func repeatedPickerSelectionKeepsConfigurationAndRemovalIsScoped() {
        let draft = HanlinComposerDraft()
        let reference = HanlinCapabilityReference(kind: .tool, sourceID: "native", capabilityID: "search")
        let selected = HanlinCapabilityAttachment(reference: reference, title: "Search",
            configuration: .object(["scope": .string("chosen")]))
        let originalID = draft.attach(selected)
        let repeatedID = draft.attach(.init(reference: reference, title: "Search"))
        #expect(originalID == repeatedID)
        #expect(draft.capabilityAttachments.count == 1)
        #expect(draft.capabilityAttachments[0].configuration == selected.configuration)
        draft.removeCapability(id: UUID())
        #expect(draft.capabilityAttachments.count == 1)
        draft.removeCapability(id: originalID)
        #expect(draft.capabilityAttachments.isEmpty)
    }
}
#endif
