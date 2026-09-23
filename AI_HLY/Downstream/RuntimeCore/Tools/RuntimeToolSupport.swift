import Foundation

enum RuntimeToolSupport {
    static func profile(name: String, image: String, running: String, completed: String, arguments: [String]) -> ToolPresentationProfile {
        ToolPresentationProfile(
            identity: "runtime.\(name)",
            activity: ToolActivityPresentationDescriptor(
                kind: .execute,
                systemImage: image,
                runningTitle: RuntimeL10n.string(running),
                completedTitle: RuntimeL10n.string(completed),
                failedTitle: RuntimeL10n.string("Runtime execution failed"),
                visibleArgumentKeys: arguments
            ),
            result: ToolResultPresentationDescriptor(rendererKind: .modernNative, supportsCard: true),
            resultDisplayPolicy: .modelControlled
        )
    }

    static func limits(_ arguments: [String: Any]) throws -> RuntimeExecutionLimits {
        RuntimeExecutionLimits(
            timeout: .seconds(
                try NativeToolJSON.strictInt(
                    arguments,
                    "timeout_seconds",
                    default: 30,
                    range: 1...300
                )
            )
        )
    }

    static func result(
        _ result: RuntimeExecutionResult,
        title: String,
        systemImage: String,
        runtimeKind: RuntimeKind,
        argumentKeys: [String]
    ) -> NativeToolResult {
        let renderedValue = result.value.flatMap(renderValue)
        var sections: [String] = []
        if !result.stdout.isEmpty { sections.append(result.stdout) }
        if !result.stderr.isEmpty { sections.append("stderr:\n\(result.stderr)") }
        if let renderedValue { sections.append("value: \(renderedValue)") }
        let body = sections.joined(separator: "\n")
        let outcome = outcome(for: result)
        var diagnostics = NativeToolExecutionDiagnostics(
            backendRoute: "host-services/runtime-broker",
            source: "native",
            runtimeKind: runtimeKind.rawValue,
            failureCategory: outcome.isSuccess ? nil : outcome.rawValue,
            argumentKeys: argumentKeys.sorted(),
            capabilityDecision: "allowed",
            availabilityDecision: "allowed",
            exitCode: result.exitCode,
            didTimeOut: result.didTimeOut,
            wasCancelled: result.wasCancelled,
            outputWasTruncated: result.outputWasTruncated,
            stdoutByteCount: result.stdout.utf8.count,
            stderrByteCount: result.stderr.utf8.count,
            valueType: result.value.map(valueType),
            callerIdentity: "agent"
        )
        let fallback = outcome.isSuccess
            ? RuntimeL10n.string("Execution completed without output.")
            : failureMessage(for: outcome, exitCode: result.exitCode)
        let block = NativeUIBlock(
            type: outcome.isSuccess ? .card : .error,
            title: RuntimeL10n.string(title),
            subtitle: result.exitCode.map { RuntimeL10n.format("Exit code: %d", $0) },
            body: body.isEmpty ? fallback : body,
            footnote: RuntimeL10n.format("Duration: %d ms", result.durationMilliseconds),
            systemImage: systemImage,
            actions: body.isEmpty ? [] : [.init(type: .copyText, title: RuntimeL10n.string("Copy output"), systemImage: "doc.on.doc", text: body)]
        )
        let modelText = body.isEmpty ? fallback : body
        diagnostics.modelResultByteCount = modelText.utf8.count
        diagnostics.userResultByteCount = body.utf8.count
        diagnostics.uiBlockTypes = [outcome.isSuccess ? "card" : "error"]
        return NativeToolResult(
            modelText: modelText,
            userText: body.isEmpty ? fallback : body,
            uiBlocks: [block],
            outcome: outcome,
            diagnostics: diagnostics
        )
    }

