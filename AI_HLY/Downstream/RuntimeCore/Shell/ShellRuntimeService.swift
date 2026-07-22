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

    let fileLayout: RuntimeFileLayout
    var snapshotValue = RuntimeSnapshot.stopped(.shell)
    let diagnosticLog: ShellRuntimeDiagnosticLog

    init(fileLayout: RuntimeFileLayout = .default) {
        self.fileLayout = fileLayout
        diagnosticLog = ShellRuntimeDiagnosticLog(fileLayout: fileLayout)
    }

    func snapshot() -> RuntimeSnapshot { snapshotValue }

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

    func execute(
        command: String,
        workspace: URL,
        environment: [String: String],
        allowNetwork: Bool,
        limits: RuntimeExecutionLimits = RuntimeExecutionLimits()
    ) throws -> RuntimeExecutionResult {
        try execute(
            tokens: Self.tokenize(command),
            workspace: workspace,
            environment: environment,
            allowNetwork: allowNetwork,
            limits: limits
        )
    }

    func execute(
        tokens: [String],
        workspace: URL,
        environment: [String: String],
        allowNetwork: Bool,
        standardInput: Data = Data(),
        limits: RuntimeExecutionLimits = RuntimeExecutionLimits()
    ) throws -> RuntimeExecutionResult {
        try fileLayout.prepareIfNeeded()
        let scopedWorkspace = try fileLayout.validatedDescendant(workspace, of: fileLayout.clients, allowRoot: false)
        guard !tokens.isEmpty, tokens.count <= 128 else {
            throw RuntimeCoreError.invalidRequest("The command is empty or contains too many arguments.")
        }
        guard let name = tokens.first, let capability = Self.capabilities.first(where: { $0.name == name }) else {
            throw RuntimeCoreError.invalidRequest("The requested command is not in the verified ios_system catalog.")
        }
        let isOfflineCurlVersion = tokens == ["curl", "--version"]
        if capability.requiresNetwork && !allowNetwork && !isOfflineCurlVersion {
            throw RuntimeCoreError.invalidRequest("This command requires explicit network permission.")
        }
        try validateArguments(tokens.dropFirst(), command: name)
        for key in environment.keys { _ = try RuntimePolicy.validateEnvironmentName(key) }

        let started = ContinuousClock.now
        snapshotValue.state = .executing
        snapshotValue.activeExecutionCount += 1
        defer {
            snapshotValue.activeExecutionCount = max(0, snapshotValue.activeExecutionCount - 1)
            if snapshotValue.state == .executing { snapshotValue.state = .ready }
        }

        do {
            let output = try IOSSystemRunner.execute(
                tokens: tokens,
                workspace: scopedWorkspace,
                environment: environment,
                standardInput: standardInput
            )
            let duration = started.duration(to: .now)
            let milliseconds = duration.components.seconds * 1_000
                + Int64(duration.components.attoseconds / 1_000_000_000_000_000)
            let total = output.stdout.utf8.count + output.stderr.utf8.count
            if output.exitCode != 0 {
                try diagnosticLog.record(
                    "shell_command_failed",
                    category: ShellHealthCategory.executionSmokeFailure.rawValue,
                    message: "An approved ios_system command returned a nonzero exit code.",
                    command: name,
                    exitCode: Int(output.exitCode)
                )
            }
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
        } catch {
            snapshotValue.state = .failed
            snapshotValue.healthCategory = ShellHealthCategory.executionSmokeFailure.rawValue
            snapshotValue.lastErrorCode = "command_execution_failed"
            snapshotValue.lastDiagnostic = error.localizedDescription
            let nsError = error as NSError
            try diagnosticLog.record(
                "shell_command_failed",
                category: ShellHealthCategory.executionSmokeFailure.rawValue,
                message: error.localizedDescription,
                command: name,
                underlyingErrorDomain: nsError.domain,
                underlyingErrorCode: nsError.code
            )
            throw error
        }
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
        guard !tokens.isEmpty, tokens.count <= 128 else {
            throw RuntimeCoreError.invalidRequest("The command is empty or contains too many arguments.")
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

    private func validateArguments(_ arguments: ArraySlice<String>, command: String) throws {
        for argument in arguments where !argument.hasPrefix("-") {
            if command == "curl", let url = URL(string: argument), url.scheme != nil {
                guard url.scheme?.lowercased() == "https", url.host != nil else {
                    throw RuntimeCoreError.invalidRequest("curl accepts HTTPS URLs only.")
                }
                continue
            }
            let normalized = argument.replacingOccurrences(of: "\\", with: "/")
            guard !normalized.hasPrefix("/"), !normalized.split(separator: "/").contains("..") else {
                throw RuntimeCoreError.pathEscapesRoot
            }
        }
    }
}
