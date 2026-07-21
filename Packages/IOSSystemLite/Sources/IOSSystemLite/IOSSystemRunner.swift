import Foundation
import ios_system

public struct IOSSystemExecution: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
}

public enum IOSSystemRunner {
    public static let linkedCommands: Set<String> = [
        "awk", "cat", "cp", "curl", "grep", "head", "ln", "ls", "mkdir", "mv",
        "readlink", "rm", "rmdir", "sed", "sort", "stat", "tail", "tar", "touch",
        "tr", "uniq", "unlink", "wc"
    ]

    public static func availableCommands() -> [String] {
        configureCommands()
        let discovered = (commandsAsArray() as? [String]) ?? []
        return discovered.filter(linkedCommands.contains).sorted()
    }

    public static func execute(tokens: [String], workspace: URL, environment: [String: String]) throws -> IOSSystemExecution {
        guard let command = tokens.first, linkedCommands.contains(command), !tokens.isEmpty else {
            throw NSError(domain: "IOSSystemLite", code: 1, userInfo: [NSLocalizedDescriptionKey: "The command is not linked or allowed."])
        }
        configureCommands()
        guard ios_setMiniRootURL(workspace as NSURL) == 1 else {
            throw NSError(domain: "IOSSystemLite", code: 2, userInfo: [NSLocalizedDescriptionKey: "ios_system rejected the workspace miniRoot."])
        }
        ios_setDirectoryURL(workspace as NSURL)
        let oldEnvironment = ProcessInfo.processInfo.environment
        for (name, value) in environment { setenv(name, value, 1) }
        defer {
            for name in environment.keys where oldEnvironment[name] == nil { unsetenv(name) }
            for (name, value) in oldEnvironment where environment[name] != nil { setenv(name, value, 1) }
        }
        guard let input = tmpfile(), let output = tmpfile(), let error = tmpfile() else {
            throw NSError(domain: "IOSSystemLite", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not allocate command streams."])
        }
        defer { fclose(input); fclose(output); fclose(error) }
        ios_setStreams(input, output, error)
        joinMainThread = true
        let rendered = tokens.map(shellEscape).joined(separator: " ")
        let status = rendered.withCString { ios_system(UnsafeMutablePointer(mutating: $0)) }
        fflush(output); fflush(error)
        return IOSSystemExecution(stdout: read(output), stderr: read(error), exitCode: Int32(status))
    }

    private static func configureCommands() {
        initializeEnvironment()
        if let url = Bundle.module.url(forResource: "RuntimeCommands", withExtension: "plist") {
            _ = addCommandList(url.path)
        }
    }

    private static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func read(_ file: UnsafeMutablePointer<FILE>) -> String {
        rewind(file)
        var bytes: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = fread(&buffer, 1, buffer.count, file)
            if count == 0 { break }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
