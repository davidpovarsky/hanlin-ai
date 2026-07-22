import Foundation

enum MCPL10n {
    static func string(_ key: String) -> String {
        NSLocalizedString(key, tableName: "MCPLocalizable", bundle: .main, value: key, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: .current, arguments: arguments)
    }
}

extension MCPCompatibilityFinding {
    var localizedMessage: String {
        switch code {
        case "reachable_blocked_builtin":
            MCPL10n.format(
                "The selected entry point attempted to load %@ from %@.",
                specifier ?? "module",
                parentPath ?? path ?? "entry point"
            )
        case "runtime_probe_failed":
            MCPL10n.format("The runtime probe failed: %@", message)
        case "configuration_required":
            MCPL10n.format("This server requires configuration before its runtime probe can complete: %@", message)
        case "reachable_native_addon":
            MCPL10n.format("The selected entry point loaded native addon %@.", path ?? specifier ?? "*.node")
        case "reachable_external_executable":
            MCPL10n.format(
                "The selected entry point requested external process capability %@ from %@.",
                specifier ?? "process",
                parentPath ?? path ?? "entry point"
            )
        case "dynamic_resolution_unverified":
            MCPL10n.format("Dynamic module resolution could not be verified in %@.", path ?? parentPath ?? "a loaded module")
        case "unreachable_blocked_reference":
            MCPL10n.format(
                "The package contains unused incompatible code at %@; it was not loaded by the selected entry point.",
                path ?? "an unreachable module"
            )
        case "runtime_probe_passed":
            MCPL10n.string("The selected entry point passed the runtime probe.")
        default:
            message
        }
    }
}

extension MCPInstallTerminalError {
    var localizedMessage: String {
        if let finding = findings?.first {
            return finding.localizedMessage
        }
        switch code {
        case "runtime_probe_failed", "module_policy_unavailable":
            return MCPL10n.format("The runtime probe failed: %@", message)
        case "configuration_required":
            return MCPL10n.format("This server requires configuration before its runtime probe can complete: %@", message)
        default:
            return message
        }
    }
}
