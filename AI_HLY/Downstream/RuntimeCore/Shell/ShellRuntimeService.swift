import Foundation
import IOSSystemLite

struct ShellCommandCapability: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let summary: String
    let requiresNetwork: Bool
}

actor ShellRuntimeService {
    static let capabilities: [ShellCommandCapability] = [
        .init(name: "awk", summary: "Process text with the linked BSD awk implementation.", requiresNetwork: false),
        .init(name: "cat", summary: "Read workspace files.", requiresNetwork: false),
        .init(name: "cp", summary: "Copy workspace files.", requiresNetwork: false),
        .init(name: "curl", summary: "Transfer data over HTTPS when network access is approved.", requiresNetwork: true),
        .init(name: "grep", summary: "Search text in workspace files.", requiresNetwork: false),
        .init(name: "head", summary: "Read the beginning of workspace files.", requiresNetwork: false),
        .init(name: "ln", summary: "Create links inside the workspace.", requiresNetwork: false),
        .init(name: "ls", summary: "List workspace files.", requiresNetwork: false),
        .init(name: "mkdir", summary: "Create workspace directories.", requiresNetwork: false),
        .init(name: "mv", summary: "Move workspace files.", requiresNetwork: false),
        .init(name: "readlink", summary: "Inspect a workspace link.", requiresNetwork: false),
        .init(name: "rm", summary: "Remove workspace files.", requiresNetwork: false),
        .init(name: "rmdir", summary: "Remove empty workspace directories.", requiresNetwork: false),
        .init(name: "sed", summary: "Transform text with BSD sed.", requiresNetwork: false),
        .init(name: "sort", summary: "Sort text.", requiresNetwork: false),
        .init(name: "stat", summary: "Inspect workspace file metadata.", requiresNetwork: false),
        .init(name: "tail", summary: "Read the end of workspace files.", requiresNetwork: false),
        .init(name: "tar", summary: "Create or extract archives in the workspace.", requiresNetwork: false),
        .init(name: "touch", summary: "Create or update workspace files.", requiresNetwork: false),
        .init(name: "tr", summary: "Translate text characters.", requiresNetwork: false),
        .init(name: "uniq", summary: "Filter repeated text lines.", requiresNetwork: false),
        .init(name: "unlink", summary: "Remove one workspace link or file.", requiresNetwork: false),
        .init(name: "wc", summary: "Count lines, words, or bytes.", requiresNetwork: false)
    ]

    private let fileLayout: RuntimeFileLayout
    private var snapshotValue = RuntimeSnapshot.stopped(.shell)

    init(fileLayout: RuntimeFileLayout = .default) { self.fileLayout = fileLayout }

    func snapshot() -> RuntimeSnapshot { snapshotValue }

    func healthCheck() throws -> RuntimeSnapshot {
        let discovered = Set(IOSSystemRunner.availableCommands())
        let expected = Set(Self.capabilities.map(\.name))
        guard expected.isSubset(of: discovered) else {
            snapshotValue.state = .failed
            snapshotValue.lastErrorCode = "missing_commands:\(expected.subtracting(discovered).sorted().joined(separator: ","))"
            throw RuntimeCoreError.runtimeFailure("Some pinned ios_system commands are not linked: \(expected.subtracting(discovered).sorted().joined(separator: ", ")).")
        }
        snapshotValue.state = .ready
        snapshotValue.version = "3.0.5"
        snapshotValue.source = "holzschu/ios_system"
        snapshotValue.lastHealthCheck = .now
        snapshotValue.lastErrorCode = nil
        return snapshotValue
    }

    func execute(command: String, workspace: URL, environment: [String: String], allowNetwork: Bool, limits: RuntimeExecutionLimits = RuntimeExecutionLimits()) throws -> RuntimeExecutionResult {
        try execute(tokens: Self.tokenize(command), workspace: workspace, environment: environment, allowNetwork: allowNetwork, limits: limits)
    }

    func execute(tokens: [String], workspace: URL, environment: [String: String], allowNetwork: Bool, limits: RuntimeExecutionLimits = RuntimeExecutionLimits()) throws -> RuntimeExecutionResult {
        try fileLayout.prepareIfNeeded()
        let scopedWorkspace = try fileLayout.validatedDescendant(workspace, of: fileLayout.clients, allowRoot: false)
        guard !tokens.isEmpty, tokens.count <= 128 else {
            throw RuntimeCoreError.invalidRequest("The command is empty or contains too many arguments.")
        }
        guard let name = tokens.first, let capability = Self.capabilities.first(where: { $0.name == name }) else {
            throw RuntimeCoreError.invalidRequest("The requested command is not in the verified ios_system catalog.")
        }
        if capability.requiresNetwork && !allowNetwork { throw RuntimeCoreError.invalidRequest("This command requires explicit network permission.") }
        try validateArguments(tokens.dropFirst(), command: name)
        for key in environment.keys { _ = try RuntimePolicy.validateEnvironmentName(key) }
        let started = ContinuousClock.now
        snapshotValue.state = .executing
        snapshotValue.activeExecutionCount += 1
        defer {
            snapshotValue.activeExecutionCount = max(0, snapshotValue.activeExecutionCount - 1)
            snapshotValue.state = .ready
        }
        let output = try IOSSystemRunner.execute(tokens: tokens, workspace: scopedWorkspace, environment: environment)
        let duration = started.duration(to: .now)
        let milliseconds = duration.components.seconds * 1_000 + Int64(duration.components.attoseconds / 1_000_000_000_000_000)
        let total = output.stdout.utf8.count + output.stderr.utf8.count
        return RuntimeExecutionResult(
            executionID: UUID(),
            stdout: String(decoding: output.stdout.utf8.prefix(limits.maximumOutputBytes), as: UTF8.self),
            stderr: String(decoding: output.stderr.utf8.prefix(max(0, limits.maximumOutputBytes - min(output.stdout.utf8.count, limits.maximumOutputBytes))), as: UTF8.self),
            value: nil,
            exitCode: Int(output.exitCode),
            durationMilliseconds: milliseconds,
            didTimeOut: false,
            wasCancelled: false,
            outputWasTruncated: total > limits.maximumOutputBytes
        )
    }

    static func tokenize(_ command: String) throws -> [String] {
        guard !command.contains("\n"), !command.contains("\r"), !command.contains("`"),
              !command.contains("$("), !command.contains("${"),
              !command.contains("|"), !command.contains(";"),
              !command.contains(">"), !command.contains("<"), !command.contains("&&"), !command.contains("||") else {
            throw RuntimeCoreError.invalidRequest("Shell expansion, redirection, pipelines, substitutions, and command chaining are not supported.")
        }
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var escaping = false
        for character in command {
            if escaping { current.append(character); escaping = false; continue }
            if character == "\\" { escaping = true; continue }
            if let activeQuote = quote {
                if character == activeQuote { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" { quote = character }
            else if character.isWhitespace {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else { current.append(character) }
        }
        guard quote == nil, !escaping else { throw RuntimeCoreError.invalidRequest("The command contains an unterminated quote or escape.") }
        if !current.isEmpty { tokens.append(current) }
        guard !tokens.isEmpty, tokens.count <= 128 else { throw RuntimeCoreError.invalidRequest("The command is empty or contains too many arguments.") }
        return tokens
    }

    private func validateArguments(_ arguments: ArraySlice<String>, command: String) throws {
        for argument in arguments where !argument.hasPrefix("-") {
            if command == "curl", let url = URL(string: argument), url.scheme != nil {
                guard url.scheme?.lowercased() == "https", url.host != nil else { throw RuntimeCoreError.invalidRequest("curl accepts HTTPS URLs only.") }
                continue
            }
            let normalized = argument.replacingOccurrences(of: "\\", with: "/")
            guard !normalized.hasPrefix("/"), !normalized.split(separator: "/").contains("..") else {
                throw RuntimeCoreError.pathEscapesRoot
            }
        }
    }
}
