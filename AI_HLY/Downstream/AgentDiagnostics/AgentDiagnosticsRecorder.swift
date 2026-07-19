import CryptoKit
import Foundation

actor AgentDiagnosticsRecorder {
    private(set) var session: AgentDiagnosticsSession
    private let directoryURL: URL
    private let jsonURL: URL
    private let textURL: URL
    private let encoder: JSONEncoder

    static func start(
        runID: UUID,
        groupID: UUID,
        providerID: String,
        modelID: String,
        endpointKind: String = "chatCompletions"
    ) async -> AgentDiagnosticsRecorder? {
        guard AgentDiagnosticsConfiguration.level != .off,
              let directory = NativeToolTraceLogger.shared.diagnosticsDirectoryURL else { return nil }
        let recorder = AgentDiagnosticsRecorder(
            runID: runID,
            groupID: groupID,
            providerID: providerID,
            modelID: modelID,
            endpointKind: endpointKind,
            directoryURL: directory,
            level: AgentDiagnosticsConfiguration.level
        )
        await recorder.persist()
        await recorder.cleanupRetention()
        let sessionPath = (await recorder.fileURLs()).json.path
        NativeToolTraceLogger.shared.log(
            "AgentRunStarted",
            ["runID": String(runID.uuidString.prefix(8)), "sessionPath": sessionPath],
            conversationID: groupID.uuidString
        )
        return recorder
    }

    private init(
        runID: UUID,
        groupID: UUID,
        providerID: String,
        modelID: String,
        endpointKind: String,
        directoryURL: URL,
        level: AgentDiagnosticsLevel
    ) {
        let now = Date()
        let bundle = Bundle.main
        session = AgentDiagnosticsSession(
            id: UUID(),
            runID: runID,
            groupID: groupID,
            startedAt: now,
            lastUpdatedAt: now,
            providerID: providerID,
            modelID: modelID,
            endpointKind: endpointKind,
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            status: "running",
            isComplete: false,
            level: level,
            rounds: [],
            totals: .unavailable,
            efficiency: AgentEfficiencyReport()
        )
        self.directoryURL = directoryURL
        let stamp = Self.fileDateFormatter.string(from: now)
        let shortID = String(runID.uuidString.prefix(8)).lowercased()
        let base = "agent-session-\(stamp)-\(shortID)"
        jsonURL = directoryURL.appendingPathComponent(base).appendingPathExtension("json")
        textURL = directoryURL.appendingPathComponent(base).appendingPathExtension("txt")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
    }

    @discardableResult
    func beginRound(index: Int, trigger: String, requestObject: Any) async -> UUID {
        let sanitizedJSON = AgentDiagnosticsRedactor.sanitizedJSONString(from: requestObject, pretty: true)
        let metadataOnly = session.level != .fullLocalDebug
        let requestText = metadataOnly ? nil : sanitizedJSON
        let request = AgentDiagnosticsModelRequest(
            sanitizedJSON: requestText,
            byteCount: sanitizedJSON.utf8.count,
            contentHash: Self.sha256(sanitizedJSON),
            composition: Self.composition(from: requestObject)
        )
        let round = AgentDiagnosticsRound(
            id: UUID(),
            index: index,
            startedAt: Date(),
            trigger: trigger,
            request: request,
            response: AgentDiagnosticsModelResponse(streamEventCount: 0),
            toolCalls: [],
            usage: .unavailable
        )
        session.rounds.append(round)
        updateDerivedValues()
        await persist()
        trace("ModelRoundStarted", roundIndex: index)
        trace("ModelRequestPrepared", roundIndex: index, fields: ["bytes": request.byteCount, "hash": request.contentHash])
        return round.id
    }

    func responseStarted(roundID: UUID, httpStatus: Int?, providerRequestID: String?) async {
        let responseStartedAt = Date()
        updateRound(roundID) { round in
            round.response.httpStatus = httpStatus
            round.response.providerRequestID = providerRequestID
            round.response.timeToFirstToken = responseStartedAt.timeIntervalSince(round.startedAt)
        }
        await persist()
        trace("ModelResponseStarted", roundID: roundID)
    }

    func recordStreamEvent(roundID: UUID, visibleContent: String?, visibleReasoningSummary: String?) {
        let shouldStoreFullContent = session.level == .fullLocalDebug

        updateRound(roundID) { round in
            round.response.streamEventCount += 1

            guard shouldStoreFullContent else { return }

            if let visibleContent {
                round.response.visibleContent = (round.response.visibleContent ?? "") + visibleContent
            }
            if let visibleReasoningSummary {
                round.response.visibleReasoningSummary =
                    (round.response.visibleReasoningSummary ?? "") + visibleReasoningSummary
            }
        }
    }

    func recordToolCall(roundID: UUID, call: AgentToolCall) async {
        let argumentHash = Self.sha256(call.sanitizedArgumentsJSON)
        var duplicateOf: String?
        for round in session.rounds {
            duplicateOf = round.toolCalls.first(where: {
                $0.toolName == call.name && Self.sha256($0.argumentsAfterMetadataRemoval ?? "") == argumentHash
            })?.callID
            if duplicateOf != nil { break }
        }
        let full = session.level == .fullLocalDebug
        let diagnosticsCall = AgentDiagnosticsToolCall(
            callID: call.id,
            toolName: call.name,
            progressSummary: call.progressSummary,
            presentationProfileIdentity: call.presentationProfile.identity,
            resultPresentationRequested: call.resultPresentationRequest.rawValue,
            resultPresentationEffective: nil,
            resultRendererKind: nil,
            resultPresentationSuppressed: nil,
            suppressionReason: nil,
            requestedAt: Date(),
            executionStartedAt: Date(),
            status: "running",
            rawArgumentsBeforeSanitization: full ? AgentDiagnosticsRedactor.sanitize(call.rawArgumentsJSON) : nil,
            argumentsAfterMetadataRemoval: full ? AgentDiagnosticsRedactor.sanitize(call.sanitizedArgumentsJSON) : argumentHash,
            resultForModel: nil,
            resultForUser: nil,
            resultByteCount: 0,
            error: nil,
            wasDeduplicated: duplicateOf != nil,
            duplicateOfCallID: duplicateOf
        )
        updateRound(roundID) { $0.toolCalls.append(diagnosticsCall) }
        updateDerivedValues()
        await persist()
        trace("ToolCallReceived", roundID: roundID, toolName: call.name, fields: ["callID": call.id])
        trace("ToolExecutionStarted", roundID: roundID, toolName: call.name)
    }

    func completeToolCall(
        roundID: UUID,
        callID: String,
        resultForModel: String,
        resultForUser: String?,
        duration: TimeInterval,
        error: String? = nil,
        presentationDecision: ToolResultPresentationDecision? = nil
    ) async {
        let shouldStoreFullContent = session.level == .fullLocalDebug
        let completedAt = Date()
        let sanitizedError = error.map(AgentDiagnosticsRedactor.sanitize)
        let sanitizedModelResult = shouldStoreFullContent
            ? AgentDiagnosticsRedactor.sanitize(resultForModel)
            : nil
        let sanitizedUserResult = shouldStoreFullContent
            ? resultForUser.map(AgentDiagnosticsRedactor.sanitize)
            : nil
        let resultByteCount = resultForModel.utf8.count

        updateRound(roundID) { round in
            guard let index = round.toolCalls.firstIndex(where: { $0.callID == callID }) else { return }

            var call = round.toolCalls[index]
            call.executionCompletedAt = completedAt
            call.status = error == nil ? "completed" : "failed"
            call.resultByteCount = resultByteCount
            call.error = sanitizedError
            call.resultForModel = sanitizedModelResult
            call.resultForUser = sanitizedUserResult
            call.resultPresentationEffective = presentationDecision?.shouldPresent
            call.resultRendererKind = presentationDecision?.rendererKind?.rawValue
            call.resultPresentationSuppressed = presentationDecision.map { !$0.shouldPresent }
            call.suppressionReason = presentationDecision?.suppressionReason?.rawValue
            round.toolCalls[index] = call
        }
        updateDerivedValues()
        await persist()
        trace(
            error == nil ? "ToolExecutionCompleted" : "ToolExecutionFailed",
            roundID: roundID,
            fields: ["callID": callID, "duration": duration, "resultBytes": resultByteCount]
        )
    }

    func finishRound(
        roundID: UUID,
        finishReason: String?,
        usage: AgentTokenUsage?,
        error: String? = nil
    ) async {
        let completedAt = Date()
        let sanitizedError = error.map(AgentDiagnosticsRedactor.sanitize)

        updateRound(roundID) { round in
            round.completedAt = completedAt
            round.response.finishReason = finishReason
            round.response.error = sanitizedError
            round.response.totalLatency = completedAt.timeIntervalSince(round.startedAt)
            if let usage {
                round.usage = usage
            } else {
                let input = AgentTokenEstimator.estimate(round.request.sanitizedJSON ?? "")
                let output = AgentTokenEstimator.estimate((round.response.visibleContent ?? "") + (round.response.visibleReasoningSummary ?? ""))
                round.usage = AgentTokenUsage(inputTokens: input, outputTokens: output, source: .locallyEstimated)
            }
        }
        updateDerivedValues()
        await persist()
        trace("ModelRoundCompleted", roundID: roundID)
    }

    func complete(status: String, error: String? = nil) async {
        session.completedAt = Date()
        session.lastUpdatedAt = Date()
        session.status = status
        session.isComplete = true
        if let error { session.efficiency.warnings.append(AgentDiagnosticsRedactor.sanitize(error)) }
        updateDerivedValues()
        await persist()
        trace(status == "completed" ? "AgentRunCompleted" : "AgentRun\(status.capitalized)")
    }

    func fileURLs() -> (json: URL, text: URL) { (jsonURL, textURL) }

    private func updateRound(_ id: UUID, update: (inout AgentDiagnosticsRound) -> Void) {
        guard let index = session.rounds.firstIndex(where: { $0.id == id }) else { return }

        var round = session.rounds[index]
        update(&round)
        session.rounds[index] = round
        session.lastUpdatedAt = Date()
    }

    private func updateDerivedValues() {
        session.totals = session.rounds.map(\.usage).reduce(.unavailable, +)
        var report = AgentEfficiencyReport()
        report.modelRoundCount = session.rounds.count
        let calls = session.rounds.flatMap(\.toolCalls)
        report.toolCallCount = calls.count
        report.uniqueToolCallCount = calls.filter { !$0.wasDeduplicated }.count
        report.duplicateToolCallCount = calls.filter(\.wasDeduplicated).count
        report.totalInputTokens = session.totals.inputTokens
        report.totalOutputTokens = session.totals.outputTokens
        if let initial = session.rounds.first?.usage.inputTokens, initial > 0,
           let total = session.totals.inputTokens {
            report.tokenAmplificationRatio = Double(total) / Double(initial)
        }
        report.largestToolResultCharacters = calls.map(\.resultByteCount).max() ?? 0
        report.historyGrowthByRound = session.rounds.map(\.request.composition.historyCharacters)
        report.toolSchemaOverheadTokens = session.rounds.reduce(0) { $0 + $1.request.composition.estimatedTokensBySection["toolSchemas", default: 0] }
        report.resultPresentationSchemaToolCount = session.rounds.compactMap {
            $0.request.composition.resultPresentationSchemaToolCount
        }.max()
        report.resultPresentationSchemaEstimatedTokens = session.rounds.compactMap {
            $0.request.composition.resultPresentationSchemaEstimatedTokens
        }.max()
        report.failedToolCount = calls.filter { $0.status == "failed" }.count
        report.totalDuration = session.completedAt.map { $0.timeIntervalSince(session.startedAt) }
        if report.duplicateToolCallCount > 0 { report.warnings.append("Repeated identical tool calls detected") }
        if report.modelRoundCount > 8 { report.warnings.append("High model round count") }
        if report.toolSchemaOverheadTokens > 8_000 { report.warnings.append("Excessive tool schema overhead") }
        if report.largestToolResultCharacters > 100_000 { report.warnings.append("Very large tool result") }
        session.efficiency = report
    }

    private func persist() async {
        let snapshot = session

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try encoder.encode(snapshot)
            try data.write(to: jsonURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            let readable = Self.readableText(snapshot)
            try Data(readable.utf8).write(to: textURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        } catch {
            NativeToolTraceLogger.shared.logError("AgentDiagnosticsWriteFailed", error: error)
        }
    }

    private func cleanupRetention() async {
        let limit = AgentDiagnosticsConfiguration.retentionLimit
        guard limit > 0,
              let files = try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else { return }
        let sessionJSON = files.filter { $0.lastPathComponent.hasPrefix("agent-session-") && $0.pathExtension == "json" }
            .sorted {
                let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhs > rhs
            }
        for oldJSON in sessionJSON.dropFirst(limit) {
            try? FileManager.default.removeItem(at: oldJSON)
            try? FileManager.default.removeItem(at: oldJSON.deletingPathExtension().appendingPathExtension("txt"))
        }
    }

    private func trace(
        _ event: String,
        roundID: UUID? = nil,
        roundIndex: Int? = nil,
        toolName: String? = nil,
        fields: [String: Any] = [:]
    ) {
        let index = roundIndex ?? roundID.flatMap { id in session.rounds.first(where: { $0.id == id })?.index }
        var metadata = fields
        metadata["runID"] = String(session.runID.uuidString.prefix(8))
        metadata["provider"] = session.providerID
        metadata["model"] = session.modelID
        metadata["sessionPath"] = jsonURL.path
        NativeToolTraceLogger.shared.log(
            event,
            metadata,
            requestID: session.runID.uuidString,
            conversationID: session.groupID.uuidString,
            modelStep: index,
            toolName: toolName
        )
    }

    private static func composition(from request: Any) -> AgentPromptCompositionMetrics {
        guard let dictionary = request as? [String: Any] else { return AgentPromptCompositionMetrics() }
        let messages = dictionary["messages"] as? [[String: Any]] ?? []
        let tools = dictionary["tools"] as? [[String: Any]] ?? []
        let texts = messages.map { message -> (String, String) in
            let role = message["role"] as? String ?? ""
            let content = stringify(message["content"])
            return (role, content)
        }
        var result = AgentPromptCompositionMetrics()
        result.systemCharacters = texts.filter { $0.0 == "system" || $0.0 == "developer" }.map { $0.1.count }.reduce(0, +)
        result.currentUserCharacters = texts.last(where: { $0.0 == "user" })?.1.count ?? 0
        result.toolResultCharacters = texts.filter { $0.0 == "tool" || $0.1.contains("result has been obtained") }.map { $0.1.count }.reduce(0, +)
        result.historyCharacters = max(0, texts.map { $0.1.count }.reduce(0, +) - result.currentUserCharacters)
        result.toolSchemaCharacters = sanitizedJSONString(from: tools).count
        let resultPresentationSchemas = tools.filter(Self.hasResultPresentationProperty)
        result.resultPresentationSchemaToolCount = resultPresentationSchemas.count
        result.resultPresentationSchemaEstimatedTokens = AgentTokenEstimator.estimate(
            sanitizedJSONString(from: resultPresentationSchemas)
        )
        result.estimatedTokensBySection = [
            "system": AgentTokenEstimator.estimate(String(repeating: "x", count: result.systemCharacters)),
            "toolSchemas": AgentTokenEstimator.estimate(String(repeating: "x", count: result.toolSchemaCharacters)),
            "history": AgentTokenEstimator.estimate(String(repeating: "x", count: result.historyCharacters)),
            "currentUser": AgentTokenEstimator.estimate(String(repeating: "x", count: result.currentUserCharacters)),
            "toolResults": AgentTokenEstimator.estimate(String(repeating: "x", count: result.toolResultCharacters))
        ]
        return result
    }

    private static func hasResultPresentationProperty(_ schema: [String: Any]) -> Bool {
        let objectSchema: [String: Any]
        if let function = schema["function"] as? [String: Any] {
            objectSchema = function["parameters"] as? [String: Any] ?? [:]
        } else if let input = schema["input_schema"] as? [String: Any] {
            objectSchema = input
        } else {
            objectSchema = schema["parameters"] as? [String: Any] ?? schema
        }
        let properties = objectSchema["properties"] as? [String: Any] ?? [:]
        return properties[ToolSchemaDecorator.resultPresentationKey] != nil
    }

    private static func stringify(_ value: Any?) -> String {
        guard let value else { return "" }
        if let string = value as? String { return string }
        return sanitizedJSONString(from: value)
    }

    private static func sanitizedJSONString(from value: Any) -> String {
        AgentDiagnosticsRedactor.sanitizedJSONString(from: value)
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func readableText(_ session: AgentDiagnosticsSession) -> String {
        var lines = [
            "Session", "Run ID: \(session.runID.uuidString)", "Provider: \(session.providerID)",
            "Model: \(session.modelID)", "Start time: \(ISO8601DateFormatter().string(from: session.startedAt))",
            "End time: \(session.completedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "—")", "Status: \(session.status)", ""
        ]
        for round in session.rounds.sorted(by: { $0.index < $1.index }) {
            lines += [
                "Round \(round.index)", "Trigger: \(round.trigger)",
                "Request bytes: \(round.request.byteCount)", "Request hash: \(round.request.contentHash)"
            ]
            if let request = round.request.sanitizedJSON { lines += ["", "Request", request] }
            lines += ["", "Provider response"]
            if let reasoning = round.response.visibleReasoningSummary { lines += ["Visible reasoning summary", reasoning] }
            if let content = round.response.visibleContent { lines.append(content) }
            lines += ["Finish reason: \(round.response.finishReason ?? "—")", "Token usage: \(round.usage.source.rawValue)"]
            for tool in round.toolCalls {
                lines += [
                    "", "Tool execution", "Tool name: \(tool.toolName)", "Call ID: \(tool.callID)",
                    "Status: \(tool.status)",
                    "Presentation profile: \(tool.presentationProfileIdentity ?? "—")",
                    "Result requested: \(tool.resultPresentationRequested ?? "none")",
                    "Result presented: \(tool.resultPresentationEffective.map(String.init) ?? "—")",
                    "Result renderer: \(tool.resultRendererKind ?? "—")",
                    "Suppression reason: \(tool.suppressionReason ?? "—")"
                ]
                if let arguments = tool.argumentsAfterMetadataRemoval { lines += ["Arguments", arguments] }
                if let result = tool.resultForModel { lines += ["Result returned to model", result] }
            }
            lines.append("")
        }
        lines += [
            "Token totals", "Input: \(session.totals.inputTokens.map(String.init) ?? "unavailable")",
            "Output: \(session.totals.outputTokens.map(String.init) ?? "unavailable")",
            "Source: \(session.totals.source.rawValue)", "", "Efficiency report",
            "Model rounds: \(session.efficiency.modelRoundCount)", "Tool calls: \(session.efficiency.toolCallCount)",
            "Duplicate tool calls: \(session.efficiency.duplicateToolCallCount)", "Warnings: \(session.efficiency.warnings.joined(separator: "; "))"
        ]
        return AgentDiagnosticsRedactor.sanitize(lines.joined(separator: "\n"))
    }

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return formatter
    }()
}
