//
//  AgentEventAccumulator.swift
//  AI_HLY
//

import Foundation

struct AgentEventAccumulator {
    private(set) var run: AgentRun
    private var transcript: AgentTranscriptAccumulator
    private var stepIndexByExternalID: [String: Int] = [:]
    private var nextStepSequence: Int
    private var pendingToolArguments: [String: String] = [:]
    private var toolTranscriptIDByCallID: [String: String] = [:]
    private var callIDByExecutionID: [String: String] = [:]
    private var toolCallByID: [String: AgentToolCall] = [:]
    private var profileByCallID: [String: ToolPresentationProfile] = [:]

    init(run: AgentRun) {
        self.run = run
        transcript = AgentTranscriptAccumulator(items: run.transcriptItems)
        nextStepSequence = (run.steps.map(\.sequence).max() ?? -1) + 1
        for (index, step) in run.steps.enumerated() {
            if let externalID = step.externalID {
                stepIndexByExternalID[externalID] = index
            }
        }
    }

    mutating func apply(_ event: AgentEvent) {
        defer {
            run.transcriptItems = transcript.items
            assert(AgentTranscriptValidation.hasStrictlyIncreasingSequence(run.transcriptItems))
            assert(!AgentTranscriptValidation.containsDuplicateNativeUIResults(run.transcriptItems))
            assert(AgentTranscriptValidation.satisfiesCompletedRunInvariant(run))
        }

        switch event {
        case .runStarted(let metadata):
            guard metadata.id == run.id else { return }
            run.startedAt = metadata.startedAt

        case .reasoningStarted(let metadata):
            let sequence = transcript.allocateSequence()
            let stepID = appendStep(
                externalID: metadata.id,
                sequence: sequence,
                kind: .reasoning,
                title: metadata.title,
                startedAt: metadata.startedAt
            )
            transcript.begin(
                externalID: metadata.id,
                kind: .reasoning,
                activityStepID: stepID,
                startedAt: metadata.startedAt,
                visibility: .collapseIntoThinking,
                sequence: sequence
            )

        case .reasoningDelta(let id, let text):
            append(text, to: id, keyPath: \.output, kind: .reasoning, title: String(localized: "Thinking"))
            transcript.appendText(text, to: id)

        case .reasoningCompleted(let id):
            completeStep(externalID: id)
            transcript.complete(externalID: id)

        case .progressMessage(let progress):
            guard !hasDuplicateProgress(progress.message) else { return }
            let sequence = transcript.allocateSequence()
            let stepID = appendStep(
                externalID: progress.id,
                sequence: sequence,
                kind: .progress,
                title: progress.message,
                summary: progress.message,
                source: progress.source,
                status: .completed,
                startedAt: progress.timestamp,
                completedAt: progress.timestamp
            )
            transcript.begin(
                externalID: progress.id,
                kind: .progress,
                activityStepID: stepID,
                startedAt: progress.timestamp,
                status: .completed,
                text: progress.message,
                visibility: .collapseIntoThinking,
                sequence: sequence
            )

        case .toolCallStarted(let call):
            let profile = call.presentationProfile
            let presentation = ToolPresentationRegistry.presentation(for: call.name, profile: profile)
            let visibleKeys = profile.activity.visibleArgumentKeys
            let userFacingArguments = ToolProgressSummary.userFacingArguments(
                from: call.sanitizedArgumentsJSON,
                visibleKeys: visibleKeys
            )
            let queryItems = profile.activity.kind == .search
                ? ToolProgressSummary.stringValues(
                    from: call.sanitizedArgumentsJSON,
                    keys: visibleKeys
                )
                : []
            let sequence = transcript.allocateSequence()
            let stepID = appendStep(
                externalID: "call:\(call.id)",
                sequence: sequence,
                kind: .toolCall,
                profile: profile,
                resultPresentationRequest: call.resultPresentationRequest,
                title: presentation.title,
                subtitle: call.name,
                summary: call.progressSummary ?? presentation.runningDescription,
                source: call.progressSummarySource ?? .applicationGenerated,
                input: userFacingArguments,
                queryItems: queryItems
            )
            let transcriptID = "tool:\(call.id)"
            toolTranscriptIDByCallID[call.id] = transcriptID
            transcript.begin(
                externalID: transcriptID,
                kind: .toolActivity,
                callID: call.id,
                activityStepID: stepID,
                text: call.progressSummary ?? presentation.runningDescription,
                visibility: .collapseIntoThinking,
                sequence: sequence
            )
            pendingToolArguments[call.id] = userFacingArguments
            toolCallByID[call.id] = call
            profileByCallID[call.id] = profile

        case .toolCallArgumentsDelta(let id, let delta):
            pendingToolArguments[id, default: ""].append(delta)

        case .toolCallCompleted(let call):
            toolCallByID[call.id] = call
            profileByCallID[call.id] = call.presentationProfile
            let externalID = "call:\(call.id)"
            if stepIndexByExternalID[externalID] == nil {
                apply(.toolCallStarted(call))
            }
            updateStep(externalID: externalID) { step in
                step.input = ToolProgressSummary.userFacingArguments(
                    from: call.sanitizedArgumentsJSON,
                    visibleKeys: call.presentationProfile.activity.visibleArgumentKeys
                )
                step.status = .completed
                step.completedAt = Date()
            }

        case .toolExecutionStarted(let execution):
            let presentation = ToolPresentationRegistry.presentation(
                for: execution.name,
                profile: profileByCallID[execution.callID]
            )
            let stepID = appendStep(
                externalID: "execution:\(execution.id)",
                kind: presentation.activityKind,
                profile: profileByCallID[execution.callID],
                resultPresentationRequest: toolCallByID[execution.callID]?.resultPresentationRequest,
                title: presentation.title,
                subtitle: execution.name,
                summary: presentation.runningDescription,
                source: .applicationGenerated,
                startedAt: execution.startedAt,
                input: pendingToolArguments[execution.callID]
            )
            callIDByExecutionID[execution.id] = execution.callID
            let transcriptID = toolTranscriptIDByCallID[execution.callID] ?? "tool:\(execution.callID)"
            toolTranscriptIDByCallID[execution.callID] = transcriptID
            if transcript.item(externalID: transcriptID) == nil {
                transcript.begin(
                    externalID: transcriptID,
                    kind: .toolActivity,
                    callID: execution.callID,
                    activityStepID: stepID,
                    startedAt: execution.startedAt,
                    text: presentation.runningDescription,
                    visibility: .collapseIntoThinking
                )
            } else {
                transcript.update(externalID: transcriptID) { item in
                    item.activityStepID = stepID
                    item.status = .running
                    item.completedAt = nil
                }
            }

        case .toolExecutionProgress(let id, let message):
            let sanitized = ProgressSummarySanitizer.sanitize(message)
            updateStep(externalID: "execution:\(id)") { step in
                step.userFacingSummary = sanitized ?? step.userFacingSummary
            }
            if let callID = callIDByExecutionID[id], let transcriptID = toolTranscriptIDByCallID[callID] {
                transcript.update(externalID: transcriptID) { item in
                    item.text = sanitized ?? item.text
                }
            }

        case .toolExecutionCompleted(let id, let result):
            let callID = callIDByExecutionID[id] ?? id.replacingOccurrences(of: ":execution", with: "")
            let profile = profileByCallID[callID]
            updateStep(externalID: "execution:\(id)") { step in
                step.output = Self.safePreview(result.userText ?? result.modelText)
                step.richResultBlocks = result.richResultBlocks
                if let profile {
                    step.title = result.isError
                        ? profile.activity.failedTitle
                        : profile.activity.completedTitle
                }
                step.status = result.isError ? .failed : .completed
                if result.isError {
                    step.errorDescription = Self.safePreview(result.userText ?? result.modelText)
                }
                step.completedAt = step.startedAt.addingTimeInterval(max(0, result.duration))
            }
            if let transcriptID = toolTranscriptIDByCallID[callID] {
                transcript.complete(externalID: transcriptID, status: result.isError ? .failed : .completed)
            }
            if let call = toolCallByID[callID], let profile {
                let decision = ToolResultPresentationCoordinator.decide(
                    call: call,
                    profile: profile,
                    hasPayload: !result.richResultBlocks.isEmpty || result.hasLegacyPresentationPayload
                )
                if decision.shouldPresent, let rendererKind = decision.rendererKind {
                    transcript.insertUserVisibleResult(
                        callID: callID,
                        toolName: call.name,
                        rendererKind: rendererKind,
                        request: call.resultPresentationRequest,
                        blocks: result.richResultBlocks,
                        completedAt: Date()
                    )
                }
            }

        case .toolExecutionFailed(let id, let error):
            let callID = callIDByExecutionID[id] ?? id.replacingOccurrences(of: ":execution", with: "")
            let failedTitle = profileByCallID[callID]?.activity.failedTitle
            updateStep(externalID: "execution:\(id)") { step in
                step.status = .failed
                if let failedTitle { step.title = failedTitle }
                step.errorDescription = error.message
                step.completedAt = Date()
            }
            if let transcriptID = toolTranscriptIDByCallID[callID] {
                transcript.update(externalID: transcriptID) { item in
                    item.text = error.message
                }
                transcript.complete(externalID: transcriptID, status: .failed)
            }

        case .answerSegmentStarted(let metadata):
            transcript.begin(
                externalID: metadata.id,
                kind: .assistantText,
                startedAt: metadata.startedAt,
                textRole: .provisional,
                visibility: .collapseIntoThinking
            )

        case .answerSegmentDelta(let id, let text):
            transcript.appendText(text, to: id)

        case .answerSegmentEnded(let id, let disposition):
            transcript.endAnswerSegment(externalID: id, disposition: disposition)
            if disposition == .final {
                run.finalAnswer = Self.nonemptyText(transcript.item(externalID: id)?.text)
            }

        case .searchStarted(let id, let title, let query):
            let sequence = transcript.allocateSequence()
            let stepID = appendStep(
                externalID: id,
                sequence: sequence,
                kind: .webSearch,
                title: title,
                summary: title,
                source: .applicationGenerated,
                queryItems: query.map { [$0] } ?? []
            )
            transcript.begin(
                externalID: id,
                kind: .toolActivity,
                activityStepID: stepID,
                text: title,
                visibility: .collapseIntoThinking,
                sequence: sequence
            )

        case .searchCompleted(let id, let sources, let output):
            updateStep(externalID: id) { step in
                step.sourceItems = sources
                step.output = Self.safePreview(output)
                step.status = .completed
                step.completedAt = Date()
            }
            transcript.complete(externalID: id)

        case .runCompleted:
            closeRunningSteps(as: .completed)
            transcript.closeActiveItems(as: .completed)
            run.finalAnswer = transcript.selectFinalAnswerForCompletedRun()
            run.status = .completed
            run.completedAt = Date()

        case .runFailed(let error):
            closeRunningSteps(as: .failed, error: error.message)
            transcript.closeActiveItems(as: .failed)
            appendErrorTranscript(text: error.message, status: .failed, remainInChat: true)
            run.finalAnswer = Self.finalAnswer(from: transcript.items)
            run.status = .failed
            run.completedAt = Date()

        case .runCancelled:
            closeRunningSteps(as: .cancelled)
            transcript.closeActiveItems(as: .cancelled)
            run.finalAnswer = Self.finalAnswer(from: transcript.items)
            run.status = .cancelled
            run.completedAt = Date()
            let timestamp = Date()
            let sequence = transcript.allocateSequence()
            let stepID = appendStep(
                externalID: "cancel:\(run.id.uuidString)",
                sequence: sequence,
                kind: .cancellation,
                title: String(localized: "Cancelled"),
                status: .cancelled,
                startedAt: timestamp,
                completedAt: timestamp
            )
            transcript.begin(
                externalID: "cancel:\(run.id.uuidString)",
                kind: .error,
                activityStepID: stepID,
                startedAt: timestamp,
                status: .cancelled,
                text: String(localized: "Cancelled"),
                visibility: .collapseIntoThinking,
                sequence: sequence
            )
        }
    }

