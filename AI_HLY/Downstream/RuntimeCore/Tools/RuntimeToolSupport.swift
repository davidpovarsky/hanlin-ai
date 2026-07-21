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

    static func limits(_ arguments: [String: Any]) -> RuntimeExecutionLimits {
        RuntimeExecutionLimits(timeout: .seconds(NativeToolJSON.int(arguments, "timeout_seconds", default: 30)))
    }

    static func result(_ result: RuntimeExecutionResult, title: String, systemImage: String) -> NativeToolResult {
        let body = [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: result.stdout.isEmpty || result.stderr.isEmpty ? "" : "\n")
        let block = NativeUIBlock(
            type: result.exitCode == 0 && !result.didTimeOut && !result.wasCancelled ? .card : .error,
            title: RuntimeL10n.string(title),
            subtitle: result.exitCode.map { RuntimeL10n.format("Exit code: %d", $0) },
            body: body.isEmpty ? RuntimeL10n.string("No output") : body,
            footnote: RuntimeL10n.format("Duration: %d ms", result.durationMilliseconds),
            systemImage: systemImage,
            actions: body.isEmpty ? [] : [.init(type: .copyText, title: RuntimeL10n.string("Copy output"), systemImage: "doc.on.doc", text: body)]
        )
        return NativeToolResult(modelText: body.isEmpty ? RuntimeL10n.string("Execution completed without output.") : body, userText: body.isEmpty ? nil : body, uiBlocks: [block])
    }

    static func failure(_ error: Error, title: String) -> NativeToolResult {
        NativeToolResult(
            modelText: "\(RuntimeL10n.string(title)): \(error.localizedDescription)",
            uiBlocks: [.init(type: .error, title: RuntimeL10n.string(title), body: error.localizedDescription, systemImage: "exclamationmark.triangle")]
        )
    }
}
