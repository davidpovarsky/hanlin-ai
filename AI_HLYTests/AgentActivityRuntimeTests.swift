import XCTest
@testable import AI_Hanlin

final class AgentActivityRuntimeTests: XCTestCase {
    func testOperationalStateDoesNotEndAnswerOrCreateProgress() {
        for state in [
            "Processing", "Sending request", "Waiting for model response",
            "Request sent", "Parsing response"
        ] {
            var adapter = HanlinStreamEventAdapter(runID: UUID())
            let events = adapter.events(from: StreamData(content: "Answer", operationalState: state))

            XCTAssertTrue(events.contains { event in
                if case .answerSegmentDelta(_, "Answer") = event { return true }
                return false
            })
            XCTAssertFalse(events.contains { event in
                if case .answerSegmentEnded(_, .interim) = event { return true }
                if case .progressMessage(_) = event { return true }
                return false
            })
        }
    }

    func testCompletedRunPromotesLastNonemptyAssistantSegment() {
        let run = AgentRun(groupID: UUID())
        var accumulator = AgentEventAccumulator(run: run)
        accumulator.apply(.answerSegmentStarted(AgentItemMetadata(id: "first", title: "", startedAt: .now)))
        accumulator.apply(.answerSegmentDelta(id: "first", text: "Interim"))
        accumulator.apply(.answerSegmentEnded(id: "first", disposition: .interim))
        accumulator.apply(.answerSegmentStarted(AgentItemMetadata(id: "second", title: "", startedAt: .now)))
        accumulator.apply(.answerSegmentDelta(id: "second", text: "Final"))
        accumulator.apply(.runCompleted)

        XCTAssertEqual(accumulator.run.finalAnswer, "Final")
        XCTAssertTrue(AgentTranscriptValidation.satisfiesCompletedRunInvariant(accumulator.run))
    }

    func testContentProcessingToolContentProducesOneVisibleFinalAnswer() {
        let runID = UUID()
        var adapter = HanlinStreamEventAdapter(runID: runID)
        var accumulator = AgentEventAccumulator(run: AgentRun(id: runID, groupID: UUID()))
        let call = AgentToolCall.parse(
            id: "lookup",
            name: "search_online",
            argumentsJSON: #"{"query":"Swift"}"#
        )

        accumulator.apply(.runStarted(AgentRunMetadata(
            id: runID,
            groupID: accumulator.run.groupID,
            providerID: nil,
            modelID: nil,
            startedAt: .now
        )))
        adapter.events(from: StreamData(content: "Let me check.")).forEach { accumulator.apply($0) }
        adapter.events(from: StreamData(operationalState: "Processing")).forEach { accumulator.apply($0) }
        adapter.events(from: StreamData(agentEvents: [.toolCallStarted(call)])).forEach { accumulator.apply($0) }
        adapter.events(from: StreamData(content: "Here is the verified answer.")).forEach { accumulator.apply($0) }
        adapter.completionEvents().forEach { accumulator.apply($0) }
        accumulator.apply(.runCompleted)

        let visibleAnswers = accumulator.run.transcriptItems.filter {
            $0.kind == .assistantText && $0.visibilityAfterCompletion == .remainInChat
        }
        XCTAssertEqual(visibleAnswers.compactMap(\.text), ["Here is the verified answer."])
        XCTAssertEqual(accumulator.run.finalAnswer, "Here is the verified answer.")
        XCTAssertTrue(accumulator.run.hasMeaningfulThinkingActivity)
    }

    func testMalformedCompletedTranscriptNormalizesToOneFinal() {
        let first = assistantItem(sequence: 0, text: "First", role: .final)
        let second = assistantItem(sequence: 1, text: "Second", role: .final)
        let normalized = AgentTranscriptValidation.normalized(
            [first, second],
            promotingFinalAnswerForCompletedRun: true
        )

        XCTAssertEqual(normalized.filter { $0.textRole == .final }.count, 1)
        XCTAssertEqual(AgentTranscriptValidation.finalAnswer(in: normalized), "Second")
    }

    func testExistingFinalMarkerWinsOverLaterInterimText() {
        let final = assistantItem(sequence: 0, text: "Chosen", role: .final)
        let later = assistantItem(sequence: 1, text: "Later interim", role: .interim)
        let normalized = AgentTranscriptValidation.normalized(
            [final, later],
            promotingFinalAnswerForCompletedRun: true
        )

        XCTAssertEqual(AgentTranscriptValidation.finalAnswer(in: normalized), "Chosen")
        XCTAssertEqual(normalized.last?.visibilityAfterCompletion, .collapseIntoThinking)
    }