    @discardableResult
    private mutating func appendStep(
        externalID: String?,
        sequence: Int? = nil,
        kind: AgentActivityKind,
        profile: ToolPresentationProfile? = nil,
        resultPresentationRequest: ToolResultPresentationRequest? = nil,
        title: String,
        subtitle: String? = nil,
        summary: String? = nil,
        source: ProgressSummarySource? = nil,
        status: AgentActivityStatus = .running,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        input: String? = nil,
        output: String? = nil,
        queryItems: [String] = [],
        sourceItems: [AgentActivitySource] = []
    ) -> UUID? {
        if let externalID, let index = stepIndexByExternalID[externalID], run.steps.indices.contains(index) {
            return run.steps[index].id
        }
        let assignedSequence = sequence ?? nextStepSequence
        nextStepSequence = max(nextStepSequence, assignedSequence + 1)
        let step = AgentActivityStep(
            externalID: externalID,
            sequence: assignedSequence,
            kind: kind,
            presentationProfile: profile,
            resultPresentationRequest: resultPresentationRequest,
            title: title,
            subtitle: subtitle,
            userFacingSummary: summary,
            summarySource: source,
            status: status,
            startedAt: startedAt,
            completedAt: completedAt,
            input: input,
            output: output,
            queryItems: queryItems,
            sourceItems: sourceItems
        )
        run.steps.append(step)
        if let externalID { stepIndexByExternalID[externalID] = run.steps.count - 1 }
        return step.id
    }

