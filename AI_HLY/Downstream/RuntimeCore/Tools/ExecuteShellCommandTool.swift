import Foundation

struct ExecuteShellCommandTool: NativeTool {
    let name = "execute_shell_command"
    private let hostContext: HanlinHostCallContext?

    init(hostContext: HanlinHostCallContext? = nil) {
        self.hostContext = hostContext
    }

    var catalogEntry: NativeToolCatalogEntry {
        .init(name: name, title: RuntimeL10n.string("Shell / ios_system"), summary: RuntimeL10n.string("Run one approved ios_system program with a structured argument array."), categories: ["runtime", "code", "shell"], keywords: ["shell", "files", "ios_system"], examples: ["List the files in the local workspace"], isSensitive: true, systemImage: "apple.terminal", isEnabledByDefault: false, presentationProfile: RuntimeToolSupport.profile(name: name, image: "apple.terminal", running: "Running shell command", completed: "Shell command completed", arguments: ["program", "arguments", "allow_network"]))
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(name: name, description: RuntimeL10n.string("Run exactly one approved ios_system program in the assigned workspace. This is not a POSIX/Linux shell: there is no command chaining, pipes, redirection, substitution, or arbitrary binaries. Paths must stay inside the workspace. curl accepts HTTPS only and requires allow_network=true except for curl --version."), parameters: NativeToolSchema.object(properties: [
            "program": NativeToolSchema.string(description: RuntimeL10n.string("Approved program name."), enumValues: ShellRuntimeService.capabilities.map(\.name)),
            "arguments": NativeToolSchema.stringArray(description: RuntimeL10n.string("Program arguments as separate strings; shell syntax is not interpreted."), maximumItems: 127),
            "allow_network": ["type": "boolean", "description": RuntimeL10n.string("Explicitly allow HTTPS network access for curl.")]
        ], required: ["program"]))
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        guard await isAllowedByCatalog() else {
            return RuntimeToolSupport.failure(
                HanlinHostServiceError.capabilityNotGranted("tool.\(name)"),
                title: "Shell disabled",
                runtimeKind: .shell
            )
        }
        do {
            let arguments = try NativeToolJSON.validatedDictionary(
                from: argumentsJSON,
                allowedKeys: ["program", "arguments", "allow_network", "command"]
            )
            let program = try NativeToolJSON.strictOptionalString(arguments, "program")
            let legacyCommand = try NativeToolJSON.strictOptionalString(arguments, "command")
            guard (program == nil) != (legacyCommand == nil) else {
                throw NativeToolJSON.JSONError.invalidValue(
                    key: "program",
                    description: "provide the structured program form only"
                )
            }
            let argv = try NativeToolJSON.strictStringArray(arguments, "arguments")
            guard argv.count <= 127 else {
                throw NativeToolJSON.JSONError.invalidValue(
                    key: "arguments",
                    description: "at most 127 arguments are permitted"
                )
            }
            let allowNetwork = try NativeToolJSON.strictBool(arguments, "allow_network")
            let environment = try await AppRuntimeCore.shared.environment.resolved(scopes: [.shared, .shell])
            let result: RuntimeExecutionResult
            if let program {
                guard ShellRuntimeService.capabilities.contains(where: { $0.name == program }) else {
                    throw NativeToolJSON.JSONError.invalidValue(
                        key: "program",
                        description: "program is not in the approved ios_system catalog"
                    )
                }
                result = try await AgentHostServicesAdapter.executeShell(
                    program: program,
                    arguments: argv,
                    environment: environment,
                    allowNetwork: allowNetwork,
                    context: hostContext
                )
            } else {
                guard argv.isEmpty else {
                    throw NativeToolJSON.JSONError.invalidValue(
                        key: "arguments",
                        description: "arguments cannot accompany the legacy command input"
                    )
                }
                result = try await AgentHostServicesAdapter.executeLegacyShell(
                    command: legacyCommand ?? "",
                    environment: environment,
                    allowNetwork: allowNetwork,
                    context: hostContext
                )
            }
            return RuntimeToolSupport.result(
                result,
                title: "Shell / ios_system",
                systemImage: "apple.terminal",
                runtimeKind: .shell,
                argumentKeys: Array(arguments.keys)
            )
        } catch { return RuntimeToolSupport.failure(error, title: "Shell command failed", runtimeKind: .shell) }
    }

    private func isAllowedByCatalog() async -> Bool {
        await MainActor.run {
            NativeToolCatalog.shared.ensureBuiltinsRegistered()
            guard let entry = NativeToolCatalog.shared.entry(named: name) else { return true }
            return NativeToolCatalog.shared.isEffectivelyEnabled(entry)
        }
    }
}