    func testCompletedTranscriptWithoutAssistantTextHasNoFinalAnswer() {
        let progress = AgentTranscriptItem(
            sequence: 0,
            kind: .progress,
            status: .completed,
            text: "Checked",
            visibilityAfterCompletion: .collapseIntoThinking
        )
        let normalized = AgentTranscriptValidation.normalized(
            [progress],
            promotingFinalAnswerForCompletedRun: true
        )

        XCTAssertNil(AgentTranscriptValidation.finalAnswer(in: normalized))
    }

    func testSearchCapturesQueryAndUsesSourceTitleInsteadOfProvider() {
        let runID = UUID()
        var adapter = HanlinStreamEventAdapter(runID: runID)
        let events = adapter.events(from: StreamData(
            resources: [Resource(icon: "", title: "Swift", link: "https://swift.org/documentation")],
            searchEngine: "LANGSEARCH",
            search_text: "result text",
            searchQueries: ["modern Swift concurrency"]
        ))
        var accumulator = AgentEventAccumulator(run: AgentRun(id: runID, groupID: UUID()))
        events.forEach { accumulator.apply($0) }
        let activity = AgentActivityComposer.compose(accumulator.run).activities.first { $0.kind == .search }

        XCTAssertEqual(activity?.queries, ["modern Swift concurrency"])
        XCTAssertEqual(activity?.sources.first?.displayTitle, "Swift")
        XCTAssertEqual(activity?.searchProviderName, "LANGSEARCH")
    }

    func testSearchQueryDeduplicationPreservesOrderAndSourceFallsBackToDomain() {
        XCTAssertEqual(
            AgentActivityDeduplicator.uniqueStrings(["First", " first ", "Second"]),
            ["First", "Second"]
        )
        let source = AgentActivitySource(
            title: "",
            url: "https://developer.apple.com/documentation",
            providerName: "LANGSEARCH"
        )
        XCTAssertEqual(source.displayTitle, "developer.apple.com")
    }

    func testEvidenceDeduplicatesNormalizedURLs() {
        let first = AgentEvidenceItem(
            kind: .webPage,
            title: "Example",
            url: "https://EXAMPLE.com/article/?utm_source=test#section",
            wasReturnedToModel: true
        )
        let second = AgentEvidenceItem(
            kind: .webPage,
            title: "Example again",
            url: "https://example.com/article",
            wasReturnedToModel: true
        )
        var accumulator = AgentEvidenceAccumulator()
        accumulator.insert(contentsOf: [first, second])

        XCTAssertEqual(accumulator.items.count, 1)
    }

    func testInlineProcessExcludesResultsFinalAnswerAndTransport() {
        let interim = assistantItem(sequence: 0, text: "Interim", role: .interim)
        var final = assistantItem(sequence: 1, text: "Final", role: .final)
        final.visibilityAfterCompletion = .remainInChat
        let transport = AgentTranscriptItem(
            sequence: 2,
            kind: .progress,
            status: .completed,
            text: "Sending request",
            visibilityAfterCompletion: .collapseIntoThinking
        )
        let result = AgentTranscriptItem(
            sequence: 3,
            kind: .userVisibleToolResult,
            status: .completed,
            visibilityAfterCompletion: .remainInChat
        )

        XCTAssertTrue(AgentInlineProcessPolicy.includes(interim))
        XCTAssertFalse(AgentInlineProcessPolicy.includes(final))
        XCTAssertFalse(AgentInlineProcessPolicy.includes(transport))
        XCTAssertFalse(AgentInlineProcessPolicy.includes(result))
    }

    func testEvidenceDoesNotDependOnResultPresentation() {
        let profile = ToolPresentationProfile.modernNative(
            toolName: "wikipedia_search",
            kind: .search,
            systemImage: "globe",
            runningTitle: "Searching Wikipedia",
            completedTitle: "Searched Wikipedia",
            visibleArgumentKeys: ["query"],
            evidenceKind: .wikipediaArticle
        )
        let call = AgentToolCall.parse(
            id: "call",
            name: "wikipedia_search",
            argumentsJSON: #"{"query":"Swift","result_presentation":"none"}"#,
            presentationProfile: profile
        )
        let block = NativeUIBlock(
            type: .searchResults,
            items: [NativeUIListItem(
                id: "1",
                title: "Swift",
                subtitle: "Wikipedia (en)",
                url: "https://en.wikipedia.org/wiki/Swift_(programming_language)"
            )]
        )
        let result = AgentToolResult(
            modelText: "Swift",
            userText: nil,
            richResultBlocks: [block],
            evidenceItems: [],
            hasLegacyPresentationPayload: false,
            isError: false,
            duration: 0
        )

        XCTAssertFalse(ToolResultPresentationCoordinator.decide(
            call: call,
            profile: profile,
            hasPayload: true
        ).shouldPresent)
        XCTAssertEqual(AgentEvidenceExtractor.extract(call: call, result: result, sequence: 0).count, 1)
    }

