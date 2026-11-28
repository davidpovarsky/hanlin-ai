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

@Test func explicitReturnedSourceLinksWorkWithoutResponsesAnnotations() {
    let text = "A supported sentence. [source](https://a.example/reference) [2](https://b.example/reference) Next sentence."
    let anchors = HanlinCitationProjection.explicitSourceLinkAnchors(text: text, sources: [sourceA, sourceB])
    #expect(anchors.count == 2)
    let result = HanlinCitationProjection.make(text: text, messageID: citationMessage,
        sources: [sourceA, sourceB], anchors: anchors)
    #expect(result.groups.count == 1)
    #expect(result.groups[0].sources == [sourceA, sourceB])
    #expect(result.markdown.hasPrefix("A supported sentence. [9F742443]"))
    #expect(!result.markdown.contains("[source]") && !result.markdown.contains("[2]"))
    #expect(result.markdown.hasSuffix("Next sentence."))
}

@Test func admittedURLAliasesGroupAsOneSourceWithoutAdmittingUnknownFragments() {
    let baseURL = URL(string: "https://example.com/reference")!
    let sectionURL = URL(string: "https://example.com/reference#section")!
    let source = HanlinSourceReference(id: "page", title: "Returned page", url: baseURL,
        alternateURLs: [sectionURL])
    let text = "Supported. [source](https://example.com/reference#section) [source](https://example.com/reference) Unknown. [source](https://example.com/reference#unknown)"
    let anchors = HanlinCitationProjection.explicitSourceLinkAnchors(text: text, sources: [source])
    #expect(anchors.count == 2)
    let result = HanlinCitationProjection.make(text: text, messageID: citationMessage,
        sources: [source], anchors: anchors)
    #expect(result.groups.count == 1)
    #expect(result.groups[0].sources == [source])
    #expect(result.groups[0].sources[0].url == baseURL)
    #expect(!result.markdown.contains("[source](https://example.com/reference#section)"))
    #expect(!result.markdown.contains("[source](https://example.com/reference)"))
    #expect(result.markdown.hasSuffix("Unknown. [source](https://example.com/reference#unknown)"))
}

@Test func sourceRecognitionPreservesProseCodeImagesAndUnverifiedLinks() {
    let text = """
    Read [the original](https://a.example/reference) for details.
    A sentence. [Read more](https://a.example/reference)
    Unknown claim. [source](https://unknown.example/reference)
    Unmapped claim. [1]
    An image. ![source](https://a.example/reference)
    Escaped. \\[source](https://a.example/reference)
    `Code sentence. [source](https://a.example/reference)`
    ``Code ` sentence. [source](https://a.example/reference)``
    ```markdown
    A code sample. [source](https://a.example/reference)
    ```
    """
    #expect(HanlinCitationProjection.explicitSourceLinkAnchors(text: text, sources: [sourceA]).isEmpty)
}

@Test func explicitCitationWaitsForItsSentenceAndDoesNotCrossParagraphs() {
    let unfinished = "Unfinished [source](https://a.example/reference)"
    let separated = "Previous sentence.\n\n[source](https://a.example/reference)"
    #expect(HanlinCitationProjection.explicitSourceLinkAnchors(text: unfinished, sources: [sourceA]).isEmpty)
    #expect(HanlinCitationProjection.explicitSourceLinkAnchors(text: separated, sources: [sourceA]).isEmpty)
    let complete = "**מקור 😀 מדויק.** [source](https://a.example/reference)"
    let anchors = HanlinCitationProjection.explicitSourceLinkAnchors(text: complete, sources: [sourceA])
    let result = HanlinCitationProjection.make(text: complete, messageID: citationMessage,
        sources: [sourceA], anchors: anchors)
    #expect(result.groups.count == 1)
    #expect(result.markdown.hasPrefix("**מקור 😀 מדויק.** [9F742443]"))
}

@Test func explicitSourceLinksSupportParenthesizedAndAngleURLs() {
    let source = HanlinSourceReference(id: "wiki", title: "Exact page",
        url: URL(string: "https://example.com/wiki/Topic_(detail)"))
    for text in ["Supported. [source](https://example.com/wiki/Topic_(detail))",
                 "Supported. [source](<https://example.com/wiki/Topic_(detail)>)"] {
        let anchors = HanlinCitationProjection.explicitSourceLinkAnchors(text: text, sources: [source])
        #expect(anchors.count == 1)
        let result = HanlinCitationProjection.make(text: text, messageID: citationMessage, sources: [source], anchors: anchors)
        #expect(result.groups.count == 1)
        #expect(!result.markdown.contains("[source]"))
    }
}

@Test func orderedPartsWithEqualOffsetsKeepIndependentSourceTargets() {
    let a = HanlinCitationProjection.make(text: "Claim A.", messageID: citationMessage,
        sources: [sourceA], anchors: [.init(sourceID: "A", range: 0..<8)], namespace: "part-A")
    let b = HanlinCitationProjection.make(text: "Claim B.", messageID: citationMessage,
        sources: [sourceB], anchors: [.init(sourceID: "B", range: 0..<8)], namespace: "part-B")
    #expect(a.groups.count == 1 && b.groups.count == 1)
    #expect(a.groups[0].url != b.groups[0].url)
}
