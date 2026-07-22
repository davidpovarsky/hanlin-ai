import Foundation

struct ShellRuntimeDiagnosticEvent: Codable, Sendable {
    let timestamp: Date
    let event: String
    let category: String?
    let message: String?
    let command: String?
    let exitCode: Int?
    let resourcePath: String?
    let missingCommands: [String]?
    let underlyingErrorDomain: String?
    let underlyingErrorCode: Int?
}

struct ShellRuntimeDiagnosticLog: Sendable {
    static let fileName = "shell-runtime.log"
    static let maximumBytes = 512 * 1_024

    let url: URL

    init(fileLayout: RuntimeFileLayout) {
        url = fileLayout.logs.appending(path: Self.fileName)
    }

    func record(
        _ event: String,
        category: String? = nil,
        message: String? = nil,
        command: String? = nil,
        exitCode: Int? = nil,
        resourcePath: String? = nil,
        missingCommands: [String]? = nil,
        underlyingErrorDomain: String? = nil,
        underlyingErrorCode: Int? = nil
    ) throws {
        let entry = ShellRuntimeDiagnosticEvent(
            timestamp: .now,
            event: event,
            category: category,
            message: message,
            command: command,
            exitCode: exitCode,
            resourcePath: resourcePath,
            missingCommands: missingCommands?.isEmpty == false ? missingCommands : nil,
            underlyingErrorDomain: underlyingErrorDomain,
            underlyingErrorCode: underlyingErrorCode
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var line = try encoder.encode(entry)
        line.append(0x0A)

        let existing = (try? Data(contentsOf: url)) ?? Data()
        let available = max(0, Self.maximumBytes - line.count)
        var retained = Data(existing.suffix(available))
        if existing.count > retained.count,
           let newline = retained.firstIndex(of: 0x0A) {
            retained.removeSubrange(retained.startIndex...newline)
        }
        retained.append(line)
        try retained.write(to: url, options: .atomic)
    }
}