    func testRetrievalProfilesCoverFutureEvidenceFamilies() {
        XCTAssertEqual(
            ToolPresentationProfileRegistry.resolve(toolName: "read_github_file").evidence?.kind,
            .githubFile
        )
        XCTAssertEqual(
            ToolPresentationProfileRegistry.resolve(toolName: "retrieve_email").evidence?.kind,
            .email
        )
        XCTAssertEqual(
            ToolPresentationProfileRegistry.resolve(toolName: "search_contacts").evidence?.kind,
            .contact
        )
    }

    func testRetrievedDocumentWithoutURLUsesExternalID() {
        let profile = ToolPresentationProfile.modernNative(
            toolName: "read_document",
            kind: .read,
            systemImage: "doc.text",
            runningTitle: "Reading",
            completedTitle: "Read",
            visibleArgumentKeys: [],
            evidenceKind: .document
        )
        let call = AgentToolCall.parse(
            id: "document-call",
            name: "read_document",
            argumentsJSON: "{}",
            presentationProfile: profile
        )
        let result = AgentToolResult(
            modelText: "Document contents",
            userText: nil,
            richResultBlocks: [NativeUIBlock(id: "document-42", type: .text, title: "Project brief")],
            evidenceItems: [],
            hasLegacyPresentationPayload: false,
            isError: false,
            duration: 0
        )

        let evidence = AgentEvidenceExtractor.extract(call: call, result: result, sequence: 2)
        XCTAssertEqual(evidence.first?.kind, .document)
        XCTAssertEqual(evidence.first?.externalID, "document-42")
    }

    func testFailedAndUnreturnedEvidenceAreNotPresented() {
        let profile = ToolPresentationProfile.modernNative(
            toolName: "read_document",
            kind: .read,
            systemImage: "doc.text",
            runningTitle: "Reading",
            completedTitle: "Read",
            visibleArgumentKeys: [],
            evidenceKind: .document
        )
        let call = AgentToolCall.parse(
            id: "failed-call",
            name: "read_document",
            argumentsJSON: "{}",
            presentationProfile: profile
        )
        let failedResult = AgentToolResult(
            modelText: "Failure",
            userText: nil,
            richResultBlocks: [NativeUIBlock(id: "failed", type: .text, title: "Not retrieved")],
            evidenceItems: [],
            hasLegacyPresentationPayload: false,
            isError: true,
            duration: 0
        )
        XCTAssertTrue(AgentEvidenceExtractor.extract(call: call, result: failedResult, sequence: 0).isEmpty)

        var accumulator = AgentEvidenceAccumulator()
        accumulator.insert(contentsOf: [AgentEvidenceItem(
            kind: .document,
            title: "Hidden",
            externalID: "hidden",
            wasReturnedToModel: false
        )])
        XCTAssertTrue(accumulator.items.isEmpty)
    }

    func testLegacyResourcesAdaptAndSefariaReferencesDeduplicate() {
        let legacy = LegacyResourcesEvidenceAdapter.items(
            from: [Resource(icon: "", title: "Apple", link: "https://apple.com")],
            providerName: "LANGSEARCH"
        )
        XCTAssertEqual(legacy.first?.title, "Apple")
        XCTAssertEqual(legacy.first?.sourceName, "LANGSEARCH")

        var accumulator = AgentEvidenceAccumulator()
        accumulator.insert(contentsOf: [
            AgentEvidenceItem(
                kind: .sefariaSource,
                title: "Genesis 1:1",
                reference: "Genesis 1:1–3",
                wasReturnedToModel: true
            ),
            AgentEvidenceItem(
                kind: .sefariaSource,
                title: "Genesis 1:1",
                reference: " genesis   1:1-3 ",
                wasReturnedToModel: true
            )
        ])
        XCTAssertEqual(accumulator.items.count, 1)
    }

    private func assistantItem(
        sequence: Int,
        text: String,
        role: AgentTranscriptTextRole
    ) -> AgentTranscriptItem {
        AgentTranscriptItem(
            sequence: sequence,
            kind: .assistantText,
            status: .completed,
            text: text,
            textRole: role,
            visibilityAfterCompletion: role == .final ? .remainInChat : .collapseIntoThinking
        )
    }
}
