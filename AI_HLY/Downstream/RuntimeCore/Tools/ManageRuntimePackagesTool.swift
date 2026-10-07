import Foundation

@MainActor
struct ManageRuntimePackagesTool: NativeTool {
    let name = "manage_runtime_packages"

    var catalogEntry: NativeToolCatalogEntry {
        .init(
            name: name,
            title: RuntimeL10n.string("Manage Runtime Packages"),
            summary: RuntimeL10n.string("Inspect, preview, install, probe, and uninstall packages for local Node/npm or Python/PyPI runtimes."),
            categories: ["runtime", "code", "packages"],
            keywords: ["packages", "npm", "pip", "pypi", "install", "node", "python", "חבילות", "התקנה"],
            examples: [
                "List installed Python packages",
                "Install a Python package",
                "Preview an npm package"
            ],
            systemImage: "shippingbox",
            presentationProfile: RuntimeToolSupport.profile(
                name: name,
                image: "shippingbox",
                running: "Managing runtime packages...",
                completed: "Package operation complete",
                arguments: ["runtime", "action", "package", "version"]
            )
        )
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: RuntimeL10n.string("Manage packages for local runtime environments (Node/npm or Python/PyPI). Actions: 'list' (installed packages), 'preview' (inspect metadata/dependencies before installing), 'install' (download, extract, verify, and register), 'uninstall' (remove), and 'probe' (verify import and entry point execution)."),
            parameters: NativeToolSchema.object(
                properties: [
                    "runtime": NativeToolSchema.string(
                        description: RuntimeL10n.string("Target runtime environment."),
                        enumValues: ["node", "python"]
                    ),
                    "action": NativeToolSchema.string(
                        description: RuntimeL10n.string("Package management operation to perform."),
                        enumValues: ["list", "preview", "install", "uninstall", "probe"]
                    ),
                    "package": NativeToolSchema.string(
                        description: RuntimeL10n.string("Package name or specifier (e.g. 'requests', 'yocto-queue'). Required for preview, install, uninstall, probe.")
                    ),
                    "version": NativeToolSchema.string(
                        description: RuntimeL10n.string("Optional explicit version to target.")
                    )
                ],
                required: ["runtime", "action"]
            )
        )
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.validatedDictionary(
                from: argumentsJSON,
                allowedKeys: ["runtime", "action", "package", "version"]
            )
            let runtime = try NativeToolJSON.strictRequiredString(arguments, "runtime").lowercased()
            let action = try NativeToolJSON.strictRequiredString(arguments, "action").lowercased()
            let packageName = try? NativeToolJSON.strictOptionalString(arguments, "package")
            let version = try? NativeToolJSON.strictOptionalString(arguments, "version")

            guard runtime == "node" || runtime == "python" else {
                throw NativeToolJSON.JSONError.invalidValue(key: "runtime", description: "Must be 'node' or 'python'")
            }

            let resultText: String