    private mutating func append(
        _ text: String,
        to externalID: String,
        keyPath: WritableKeyPath<AgentActivityStep, String?>,
        kind: AgentActivityKind,
        title: String
    ) {
        if stepIndexByExternalID[externalID] == nil {
            appendStep(externalID: externalID, kind: kind, title: title)
        }
        updateStep(externalID: externalID) { step in
            step[keyPath: keyPath] = (step[keyPath: keyPath] ?? "") + text
        }
    }

    private mutating func completeStep(externalID: String) {
        updateStep(externalID: externalID) { step in
            step.status = .completed
            step.completedAt = Date()
        }
    }

    private mutating func updateStep(externalID: String, update: (inout AgentActivityStep) -> Void) {
        guard let index = stepIndexByExternalID[externalID], run.steps.indices.contains(index) else { return }
        update(&run.steps[index])
    }

    private func hasDuplicateProgress(_ message: String) -> Bool {
        run.steps.reversed().prefix(3).contains {
            AgentActivityDeduplicator.normalized($0.userFacingSummary) == AgentActivityDeduplicator.normalized(message)
        }
    }

    private mutating func closeRunningSteps(as status: AgentActivityStatus, error: String? = nil) {
        let completion = Date()
        for index in run.steps.indices where run.steps[index].status == .running || run.steps[index].status == .pending {
            run.steps[index].status = status
            run.steps[index].completedAt = completion
            if status == .failed { run.steps[index].errorDescription = error }
        }
    }

