import CryptoKit
import Foundation
import IOSSystemLite

struct ShellCommandCapability: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let summary: String
    let requiresNetwork: Bool
}

enum ShellHealthCategory: String, Codable, Sendable {
    case resourceMissing
    case malformedDictionary
    case dictionaryCatalogMismatch
    case initializationFailure
    case commandNotRegistered
    case commandNotExecutable
    case executionSmokeFailure
    case ready
}

actor ShellRuntimeService {
    static let capabilities: [ShellCommandCapability] = [
        .init(name: "awk", summary: "Process text with the linked BSD awk implementation.", requiresNetwork: false),
        .init(name: "cat", summary: "Read workspace files.", requiresNetwork: false),
        .init(name: "cp", summary: "Copy workspace files.", requiresNetwork: false),
        .init(name: "curl", summary: "Transfer data over HTTPS.", requiresNetwork: true),
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

    private static let executionQueue = DispatchQueue(label: "hanlin.shell.execution", qos: .userInitiated)
    private typealias Pending = RuntimeQueuedExecution<URL, IOSSystemExecution>
    private let jobs: RuntimeJobStore
    private var active: [UUID: Pending] = [:]
    private var stopRequested = false
    let fileLayout: RuntimeFileLayout
    let commandDictionaryURL: URL?
    var snapshotValue = RuntimeSnapshot.stopped(.shell)
    let diagnosticLog: ShellRuntimeDiagnosticLog

    init(fileLayout: RuntimeFileLayout = .default, commandDictionaryURL: URL? = nil, jobs: RuntimeJobStore? = nil) {
        self.fileLayout = fileLayout
        self.jobs = jobs ?? RuntimeJobStore(fileLayout: fileLayout)
        self.commandDictionaryURL = commandDictionaryURL
        diagnosticLog = ShellRuntimeDiagnosticLog(fileLayout: fileLayout)
    }

    func snapshot() -> RuntimeSnapshot { snapshotValue }

    func commandDependencyDiagnostics() throws -> [String: IOSSystemCommandDependencyDiagnostic] {
        try IOSSystemRunner.evaluateCommandDependencies(dictionaryURL: commandDictionaryURL)
    }

    func healthCheck() throws -> RuntimeSnapshot {
        try fileLayout.prepareIfNeeded()
        snapshotValue.version = "3.0.5"
        snapshotValue.source = "holzschu/ios_system"
        snapshotValue.lastHealthCheck = .now
        try diagnosticLog.record("shell_registration_started")

        do {
            let report = try IOSSystemRunner.registrationReport()
            try diagnosticLog.record(
                "shell_resources_found",
                message: "Main and extra ios_system dictionaries were found at the app root.",
                resourcePath: report.mainDictionaryPath
            )
            try diagnosticLog.record(
                "shell_dictionary_validated",
                message: "The app and IOSSystemLite dictionaries contain the exact approved 23-command catalog."
            )
            try diagnosticLog.record(
                "shell_environment_initialized",
                message: "initializeEnvironment completed once for this process."
            )
            try diagnosticLog.record(
                "shell_commands_discovered",
                message: "ios_system returned \(report.registeredCommands.count) approved commands.",
                missingCommands: report.missingRegisteredCommands
            )
            try diagnosticLog.record(
                "shell_executable_validation",
                message: "ios_executable accepted \(report.executableCommands.count) approved commands.",
                missingCommands: report.missingExecutableCommands
            )

            if !report.missingRegisteredCommands.isEmpty {
                throw IOSSystemRegistrationError(
                    category: .commandNotRegistered,
                    code: "command_not_registered",
                    message: "Some approved ios_system commands were not registered: \(report.missingRegisteredCommands.joined(separator: ", ")).",
                    missingCommands: report.missingRegisteredCommands
                )
            }
            if !report.missingExecutableCommands.isEmpty {
                throw IOSSystemRegistrationError(
                    category: .commandNotExecutable,
                    code: "command_not_executable",
                    message: "Some registered ios_system commands are not executable: \(report.missingExecutableCommands.joined(separator: ", ")).",
                    missingCommands: report.missingExecutableCommands
                )
            }

            snapshotValue.state = .ready
            snapshotValue.healthCategory = ShellHealthCategory.ready.rawValue
            snapshotValue.lastErrorCode = nil
            snapshotValue.lastDiagnostic = "All 23 approved ios_system commands are registered and executable."
            snapshotValue.missingCommands = nil
            return snapshotValue
        } catch let error as IOSSystemRegistrationError {
            let category = ShellHealthCategory(rawValue: error.category.rawValue) ?? .initializationFailure
            return try failHealth(
                category: category,
                code: error.code,
                message: error.message,
                resourcePath: error.resourcePath,
                missingCommands: error.missingCommands,
                underlyingErrorDomain: error.underlyingErrorDomain,
                underlyingErrorCode: error.underlyingErrorCode
            )
        } catch {
            let nsError = error as NSError
            return try failHealth(
                category: .initializationFailure,
                code: "unexpected_initialization_error",
                message: error.localizedDescription,
                underlyingErrorDomain: nsError.domain,
                underlyingErrorCode: nsError.code
            )
        }
    }

    func stop() async -> RuntimeSnapshot {
        stopRequested = true
        for id in Array(active.keys) { try? await cancel(id: id) }
        if active.isEmpty { snapshotValue = .stopped(.shell) }
        else { snapshotValue.lastDiagnostic = "Stop requested. Queued commands are skipped; running linked native commands must finish before Shell can stop." }
        return snapshotValue
    }

    func cancel(id: UUID) async throws {
        try await jobs.requestCancellation(id: id, kind: .shell)
        active[id]?.cancelBeforeStarting()
    }

    func execute(
        command: String,
        workspace: URL,
        environment: [String: String],
        allowNetwork: Bool,
        limits: RuntimeExecutionLimits = RuntimeExecutionLimits()
    ) async throws -> RuntimeExecutionResult {
        try fileLayout.prepareIfNeeded()
        let scopedWorkspace = try fileLayout.validatedWorkspace(workspace)
        for key in environment.keys { _ = try RuntimePolicy.validateEnvironmentName(key) }

        if command.trimmingCharacters(in: .whitespacesAndNewlines) == "pwd" {
            return try await execute(tokens: ["pwd"], workspace: scopedWorkspace, environment: environment, allowNetwork: allowNetwork, limits: limits)
        }
        return try await runCaptured(limits: limits) { directory, onStart in
            try IOSSystemRunner.executeCommand(command: command, workspace: scopedWorkspace,
                environment: environment, outputDirectory: directory,
                maximumPreviewBytes: limits.maximumOutputBytes, onStart: onStart)
        }
    }

    func execute(
        tokens: [String],
        workspace: URL,
        environment: [String: String],
        allowNetwork: Bool,
        standardInput: Data = Data(),
        limits: RuntimeExecutionLimits = RuntimeExecutionLimits()
    ) async throws -> RuntimeExecutionResult {
        try fileLayout.prepareIfNeeded()
        let scopedWorkspace = try fileLayout.validatedWorkspace(workspace)
        guard !tokens.isEmpty else {
            throw RuntimeCoreError.invalidRequest("The command is empty.")
        }
        if tokens.first == "pwd" {
            guard tokens.dropFirst().allSatisfy({ $0 == "-L" || $0 == "-P" }) else {
                throw RuntimeCoreError.invalidRequest("pwd accepts only -L or -P.")
            }
            return try await runCaptured(limits: limits) { directory, onStart in
                try onStart()
                let stdout = directory.appending(path: "stdout.log")
                let stderr = directory.appending(path: "stderr.log")
                try Data((scopedWorkspace.path + "\n").utf8).write(to: stdout)
                try Data().write(to: stderr)
                var preview = Data((scopedWorkspace.path + "\n").utf8.prefix(limits.maximumOutputBytes))
                while String(data: preview, encoding: .utf8) == nil { preview.removeLast() }
                return IOSSystemExecution(stdout: String(decoding: preview, as: UTF8.self), stderr: "", exitCode: 0,
                    stdoutFileURL: stdout, stderrFileURL: stderr)
            }
        }
        guard let name = tokens.first, Self.capabilities.contains(where: { $0.name == name }) else {
            throw RuntimeCoreError.invalidRequest("The requested command is not in the verified ios_system catalog.")
        }
        if let commandDictionaryURL {
            let diagnostics = try IOSSystemRunner.evaluateCommandDependencies(dictionaryURL: commandDictionaryURL)
            guard let status = diagnostics[name] else {
                throw RuntimeCoreError.invalidRequest("Command '\(name)' is not present in the configured command dictionary.")
            }
            if !status.isAvailable {
                let reason = status.missingDependencyReason ?? "Missing dependency (\(status.framework)/\(status.symbol)) for command '\(name)'."
                try diagnosticLog.record(
                    "shell_command_dependency_missing",
                    category: ShellHealthCategory.commandNotExecutable.rawValue,
                    message: reason,
                    command: name,
                    missingCommands: [name]
                )
                throw RuntimeCoreError.invalidRequest("Command '\(name)' is unavailable: \(reason)")
            }
        }
        // allowNetwork is retained for wire/source compatibility. Ordinary execution
        // has no second Hanlin network approval; curl keeps its native TLS behavior.
        for key in environment.keys { _ = try RuntimePolicy.validateEnvironmentName(key) }

        do {
            return try await runCaptured(limits: limits) { directory, onStart in
                try IOSSystemRunner.execute(tokens: tokens, workspace: scopedWorkspace,
                    environment: environment, standardInput: standardInput, outputDirectory: directory,
                    maximumPreviewBytes: limits.maximumOutputBytes, onStart: onStart)
            }
        } catch {
            if !(error is CancellationError) {
                snapshotValue.lastErrorCode = "command_execution_failed"
                snapshotValue.lastDiagnostic = error.localizedDescription
            }
            throw error
        }
    }

    private func runCaptured(
        limits: RuntimeExecutionLimits,
        operation: @escaping @Sendable (URL, @escaping @Sendable () throws -> Void) throws -> IOSSystemExecution
    ) async throws -> RuntimeExecutionResult {
        try Task.checkCancellation()
        guard limits.timeout == nil else {
            throw RuntimeCoreError.invalidRequest("Linked ios_system commands do not yet support a safe per-command deadline. No timeout is silently ignored.")
        }
        let id = UUID()
        let initial = try await jobs.create(id: id, kind: .shell)
        let directory = jobs.directory(id: id, kind: .shell)
        let pending = Pending()
        active[id] = pending
        stopRequested = false
        snapshotValue.state = .executing
        snapshotValue.activeExecutionCount = active.count
        defer {
            active.removeValue(forKey: id)
            snapshotValue.activeExecutionCount = active.count
            if active.isEmpty { snapshotValue.state = stopRequested ? .stopped : .ready }
        }
        let observer = RuntimeJobProgress.reporter
        let jobs = self.jobs
        if let observer { await observer(initial) }
        if try await jobs.snapshot(id: id, kind: .shell)?.cancellationRequested == true {
            pending.cancelBeforeStarting()
        }
        let start = ContinuousClock.now
        do {
            let output: IOSSystemExecution = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    guard pending.bind(continuation, input: directory) else { return }
                    Self.executionQueue.async {
                        do {
                            let result = try operation(directory) {
                                guard pending.takeForRunning() != nil else { throw CancellationError() }
                                Task {
                                    try? await jobs.markRunning(id: id, kind: .shell)
                                    if let observer, let record = try? await jobs.snapshot(id: id, kind: .shell) { await observer(record) }
                                }
                            }
                            pending.complete(.success(result))
                        } catch { pending.complete(.failure(error)) }
                    }
                }
            } onCancel: {
                pending.cancelBeforeStarting()
                Task { try? await jobs.requestCancellation(id: id, kind: .shell) }
            }
            var artifacts: [String: RuntimeOutputArtifact] = [:]
            for (channel, url) in [("stdout", output.stdoutFileURL), ("stderr", output.stderrFileURL)] {
                guard let url else { throw RuntimeCoreError.runtimeFailure("Shell output file is missing.") }
                artifacts[channel] = try Self.artifact(url)
            }
            let duration = start.duration(to: .now)
            let total = artifacts.values.reduce(Int64(0)) { $0 + $1.bytes }
            let result = RuntimeExecutionResult(executionID: id, stdout: output.stdout, stderr: output.stderr,
                value: nil, exitCode: Int(output.exitCode),
                durationMilliseconds: duration.components.seconds * 1000 + Int64(duration.components.attoseconds / 1_000_000_000_000_000),
                didTimeOut: false, wasCancelled: false, outputWasTruncated: total > limits.maximumOutputBytes,
                outputFiles: artifacts)
            if Task.isCancelled { try await jobs.requestCancellation(id: id, kind: .shell) }
            try await jobs.complete(result, kind: .shell)
            if let observer, let record = try await jobs.snapshot(id: id, kind: .shell) { await observer(record) }
            return result
        } catch {
            try? await jobs.fail(id: id, kind: .shell, error: error)
            throw error
        }
    }

    private static func artifact(_ url: URL) throws -> RuntimeOutputArtifact {
        let stream = try FileHandle(forReadingFrom: url)
        defer { try? stream.close() }
        var digest = SHA256()
        var bytes: Int64 = 0
        while let data = try stream.read(upToCount: 65_536), !data.isEmpty {
            digest.update(data: data)
            bytes += Int64(data.count)
        }
        return RuntimeOutputArtifact(path: url.path, bytes: bytes,
            sha256: digest.finalize().map { String(format: "%02x", $0) }.joined())
    }

    static func tokenize(_ command: String) throws -> [String] {
        guard !command.contains("\n"), !command.contains("\r"), !command.contains("`"),
              !command.contains("$("), !command.contains("${"),
              !command.contains("|"), !command.contains(";"),
              !command.contains(">"), !command.contains("<"),
              !command.contains("&&"), !command.contains("||") else {
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
        guard quote == nil, !escaping else {
            throw RuntimeCoreError.invalidRequest("The command contains an unterminated quote or escape.")
        }
        if !current.isEmpty { tokens.append(current) }
        guard !tokens.isEmpty else {
            throw RuntimeCoreError.invalidRequest("The command is empty.")
        }
        return tokens
    }

    func failHealth(
        category: ShellHealthCategory,
        code: String,
        message: String,
        resourcePath: String? = nil,
        missingCommands: [String] = [],
        underlyingErrorDomain: String? = nil,
        underlyingErrorCode: Int? = nil
    ) throws -> RuntimeSnapshot {
        snapshotValue.state = .failed
        snapshotValue.healthCategory = category.rawValue
        snapshotValue.lastErrorCode = "\(category.rawValue):\(code)"
        snapshotValue.lastDiagnostic = message
        snapshotValue.missingCommands = missingCommands.isEmpty ? nil : missingCommands
        try diagnosticLog.record(
            "shell_registration_failed",
            category: category.rawValue,
            message: message,
            resourcePath: resourcePath,
            missingCommands: missingCommands,
            underlyingErrorDomain: underlyingErrorDomain,
            underlyingErrorCode: underlyingErrorCode
        )
        throw RuntimeCoreError.runtimeFailure(message)
    }

}
