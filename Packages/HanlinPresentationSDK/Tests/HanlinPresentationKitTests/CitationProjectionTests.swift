import Foundation
import Testing
@testable import HanlinPresentationKit

private let citationMessage = UUID()
private let sourceA = HanlinSourceReference(id: "A", title: "Original A", url: URL(string: "https://a.example/reference"))
private let sourceB = HanlinSourceReference(id: "B", title: "Original B", url: URL(string: "https://b.example/reference"))

@Test func citationsRequireActualAnchorsAndCompleteSentences() {
    let text = "A supported statement. An unfinished statement"
    let noAnchors = HanlinCitationProjection.make(text: text, messageID: citationMessage, sources: [sourceA], anchors: [])
    #expect(noAnchors.markdown == text && noAnchors.groups.isEmpty)
    let result = HanlinCitationProjection.make(text: text, messageID: citationMessage, sources: [sourceA, sourceB], anchors: [
        .init(sourceID: "A", range: 0..<11), .init(sourceID: "B", range: 23..<text.utf16.count),
    ])
    #expect(result.groups.count == 1 && result.groups[0].sources == [sourceA])
    #expect(result.markdown.hasPrefix("A supported statement. [9F742443]"))
    #expect(result.markdown.hasSuffix("An unfinished statement"))
}

@Test func repeatedSentenceSourcesGroupWithoutDuplicatingProviderLinks() {
    let text = "Supported. [one](https://a.example/reference) [two](https://b.example/reference)"
    let value = text as NSString
    let first = value.range(of: "[one](https://a.example/reference)")
    let second = value.range(of: "[two](https://b.example/reference)")
    let result = HanlinCitationProjection.make(text: text, messageID: citationMessage, sources: [sourceA, sourceB], anchors: [
        .init(sourceID: "A", range: first.location..<(first.location + first.length)),
        .init(sourceID: "B", range: second.location..<(second.location + second.length)),
        .init(sourceID: "A", range: first.location..<(first.location + first.length)),
    ])
    #expect(result.groups.count == 1)
    #expect(result.groups[0].sources.map(\.id) == ["A", "B"])
    #expect(!result.markdown.contains("[one]") && !result.markdown.contains("[two]"))
    #expect(URLComponents(url: result.groups[0].url, resolvingAgainstBaseURL: false)?.queryItems?.contains(.init(name: "citationTitle", value: "a.example +1")) == true)
}

@Test func rtlEmojiMarkdownAndCodeKeepCorrectCitationBoundaries() {
    let text = "**מקור 😀 מדויק.**\n\n```swift\nlet value = 1.0\n```"
    let value = text as NSString
    let claim = value.range(of: "מקור 😀 מדויק.")
    let code = value.range(of: "value")
    let result = HanlinCitationProjection.make(text: text, messageID: citationMessage, sources: [sourceA, sourceB], anchors: [
        .init(sourceID: "A", range: claim.location..<(claim.location + claim.length)),
        .init(sourceID: "B", range: code.location..<(code.location + code.length)),
        .init(sourceID: "B", range: 0..<9999),
    ])
    #expect(result.groups.count == 1)
    #expect(result.markdown.hasPrefix("**מקור 😀 מדויק.** [9F742443]"))
    #expect(result.markdown.hasSuffix("```swift\nlet value = 1.0\n```"))
}
