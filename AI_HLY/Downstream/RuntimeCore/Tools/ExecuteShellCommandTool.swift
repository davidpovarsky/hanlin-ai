import Foundation

struct ExecuteShellCommandTool: NativeTool {
    let name = "execute_shell_command"

    var catalogEntry: NativeToolCatalogEntry {
        .init(name: name, title: RuntimeL10n.string("Shell / ios_system"), summary: RuntimeL10n.string("Run one structurally parsed command from the verified ios_system catalog."), categories: ["runtime", "code", "shell"], keywords: ["shell", "files", "ios_system"], examples: ["List the files in the local workspace"], isSensitive: true, systemImage: "apple.terminal", isEnabledByDefault: false, presentationProfile: RuntimeToolSupport.profile(name: name, image: "apple.terminal", running: "Running shell command", completed: "Shell command completed", arguments: ["command"]))
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(name: name, description: RuntimeL10n.string("Run one approved ios_system command in an isolated app workspace. This is not a Linux shell."), parameters: NativeToolSchema.object(properties: [
            "command": NativeToolSchema.string(description: RuntimeL10n.string("One command from the verified catalog; no pipes, redirection, substitution, or chaining.")),
            "allow_network": ["type": "boolean", "description": RuntimeL10n.string("Explicitly allow HTTPS network access for curl.")]
        ], required: ["command"]))
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.dictionary(from: argumentsJSON)
            let command = try NativeToolJSON.requiredString(arguments, "command")
            let workspace = try RuntimeFileLayout.default.workspace(client: .tools, identifier: name)
            let environment = try await AppRuntimeCore.shared.environment.resolved(scopes: [.shared, .shell])
            let result = try await AppRuntimeCore.shared.shell.execute(command: command, workspace: workspace, environment: environment, allowNetwork: NativeToolJSON.bool(arguments, "allow_network"))
            return RuntimeToolSupport.result(result, title: "Shell / ios_system", systemImage: "apple.terminal")
        } catch { return RuntimeToolSupport.failure(error, title: "Shell command failed") }
    }
}
