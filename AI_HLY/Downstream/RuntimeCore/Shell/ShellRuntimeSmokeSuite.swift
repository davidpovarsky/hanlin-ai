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
    func runSmokeSuite() async throws -> ShellRuntimeSmokeReport {
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

        try write("alpha 1\nbeta 2\n", to: "awk-input.txt")
        commandResults.append(try await smokeCommand("awk", tokens: ["awk", "{ print $2 }", "awk-input.txt"], workspace: workspace, verify: {
            $0.stdout.contains("1") && $0.stdout.contains("2")
        }))

        try write("cat-ok\n", to: "cat-input.txt")
        commandResults.append(try await smokeCommand("cat", tokens: ["cat", "cat-input.txt"], workspace: workspace, verify: { $0.stdout == "cat-ok\n" }))

        try write("copy-ok\n", to: "cp-source.txt")
        commandResults.append(try await smokeCommand("cp", tokens: ["cp", "cp-source.txt", "cp-output.txt"], workspace: workspace, verify: { _ in
            try Data(contentsOf: workspace.appending(path: "cp-output.txt")) == Data("copy-ok\n".utf8)
        }))

        commandResults.append(try await smokeCommand("curl", tokens: ["curl", "--version"], workspace: workspace, verify: {
            ($0.stdout + $0.stderr).localizedCaseInsensitiveContains("curl")
        }))

        try write("alpha\nbeta\ngamma\n", to: "grep-input.txt")
        commandResults.append(try await smokeCommand("grep", tokens: ["grep", "beta", "grep-input.txt"], workspace: workspace, verify: { $0.stdout.contains("beta") }))

        try write("first\nsecond\n", to: "head-input.txt")
        commandResults.append(try await smokeCommand("head", tokens: ["head", "-n", "1", "head-input.txt"], workspace: workspace, verify: {
            $0.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "first"
        }))

        try write("link-target\n", to: "ln-target.txt")
        commandResults.append(try await smokeCommand("ln", tokens: ["ln", "-s", "ln-target.txt", "ln-output.txt"], workspace: workspace, verify: { _ in
            try FileManager.default.destinationOfSymbolicLink(atPath: workspace.appending(path: "ln-output.txt").path) == "ln-target.txt"
        }))

        try write("listed\n", to: "ls-visible.txt")
        commandResults.append(try await smokeCommand("ls", tokens: ["ls", "ls-visible.txt"], workspace: workspace, verify: { $0.stdout.contains("ls-visible.txt") }))

        commandResults.append(try await smokeCommand("mkdir", tokens: ["mkdir", "created-directory"], workspace: workspace, verify: { _ in
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: workspace.appending(path: "created-directory").path,
                isDirectory: &isDirectory
            )
            return exists && isDirectory.boolValue
        }))

        try write("move-ok\n", to: "mv-source.txt")
        commandResults.append(try await smokeCommand("mv", tokens: ["mv", "mv-source.txt", "mv-output.txt"], workspace: workspace, verify: { _ in
            FileManager.default.fileExists(atPath: workspace.appending(path: "mv-output.txt").path)
                && !FileManager.default.fileExists(atPath: workspace.appending(path: "mv-source.txt").path)
        }))

        try write("readlink-target\n", to: "readlink-target.txt")
        try manager.createSymbolicLink(
            atPath: workspace.appending(path: "readlink-input.txt").path,
            withDestinationPath: "readlink-target.txt"
        )
        commandResults.append(try await smokeCommand("readlink", tokens: ["readlink", "readlink-input.txt"], workspace: workspace, verify: {
            $0.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "readlink-target.txt"
        }))

        try write("remove-ok\n", to: "rm-input.txt")
        commandResults.append(try await smokeCommand("rm", tokens: ["rm", "rm-input.txt"], workspace: workspace, verify: { _ in
            !FileManager.default.fileExists(atPath: workspace.appending(path: "rm-input.txt").path)
        }))

        try manager.createDirectory(at: workspace.appending(path: "rmdir-input"), withIntermediateDirectories: false)
        commandResults.append(try await smokeCommand("rmdir", tokens: ["rmdir", "rmdir-input"], workspace: workspace, verify: { _ in
            !FileManager.default.fileExists(atPath: workspace.appending(path: "rmdir-input").path)
        }))

        try write("first\nsecond\n", to: "sed-input.txt")
        commandResults.append(try await smokeCommand("sed", tokens: ["sed", "-n", "2p", "sed-input.txt"], workspace: workspace, verify: {
            $0.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "second"
        }))

        try write("charlie\nalpha\nbravo\n", to: "sort-input.txt")
        commandResults.append(try await smokeCommand("sort", tokens: ["sort", "sort-input.txt"], workspace: workspace, verify: {
            $0.stdout.hasPrefix("alpha\n")
        }))

        try write("stat-ok\n", to: "stat-input.txt")
        commandResults.append(try await smokeCommand("stat", tokens: ["stat", "stat-input.txt"], workspace: workspace, verify: { _ in true }))

        try write("first\nlast\n", to: "tail-input.txt")
        commandResults.append(try await smokeCommand("tail", tokens: ["tail", "-n", "1", "tail-input.txt"], workspace: workspace, verify: {
            $0.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "last"
        }))

        try write("tar-ok\n", to: "tar-input.txt")
        do {
            let create = try await execute(
                tokens: ["tar", "-cf", "archive.tar", "tar-input.txt"],
                workspace: workspace,
                environment: [:],
                allowNetwork: false
            )
            let inspect = try await execute(
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
                    representativeOutput: Self.smokeOutputSummary(inspect),
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

        commandResults.append(try await smokeCommand("touch", tokens: ["touch", "touch-output.txt"], workspace: workspace, verify: { _ in
            FileManager.default.fileExists(atPath: workspace.appending(path: "touch-output.txt").path)
        }))

        commandResults.append(try await smokeCommand(
            "tr",
            tokens: ["tr", "a-z", "A-Z"],
            standardInput: Data("lower\n".utf8), workspace: workspace, verify: { $0.stdout == "LOWER\n" }))

        try write("alpha\nalpha\nbeta\n", to: "uniq-input.txt")
        commandResults.append(try await smokeCommand("uniq", tokens: ["uniq", "uniq-input.txt"], workspace: workspace, verify: {
            $0.stdout == "alpha\nbeta\n"
        }))

        try write("unlink-ok\n", to: "unlink-input.txt")
        commandResults.append(try await smokeCommand("unlink", tokens: ["unlink", "unlink-input.txt"], workspace: workspace, verify: { _ in
            !FileManager.default.fileExists(atPath: workspace.appending(path: "unlink-input.txt").path)
        }))

        try write("one\ntwo\n", to: "wc-input.txt")
        commandResults.append(try await smokeCommand("wc", tokens: ["wc", "-l", "wc-input.txt"], workspace: workspace, verify: {
            $0.stdout.contains("2") && $0.stdout.contains("wc-input.txt")
        }))

        do {
            _ = try await execute(tokens: ["sh"], workspace: workspace, environment: [:], allowNetwork: false)
            policyResults.append(.init(policy: "verified_command_catalog", passed: false,
                detail: "An unlinked executable was unexpectedly accepted."))
        } catch {
            policyResults.append(.init(policy: "verified_command_catalog", passed: true, detail: error.localizedDescription))
        }
        do {
            let pipeline = try await execute(command: "cat cat-input.txt | tr a-z A-Z > pipeline-output.txt",
                workspace: workspace, environment: [:], allowNetwork: false)
            let output = try String(contentsOf: workspace.appending(path: "pipeline-output.txt"), encoding: .utf8)
            policyResults.append(.init(policy: "native_pipeline_and_redirection",
                passed: pipeline.exitCode == 0 && output == "CAT-OK\n",
                detail: "Linked native commands execute the original pipeline and output redirection."))
        } catch {
            policyResults.append(.init(policy: "native_pipeline_and_redirection", passed: false, detail: error.localizedDescription))
        }
        do {
            let chain = try await execute(command: "printf first > chain-output.txt && printf second >> chain-output.txt",
                workspace: workspace, environment: [:], allowNetwork: false)
            let output = try String(contentsOf: workspace.appending(path: "chain-output.txt"), encoding: .utf8)
            policyResults.append(.init(policy: "native_command_chaining",
                passed: chain.exitCode == 0 && output == "firstsecond",
                detail: "Both original native commands and append redirection completed in order."))
        } catch {
            policyResults.append(.init(policy: "native_command_chaining", passed: false, detail: error.localizedDescription))
        }
        // --version exits without connecting. URL arguments must reach curl rather
        // than an obsolete second Hanlin network or HTTP-scheme permission gate.
        for scheme in ["http", "https"] {
            do {
                let result = try await execute(tokens: ["curl", "--version", "\(scheme)://example.invalid"],
                    workspace: workspace, environment: [:], allowNetwork: false)
                policyResults.append(.init(policy: "curl_\(scheme)_native_dispatch",
                    passed: result.exitCode == 0 && (result.stdout + result.stderr).localizedCaseInsensitiveContains("curl"),
                    detail: "curl accepted the URL and completed its offline version command. This does not verify a network transfer."))
            } catch {
                policyResults.append(.init(policy: "curl_\(scheme)_native_dispatch", passed: false, detail: error.localizedDescription))
            }
        }

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

    private nonisolated static func smokeOutputSummary(_ result: RuntimeExecutionResult) -> String {
        let combined = (result.stdout + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.isEmpty ? "exit=\(result.exitCode ?? -1)" : String(combined.prefix(512))
    }

    // A real actor method retains Shell isolation across suspension. A nested
    // async function capturing the mutable result array crosses isolation under
    // the app's Swift compiler; no unchecked Sendable escape is needed.
    private func smokeCommand(_ command: String, tokens: [String], standardInput: Data = Data(),
                              workspace: URL, verify: @Sendable (RuntimeExecutionResult) throws -> Bool) async throws -> ShellCommandSmokeResult {
        do {
            let result = try await execute(tokens: tokens, workspace: workspace,
                environment: [:], allowNetwork: false, standardInput: standardInput)
            let passed = result.exitCode == 0 ? try verify(result) : false
            let failure = passed ? nil : "The command returned unexpected output or filesystem state."
            if !passed {
                try diagnosticLog.record("shell_command_failed", category: ShellHealthCategory.executionSmokeFailure.rawValue,
                    message: failure, command: command, exitCode: result.exitCode)
            }
            return ShellCommandSmokeResult(command: command, exitCode: result.exitCode,
                representativeOutput: Self.smokeOutputSummary(result), passed: passed, failure: failure)
        } catch {
            let native = error as NSError
            try diagnosticLog.record("shell_command_failed", category: ShellHealthCategory.executionSmokeFailure.rawValue,
                message: error.localizedDescription, command: command,
                underlyingErrorDomain: native.domain, underlyingErrorCode: native.code)
            return ShellCommandSmokeResult(command: command, exitCode: nil, representativeOutput: "",
                passed: false, failure: error.localizedDescription)
        }
    }

}