    private mutating func appendErrorTranscript(text: String, status: AgentActivityStatus, remainInChat: Bool) {
        let id = "error:\(run.id.uuidString):\(transcript.nextSequence)"
        transcript.begin(
            externalID: id,
            kind: .error,
            status: status,
            text: text,
            visibility: remainInChat ? .remainInChat : .collapseIntoThinking
        )
    }

    private static func safePreview(_ value: String?) -> String? {
        guard let value = nonemptyText(value) else { return nil }
        return String(value.prefix(1_000))
    }

    private static func nonemptyText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

}

@MainActor
final class AgentRunCoordinator {
    let runID: UUID
    private var accumulator: AgentEventAccumulator

    var run: AgentRun { accumulator.run }

    init(groupID: UUID, providerID: String?, modelID: String?) {
        let run = AgentRun(groupID: groupID, providerID: providerID, modelID: modelID)
        runID = run.id
        accumulator = AgentEventAccumulator(run: run)
        accumulator.apply(.runStarted(AgentRunMetadata(
            id: run.id,
            groupID: groupID,
            providerID: providerID,
            modelID: modelID,
            startedAt: run.startedAt
        )))
    }

    func consume(_ events: [AgentEvent]) {
        guard accumulator.run.status == .running else { return }
        for event in events { accumulator.apply(event) }
    }

    func complete() { consume([.runCompleted]) }
    func cancel() { consume([.runCancelled]) }
    func fail(_ error: Error) { consume([.runFailed(AgentSafeError(error))]) }
}