    static func failure(
        _ error: Error,
        title: String,
        runtimeKind: RuntimeKind? = nil,
        argumentKeys: [String] = []
    ) -> NativeToolResult {
        let outcome = outcome(for: error)
        return NativeToolResult(
            modelText: "\(RuntimeL10n.string(title)): \(error.localizedDescription)",
            userText: error.localizedDescription,
            uiBlocks: [.init(type: .error, title: RuntimeL10n.string(title), body: error.localizedDescription, systemImage: "exclamationmark.triangle")],
            outcome: outcome,
            diagnostics: NativeToolExecutionDiagnostics(
                backendRoute: "host-services/runtime-broker",
                source: "native",
                runtimeKind: runtimeKind?.rawValue,
                failureCategory: outcome.rawValue,
                argumentKeys: argumentKeys.sorted(),
                capabilityDecision: outcome == .rejectedByCapability ? "denied" : nil,
                availabilityDecision: outcome == .rejectedByAvailability ? "denied" : nil,
                didTimeOut: outcome == .timedOut,
                wasCancelled: outcome == .cancelled,
                callerIdentity: "agent"
            )
        )
    }

    private static func outcome(for result: RuntimeExecutionResult) -> NativeToolExecutionOutcome {
        if result.didTimeOut { return .timedOut }
        if result.wasCancelled { return .cancelled }
        if let exitCode = result.exitCode, exitCode != 0 { return .failed }
        return .succeeded
    }

    private static func outcome(for error: Error) -> NativeToolExecutionOutcome {
        if error is CancellationError { return .cancelled }
        if let error = error as? NativeToolJSON.JSONError {
            switch error {
            case .invalidUTF8, .invalidObject, .missingRequiredString,
                 .invalidType, .unknownArguments, .invalidValue:
                return .invalidArguments
            }
        }
        if let error = error as? HanlinHostServiceError {
            switch error {
            case .runtimeDisabledByUser, .runtimeUnavailable, .runtimeRestartRequired:
                return .rejectedByAvailability
            case .capabilityNotGranted, .systemAuthorizationDenied:
                return .rejectedByCapability
            case .cancelled:
                return .cancelled
            case .timeout:
                return .timedOut
            case .invalidCallerContext, .pathOutOfScope, .invalidRequest:
                return .invalidArguments
            case .systemCapabilityUnavailable, .sqliteFailure, .unsupportedByPlatform, .quotaExceeded:
                return .failed
            }
        }
        if let error = error as? RuntimeCoreError {
            switch error {
            case .executionTimedOut: return .timedOut
            case .executionCancelled: return .cancelled
            case .runtimeUnavailable, .appRestartRequired: return .rejectedByAvailability
            case .invalidPath, .pathEscapesRoot, .symbolicLinkRejected, .invalidIdentifier,
                 .invalidEnvironmentName, .reservedEnvironmentName, .invalidDependencyManifest,
                 .invalidRequest:
                return .invalidArguments
            case .outputLimitExceeded, .requestFailed, .runtimeFailure:
                return .failed
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut {
            return .timedOut
        }
        return .failed
    }

    private static func renderValue(_ value: RuntimeJSONValue) -> String? {
        guard value != .null,
              let data = try? JSONEncoder().encode(value) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func valueType(_ value: RuntimeJSONValue) -> String {
        switch value {
        case .null: "null"
        case .boolean: "boolean"
        case .number: "number"
        case .string: "string"
        case .array: "array"
        case .object: "object"
        }
    }

    private static func failureMessage(
        for outcome: NativeToolExecutionOutcome,
        exitCode: Int?
    ) -> String {
        switch outcome {
        case .timedOut: RuntimeL10n.string("Execution timed out.")
        case .cancelled: RuntimeL10n.string("Execution was cancelled.")
        case .failed:
            exitCode.map { RuntimeL10n.format("Execution failed with exit code %d.", $0) }
                ?? RuntimeL10n.string("Runtime execution failed")
        case .invalidArguments: RuntimeL10n.string("The runtime arguments are invalid.")
        case .rejectedByCapability: RuntimeL10n.string("Runtime capability was denied.")
        case .rejectedByAvailability: RuntimeL10n.string("The runtime is unavailable.")
        case .succeeded: RuntimeL10n.string("Execution completed without output.")
        }
    }
}
