import Foundation

enum MCPLogRedactor {
    private static let keys = [
        "authorization", "bearer", "token", "api_key", "apikey", "secret", "password", "cookie"
    ]

    static func redact(_ value: String) -> String {
        var redacted = value
        for key in keys {
            let pattern = "(?i)(\(NSRegularExpression.escapedPattern(for: key))\\s*[:=]\\s*)([^\\s,;]+)"
            redacted = redacted.replacingOccurrences(
                of: pattern,
                with: "$1<redacted>",
                options: .regularExpression
            )
        }
        redacted = redacted.replacingOccurrences(
            of: "(?i)Bearer\\s+[A-Za-z0-9._~+/=-]+",
            with: "Bearer <redacted>",
            options: .regularExpression
        )
        return redacted
    }
}
