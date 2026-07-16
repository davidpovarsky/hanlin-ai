import Foundation

enum AgentDiagnosticsRedactor {
    private static let sensitiveKeyFragments = [
        "authorization", "api_key", "apikey", "token", "access_token", "refresh_token",
        "cookie", "password", "private_key", "secret", "credential", "github_token", "mcp_auth"
    ]

    static func sanitizeJSONObject(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, item in
                let key = item.key.lowercased()
                result[item.key] = sensitiveKeyFragments.contains(where: key.contains)
                    ? "<redacted>"
                    : sanitizeJSONObject(item.value)
            }
        }
        if let array = value as? [Any] { return array.map(sanitizeJSONObject) }
        if let string = value as? String { return sanitize(string) }
        return value
    }

    static func sanitize(_ value: String) -> String {
        var result = value
        let replacements = [
            ("(?i)bearer\\s+[a-z0-9._~+/-]+=*", "Bearer <redacted>"),
            ("(?i)(api[_-]?key|authorization|access[_-]?token|refresh[_-]?token|password|secret|cookie)\\s*[:=]\\s*[^\\s,;\\\"}]+", "$1=<redacted>"),
            ("(?i)sk-[a-z0-9_-]{12,}", "<redacted>"),
            ("-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----[\\s\\S]*?-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----", "<redacted>"),
            ("(?i)([?&](?:signature|sig|token|key|credential)=)[^&\\s]+", "$1<redacted>")
        ]
        for (pattern, replacement) in replacements {
            result = result.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return result
    }

    static func sanitizedJSONString(from object: Any, pretty: Bool = false) -> String {
        let sanitized = sanitizeJSONObject(object)
        guard JSONSerialization.isValidJSONObject(sanitized),
              let data = try? JSONSerialization.data(withJSONObject: sanitized, options: pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return sanitize(string)
    }
}