            if runtime == "python" {
                let manager = AppRuntimeCore.shared.pythonPackages
                switch action {
                case "list":
                    let packages = try await manager.installed()
                    if packages.isEmpty {
                        resultText = "No Python packages currently installed in the local environment."
                    } else {
                        var lines = ["Installed Python packages (\(packages.count)):"]
                        for pkg in packages {
                            let size = ByteCountFormatter.string(fromByteCount: pkg.storageBytes, countStyle: .file)
                            lines.append("- `\(pkg.name)` (\(pkg.version)) — import: `\(pkg.importName)`, storage: \(size)")
                        }
                        resultText = lines.joined(separator: "\n")
                    }

                case "preview":
                    guard let name = packageName, !name.isEmpty else {
                        throw NativeToolJSON.JSONError.missingKey("package")
                    }
                    let preview = try await manager.preview(name: name, version: version)
                    resultText = """
                    Package Preview for '\(preview.name)':
                    - Resolved Version: \(preview.version)
                    - Pure Python: \(preview.isPurePython ? "Yes (compatible)" : "No (requires native backend)")
                    - Summary: \(preview.summary ?? "None provided")
                    - Wheel File: \(preview.wheelFileName ?? "None")
                    - Compatibility: \(preview.compatibilityExplanation)
                    """

                case "install":
                    guard let name = packageName, !name.isEmpty else {
                        throw NativeToolJSON.JSONError.missingKey("package")
                    }
                    let record = try await manager.install(name: name, version: version)
                    let probe = try? await manager.probe(record)
                    let probeStatus = (probe?.exitCode == 0) ? "importVerified" : "installed (import unverified)"
                    resultText = """
                    Successfully installed Python package:
                    - Package: `\(record.name)`
                    - Version: \(record.version)
                    - Status: \(probeStatus)
                    - Wheel: \(record.wheelFileName)
                    - Import Name: `\(record.importName)`
                    - Dependencies: \(record.resolvedDependencies?.map(\.name).joined(separator: ", ") ?? "None")
                    """

                case "probe":
                    guard let name = packageName, !name.isEmpty else {
                        throw NativeToolJSON.JSONError.missingKey("package")
                    }
                    guard let record = try await manager.installed().first(where: { $0.normalizedName == name.lowercased() || $0.name.lowercased() == name.lowercased() }) else {
                        resultText = "Package '\(name)' is not installed. Install it first before probing."
                        break
                    }
                    let probe = try await manager.probe(record)
                    let status = (probe.exitCode == 0) ? "importVerified" : "importFailed"
                    resultText = """
                    Probe result for Python package '\(record.name)':
                    - Status: \(status)
                    - Exit Code: \(probe.exitCode)
                    - Output: \(probe.stdout.isEmpty ? "(none)" : probe.stdout)
                    - Error: \(probe.stderr.isEmpty ? "(none)" : probe.stderr)
                    """

                case "uninstall":
                    guard let name = packageName, !name.isEmpty else {
                        throw NativeToolJSON.JSONError.missingKey("package")
                    }
                    guard let record = try await manager.installed().first(where: { $0.normalizedName == name.lowercased() || $0.name.lowercased() == name.lowercased() }) else {
                        resultText = "Package '\(name)' is not currently installed."
                        break
                    }
                    try await manager.uninstall(record)
                    resultText = "Successfully uninstalled Python package '\(record.name)'."

                default:
                    throw NativeToolJSON.JSONError.invalidValue(key: "action", description: "Unknown action '\(action)'. Valid actions: list, preview, install, uninstall, probe")
                }

            } else {
                // Node runtime
                let manager = AppRuntimeCore.shared.nodePackages
                switch action {
                case "list":
                    let packages = try await manager.installed()
                    if packages.isEmpty {
                        resultText = "No global Node packages currently installed."
                    } else {
                        var lines = ["Installed Node packages (\(packages.count)):"]
                        for pkg in packages {
                            lines.append("- `\(pkg.name)` (\(pkg.version)) — entry: `\(pkg.entryPoint)` [\(pkg.moduleKind)]")
                        }
                        resultText = lines.joined(separator: "\n")
                    }

                case "preview":
                    guard let name = packageName, !name.isEmpty else {
                        throw NativeToolJSON.JSONError.missingKey("package")
                    }
                    let preview = try await manager.preview(name: name, version: version)
                    resultText = """
                    Node Package Preview for '\(preview.name)':
                    - Resolved Version: \(preview.version)
                    - Summary: \(preview.summary ?? "None provided")
                    - Entry Points: \(preview.entryPoints.joined(separator: ", "))
                    - Dependencies: \(preview.dependencyCount)
                    - Node Requirement: \(preview.nodeRequirement ?? "unspecified")
                    - Compatibility: \(preview.compatibility.verdict)
                    """

                case "install":
                    guard let name = packageName, !name.isEmpty else {
                        throw NativeToolJSON.JSONError.missingKey("package")
                    }
                    let record = try await manager.install(name: name, version: version)
                    let probe = try? await manager.probe(record)
                    let probeStatus = (probe?.exitCode == 0) ? "importVerified" : "installed"
                    resultText = """
                    Successfully installed Node package:
                    - Package: `\(record.name)`
                    - Version: \(record.version)
                    - Status: \(probeStatus)
                    - Entry Point: `\(record.entryPoint)`
                    - Module Kind: \(record.moduleKind)
                    """

                case "probe":
                    guard let name = packageName, !name.isEmpty else {
                        throw NativeToolJSON.JSONError.missingKey("package")
                    }
                    guard let record = try await manager.installed().first(where: { $0.name == name }) else {
                        resultText = "Node package '\(name)' is not installed. Install it first before probing."
                        break
                    }
                    let probe = try await manager.probe(record)
                    let status = (probe.exitCode == 0) ? "importVerified" : "importFailed"
                    resultText = """
                    Probe result for Node package '\(record.name)':
                    - Status: \(status)
                    - Exit Code: \(probe.exitCode)
                    - Output: \(probe.stdout.isEmpty ? "(none)" : probe.stdout)
                    - Error: \(probe.stderr.isEmpty ? "(none)" : probe.stderr)
                    """

                case "uninstall":
                    guard let name = packageName, !name.isEmpty else {
                        throw NativeToolJSON.JSONError.missingRequiredString("package")
                    }
                    try await manager.uninstall(name: name)
                    resultText = "Successfully uninstalled Node package '\(name)'."

                default:
                    throw NativeToolJSON.JSONError.invalidValue(key: "action", description: "Unknown action '\(action)'. Valid actions: list, preview, install, uninstall, probe")
                }
            }

            let executionResult = RuntimeExecutionResult(
                executionID: UUID(),
                stdout: resultText,
                stderr: "",
                value: nil,
                exitCode: 0,
                durationMilliseconds: 1,
                didTimeOut: false,
                wasCancelled: false,
                outputWasTruncated: false
            )

            return RuntimeToolSupport.result(
                executionResult,
                title: "Manage Runtime Packages",
                systemImage: "shippingbox",
                runtimeKind: runtime == "python" ? .localPython : .node,
                argumentKeys: Array(arguments.keys)
            )

        } catch {
            return RuntimeToolSupport.failure(error, title: "Manage Runtime Packages Failed", runtimeKind: .shell)
        }
    }
}
