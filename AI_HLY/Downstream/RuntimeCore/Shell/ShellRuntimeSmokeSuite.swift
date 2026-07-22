import Foundation
import IOSSystemLite

struct ShellCommandSmokeResult: Codable, Sendable {
    let command: String
    let exitCode: Int?
    let representativeOutput: String
    let passed: Bool
    let failure: String?
}

struct ShellPolicySmokeResult: Codable, Sendable {
    let policy: String
    let passed: Bool
    let detail: String
}

struct ShellRuntimeSmokeReport: Codable, Sendable {
    let passed: Bool
    let commandResults: [ShellCommandSmokeResult]
    let policyResults: [ShellPolicySmokeResult]
    let testedCommands: [String]
    let workspaceContained: Bool
    let workspaceEscapeCount: Int
}

extension ShellRuntimeService {
    func runSmokeSuite() throws -> ShellRuntimeSmokeReport {
        _ = try healthCheck()
        try diagnosticLog.record("shell_smoke_started")

        let manager = FileManager.default
        let identifier = "shell-smoke-\(UUID().uuidString.lowercased())"
        let workspace = try fileLayout.workspace(client: .tools, identifier: identifier)
        let toolsRoot = workspace.deletingLastPathComponent()
        let sentinel = toolsRoot.appending(path: "sentinel-\(UUID().uuidString.lowercased()).txt")
        let sentinelData = Data("outside-workspace-unchanged\n".utf8)
        try sentinelData.write(to: sentinel, options: .atomic)

        var commandResults: [ShellCommandSmokeResult] = []
        var policyResults: [ShellPolicySmokeResult] = []

        func write(_ value: String, to relativePath: String) throws {
            try Data(value.utf8).write(to: workspace.appending(path: relativePath), options: .atomic)
        }

        func outputSummary(_ result: RuntimeExecutionResult) -> String {
            let combined = (result.stdout + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            if combined.isEmpty { return "exit=\(result.exitCode ?? -1)" }
            return String(combined.prefix(512))
        }

        func run(
            _ command: String,
            tokens: [String],
            standardInput: Data = Data(),
            verify: (RuntimeExecutionResult) throws -> Bool
        ) throws {
            do {
                let result = try execute(
                    tokens: tokens,
                    workspace: workspace,
                    environment: [:],
                    allowNetwork: false,
                    standardInput: standardInput
                )
                let passed: Bool
                if result.exitCode == 0 {
                    passed = try verify(result)
                } else {
                    passed = false
                }
                let failure = passed ? nil : "The command returned unexpected output or filesystem state."
                commandResults.append(
                    ShellCommandSmokeResult(
                        command: command,
                        exitCode: result.exitCode,
                        representativeOutput: outputSummary(result),
                        passed: passed,
                        failure: failure
                    )
                )
                if !passed {
                    try diagnosticLog.record(
                        "shell_command_failed",
                        category: ShellHealthCategory.executionSmokeFailure.rawValue,
                        message: failure,
                        command: command,
                        exitCode: result.exitCode
                    )
                }
            } catch {
                commandResults.append(
                    ShellCommandSmokeResult(
                        command: command,
                        exitCode: nil,
                        representativeOutput: "",
                        passed: false,
                        failure: error.localizedDescription
                    )
                )
                let nsError = error as NSError
                try diagnosticLog.record(
                    "shell_command_failed",
                    category: ShellHealthCategory.executionSmokeFailure.rawValue,
                    message: error.localizedDescription,
                    command: command,
                    underlyingErrorDomain: nsError.domain,
                    underlyingErrorCode: nsError.code
                )
            }
        }

        try write("alpha 1\nbeta 2\n", to: "awk-input.txt")
        try run("awk", tokens: ["awk", "{ print $2 }", "awk-input.txt"]) {
            $0.stdout.contains("1") && $0.stdout.contains("2")
        }

        try write("cat-ok\n", to: "cat-input.txt")
        try run("cat", tokens: ["cat", "cat-input.txt"]) { $0.stdout == "cat-ok\n" }

        try write("copy-ok\n", to: "cp-source.txt")
        try run("cp", tokens: ["cp", "cp-source.txt", "cp-output.txt"]) { _ in
            try Data(contentsOf: workspace.appending(path: "cp-output.txt")) == Data("copy-ok\n".utf8)
        }

        try run("curl", tokens: ["curl", "--version"]) {
            ($0.stdout + $0.stderr).localizedCaseInsensitiveContains("curl")
        }

        try write("alpha\nbeta\ngamma\n", to: "grep-input.txt")
        try run("grep", tokens: ["grep", "beta", "grep-input.txt"]) { $0.stdout.contains("beta") }

        try write("first\nsecond\n", to: "head-input.txt")
        try run("head", tokens: ["head", "-n", "1", "head-input.txt"]) {
            $0.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "first"
        }

        try write("link-target\n", to: "ln-target.txt")
        try run("ln", tokens: ["ln", "-s", "ln-target.txt", "ln-output.txt"]) { _ in
            try manager.destinationOfSymbolicLink(atPath: workspace.appending(path: "ln-output.txt").path) == "ln-target.txt"
        }

        try write("listed\n", to: "ls-visible.txt")
        try run("ls", tokens: ["ls", "ls-visible.txt"]) { $0.stdout.contains("ls-visible.txt") }

        try run("mkdir", tokens: ["mkdir", "created-directory"]) { _ in
            var isDirectory: ObjCBool = false
            let exists = manager.fileExists(
                atPath: workspace.appending(path: "created-directory").path,
                isDirectory: &isDirectory
            )
            return exists && isDirectory.boolValue
        }

        try write("move-ok\n", to: "mv-source.txt")
        try run("mv", tokens: ["mv", "mv-source.txt", "mv-output.txt"]) { _ in
            manager.fileExists(atPath: workspace.appending(path: "mv-output.txt").path)
                && !manager.fileExists(atPath: workspace.appending(path: "mv-source.txt").path)
        }

        try write("readlink-target\n", to: "readlink-target.txt")
        try manager.createSymbolicLink(
            atPath: workspace.appending(path: "readlink-input.txt").path,
            withDestinationPath: "readlink-target.txt"
        )
        try run("readlink", tokens: ["readlink", "readlink-input.txt"]) {
            $0.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "readlink-target.txt"
        }

        try write("remove-ok\n", to: "rm-input.txt")
        try run("rm", tokens: ["rm", "rm-input.txt"]) { _ in
            !manager.fileExists(atPath: workspace.appending(path: "rm-input.txt").path)
        }

        try manager.createDirectory(at: workspace.appending(path: "rmdir-input"), withIntermediateDirectories: false)
        try run("rmdir", tokens: ["rmdir", "rmdir-input"]) { _ in
            !manager.fileExists(atPath: workspace.appending(path: "rmdir-input").path)
        }

        try write("first\nsecond\n", to: "sed-input.txt")
        try run("sed", tokens: ["sed", "-n", "2p", "sed-input.txt"]) {
            $0.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "second"
        }

        try write("charlie\nalpha\nbravo\n", to: "sort-input.txt")
        try run("sort", tokens: ["sort", "sort-input.txt"]) {
            $0.stdout.hasPrefix("alpha\n")
        }

        try write("stat-ok\n", to: "stat-input.txt")
        try run("stat", tokens: ["stat", "stat-input.txt"]) { _ in true }

        try write("first\nlast\n", to: "tail-input.txt")
        try run("tail", tokens: ["tail", "-n", "1", "tail-input.txt"]) {
            $0.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "last"
        }

        try write("tar-ok\n", to: "tar-input.txt")
        do {
            let create = try execute(
                tokens: ["tar", "-cf", "archive.tar", "tar-input.txt"],
                workspace: workspace,
                environment: [:],
                allowNetwork: false
            )
            let inspect = try execute(
                tokens: ["tar", "-tf", "archive.tar"],
                workspace: workspace,
                environment: [:],
                allowNetwork: false
            )
            let passed = create.exitCode == 0 && inspect.exitCode == 0 && inspect.stdout.contains("tar-input.txt")
            commandResults.append(
                ShellCommandSmokeResult(
                    command: "tar",
                    exitCode: passed ? 0 : (create.exitCode ?? inspect.exitCode),
                    representativeOutput: outputSummary(inspect),
                    passed: passed,
                    failure: passed ? nil : "Archive creation or inspection failed."
                )
            )
        } catch {
            commandResults.append(
                ShellCommandSmokeResult(
                    command: "tar",
                    exitCode: nil,
                    representativeOutput: "",
                    passed: false,
                    failure: error.localizedDescription
                )
            )
        }

        try run("touch", tokens: ["touch", "touch-output.txt"]) { _ in
            manager.fileExists(atPath: workspace.appending(path: "touch-output.txt").path)
        }

        try run(
            "tr",
            tokens: ["tr", "a-z", "A-Z"],
            standardInput: Data("lower\n".utf8)
        ) { $0.stdout == "LOWER\n" }

        try write("alpha\nalpha\nbeta\n", to: "uniq-input.txt")
        try run("uniq", tokens: ["uniq", "uniq-input.txt"]) {
            $0.stdout == "alpha\nbeta\n"
        }

        try write("unlink-ok\n", to: "unlink-input.txt")
        try run("unlink", tokens: ["unlink", "unlink-input.txt"]) { _ in
            !manager.fileExists(atPath: workspace.appending(path: "unlink-input.txt").path)
        }

        try write("one\ntwo\n", to: "wc-input.txt")
        try run("wc", tokens: ["wc", "-l", "wc-input.txt"]) {
            $0.stdout.contains("2") && $0.stdout.contains("wc-input.txt")
        }

        func expectRejection(_ policy: String, operation: () throws -> Void) {
            do {
                try operation()
                policyResults.append(.init(policy: policy, passed: false, detail: "The request was unexpectedly accepted."))
            } catch {
                policyResults.append(.init(policy: policy, passed: true, detail: error.localizedDescription))
            }
        }

        expectRejection("unknown_command") {
            _ = try execute(tokens: ["sh"], workspace: workspace, environment: [:], allowNetwork: false)
        }
        expectRejection("pipeline") { _ = try Self.tokenize("cat file | grep value") }
        expectRejection("redirection") { _ = try Self.tokenize("cat file > output") }
        expectRejection("command_chaining") { _ = try Self.tokenize("ls && rm file") }
        expectRejection("parent_traversal") {
            _ = try execute(tokens: ["cat", "../sentinel"], workspace: workspace, environment: [:], allowNetwork: false)
        }
        expectRejection("absolute_path") {
            _ = try execute(tokens: ["cat", "/tmp/outside"], workspace: workspace, environment: [:], allowNetwork: false)
        }
        expectRejection("curl_https_permission") {
            _ = try execute(tokens: ["curl", "https://example.invalid"], workspace: workspace, environment: [:], allowNetwork: false)
        }
        expectRejection("curl_http") {
            _ = try execute(tokens: ["curl", "http://example.invalid"], workspace: workspace, environment: [:], allowNetwork: true)
        }
        let curlVersionPassed = commandResults.first { $0.command == "curl" }?.passed == true
        policyResults.append(
            .init(
                policy: "curl_offline_version",
                passed: curlVersionPassed,
                detail: curlVersionPassed ? "curl --version passed without network access." : "curl --version failed."
            )
        )

        let sentinelUnchanged = (try? Data(contentsOf: sentinel)) == sentinelData
        let expectedCommands = Set(Self.capabilities.map(\.name))
        let testedCommands = Set(commandResults.map(\.command))
        let allCommandsCovered = testedCommands == expectedCommands && commandResults.count == expectedCommands.count
        var workspaceContained = sentinelUnchanged

        do {
            try manager.removeItem(at: workspace)
            try manager.removeItem(at: sentinel)
        } catch {
            workspaceContained = false
        }

        let passed = allCommandsCovered
            && commandResults.allSatisfy(\.passed)
            && policyResults.allSatisfy(\.passed)
            && workspaceContained
        snapshotValue.state = passed ? .ready : .failed
        snapshotValue.healthCategory = passed
            ? ShellHealthCategory.ready.rawValue
            : ShellHealthCategory.executionSmokeFailure.rawValue
        snapshotValue.lastErrorCode = passed ? nil : "executionSmokeFailure:smoke_suite_failed"
        snapshotValue.lastDiagnostic = passed
            ? "All 23 approved ios_system commands and shell policy checks passed."
            : "One or more controlled ios_system smoke checks failed."
        try diagnosticLog.record(
            "shell_smoke_completed",
            category: snapshotValue.healthCategory,
            message: snapshotValue.lastDiagnostic
        )

        return ShellRuntimeSmokeReport(
            passed: passed,
            commandResults: commandResults,
            policyResults: policyResults,
            testedCommands: testedCommands.sorted(),
            workspaceContained: workspaceContained,
            workspaceEscapeCount: workspaceContained ? 0 : 1
        )
    }
}
