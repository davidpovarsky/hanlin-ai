//
//  AgentEventAccumulator.swift
//  AI_HLY
//

import Foundation

struct AgentEventAccumulator {
    private(set) var run: AgentRun
    private var stepIndexByExternalID: [String: Int] = [:]
    private var nextSequence = 0
    private var pendingToolArguments: [String: String] = [:]

    init(run: AgentRun) {
        self.run = run
    }

    mutating func apply(_ event: AgentEvent) {
        switch event {
        case .runStarted(let metadata):
            guard metadata.id == run.id else { return }
            run.startedAt = metadata.startedAt

        case .reasoningStarted(let metadata):
            upsertStep(externalID: metadata.id, kind: .reasoning, title: metadata.title, startedAt: metadata.startedAt)

        case .reasoningDelta(let id, let text):
            append(text, to: id, keyPath: \.output, kind: .reasoning, title: String(localized: "Thinking"))

        case .reasoningCompleted(let id):
            completeStep(externalID: id)

        case .progressMessage(let progress):
            guard !hasDuplicateProgress(progress.message) else { return }
            appendStep(
                externalID: progress.id,
                kind: .progress,
                title: String(localized: "Progress update"),
                summary: progress.message,
                source: progress.source,
                status: .completed,
                startedAt: progress.timestamp,
                completedAt: progress.timestamp
            )

        case .toolCallStarted(let call):
            let presentation = ToolPresentationRegistry.presentation(for: call.name)
            let userFacingArguments = ToolProgressSummary.userFacingArguments(from: call.sanitizedArgumentsJSON)
            appendStep(
                externalID: "call:\(call.id)",
                kind: .toolCall,
                title: presentation.title,
                subtitle: call.name,
                summary: call.progressSummary ?? presentation.runningDescription,
                source: call.progressSummarySource ?? .applicationGenerated,
                input: userFacingArguments
            )
            pendingToolArguments[call.id] = userFacingArguments

        case .toolCallArgumentsDelta(let id, let delta):
            pendingToolArguments[id, default: ""].append(delta)

        case .toolCallCompleted(let call):
            let externalID = "call:\(call.id)"
            if stepIndexByExternalID[externalID] == nil {
                apply(.toolCallStarted(call))
            }
            updateStep(externalID: externalID) { step in
                step.input = ToolProgressSummary.userFacingArguments(from: call.sanitizedArgumentsJSON)
                step.status = .completed
                step.completedAt = Date()
            }

        case .toolExecutionStarted(let execution):
            let presentation = ToolPresentationRegistry.presentation(for: execution.name)
            appendStep(
                externalID: "execution:\(execution.id)",
                kind: presentation.activityKind,
                title: presentation.title,
                subtitle: execution.name,
                summary: presentation.runningDescription,
                source: .applicationGenerated,
                startedAt: execution.startedAt,
                input: pendingToolArguments[execution.callID]
            )

        case .toolExecutionProgress(let id, let message):
            updateStep(externalID: "execution:\(id)") { step in
                step.userFacingSummary = ProgressSummarySanitizer.sanitize(message) ?? step.userFacingSummary
            }

        case .toolExecutionCompleted(let id, let result):
            updateStep(externalID: "execution:\(id)") { step in
                step.output = result.userText ?? result.modelText
                step.richResultBlocks = result.richResultBlocks
                step.status = .completed
                step.completedAt = step.startedAt.addingTimeInterval(max(0, result.duration))
            }

        case .toolExecutionFailed(let id, let error):
            updateStep(externalID: "execution:\(id)") { step in
                step.status = .failed
                step.errorDescription = error.message
                step.completedAt = Date()
            }

        case .answerStarted:
            if run.finalAnswer == nil { run.finalAnswer = "" }

        case .answerDelta(_, let text):
            run.finalAnswer = (run.finalAnswer ?? "") + text

        case .answerCompleted:
            break

        case .searchStarted(let id, let title, let query):
            appendStep(
                externalID: id,
                kind: .webSearch,
                title: title,
                summary: title,
                source: .applicationGenerated,
                queryItems: query.map { [$0] } ?? []
            )

        case .searchCompleted(let id, let sources, let output):
            updateStep(externalID: id) { step in
                step.sourceItems = sources
                step.output = output
                step.status = .completed
                step.completedAt = Date()
            }

        case .runCompleted:
            closeRunningSteps(as: .completed)
            run.status = .completed
            run.completedAt = Date()

        case .runFailed(let error):
            closeRunningSteps(as: .failed, error: error.message)
            run.status = .failed
            run.completedAt = Date()

        case .runCancelled:
            closeRunningSteps(as: .cancelled)
            run.status = .cancelled
            run.completedAt = Date()
            appendStep(
                externalID: "cancel:\(run.id.uuidString)",
                kind: .cancellation,
                title: String(localized: "Cancelled"),
                status: .cancelled,
                startedAt: Date(),
                completedAt: Date()
            )
        }
    }

    private mutating func appendStep(
        externalID: String?,
        kind: AgentActivityKind,
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
    ) {
        if let externalID, stepIndexByExternalID[externalID] != nil { return }
        let step = AgentActivityStep(
            externalID: externalID,
            sequence: nextSequence,
            kind: kind,
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
        nextSequence += 1
    }

    private mutating func upsertStep(externalID: String, kind: AgentActivityKind, title: String, startedAt: Date) {
        guard stepIndexByExternalID[externalID] == nil else { return }
        appendStep(externalID: externalID, kind: kind, title: title, startedAt: startedAt)
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
        run.steps.reversed().prefix(3).contains { $0.userFacingSummary == message }
    }

    private mutating func closeRunningSteps(as status: AgentActivityStatus, error: String? = nil) {
        let completion = Date()
        for index in run.steps.indices where run.steps[index].status == .running || run.steps[index].status == .pending {
            run.steps[index].status = status
            run.steps[index].completedAt = completion
            if status == .failed { run.steps[index].errorDescription = error }
        }
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
        accumulator.apply(.runStarted(AgentRunMetadata(id: run.id, groupID: groupID, providerID: providerID, modelID: modelID, startedAt: run.startedAt)))
    }

    func consume(_ events: [AgentEvent]) {
        guard accumulator.run.status == .running else { return }
        for event in events { accumulator.apply(event) }
    }

    func complete() { consume([.runCompleted]) }
    func cancel() { consume([.runCancelled]) }
    func fail(_ error: Error) { consume([.runFailed(AgentSafeError(error))]) }
}
