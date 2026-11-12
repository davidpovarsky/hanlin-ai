import Foundation

enum AgentDiagnosticsRedactor {
    static func redactKnownCredentials(in value: Any, credentials: Set<String>) -> Any {
        if let object = value as? [String: Any] { return object.mapValues { redactKnownCredentials(in: $0, credentials: credentials) } }
        if let array = value as? [Any] { return array.map { redactKnownCredentials(in: $0, credentials: credentials) } }
        if var text = value as? String {
            for secret in credentials { text = text.replacingOccurrences(of: secret, with: "<redacted>") }
            return text
        }
        return value
    }
    private static let secretKeyNames: Set<String> = [
        "access_token", "accesstoken", "refresh_token", "refreshtoken",
        "api_key", "apikey", "x_api_key", "authorization", "proxy_authorization",
        "cookie", "set_cookie", "password", "secret", "client_secret", "clientsecret",
        "private_key", "privatekey", "credential", "github_token", "githubtoken",
        "mcp_auth", "mcpauth", "auth_token", "bearer_token", "token", "signature", "sig"
    ]

    private static let secretKeySuffixes = [
        "_access_token", "_refresh_token", "_auth_token", "_bearer_token",
        "_api_key", "_client_secret", "_private_key", "_github_token"
    ]

    static func sanitizeJSONObject(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, item in
                let normalizedKey = item.key
                    .lowercased()
                    .replacingOccurrences(of: "-", with: "_")
                result[item.key] = isSecretKey(normalizedKey)
                    ? "<redacted>"
                    : sanitizeJSONObject(item.value)
            }
        }
        if let array = value as? [Any] { return array.map(sanitizeJSONObject) }
        if let string = value as? String { return sanitize(string) }
        return value
    }

    private static func isSecretKey(_ normalizedKey: String) -> Bool {
        secretKeyNames.contains(normalizedKey)
            || secretKeySuffixes.contains(where: normalizedKey.hasSuffix)
    }

    static func sanitize(_ value: String) -> String {
        if let data = value.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           object is [String: Any] || object is [Any] {
            return sanitizedJSONString(from: object)
        }
        if value.hasPrefix("data:"), value.contains(";base64,") { return "<binary attachment retained in encrypted raw>" }
        var result = value
        let replacements = [
            ("(?i)bearer\\s+[a-z0-9._~+/-]+=*", "Bearer <redacted>"),
            ("(?i)(api[_-]?key|authorization|access[_-]?token|refresh[_-]?token|password|secret|cookie)\\s*[:=]\\s*[^\\s,;\\\"}]+", "$1=<redacted>"),
            ("(?i)sk-[a-z0-9_-]*", "<redacted>"),
            ("-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----[\\s\\S]*?-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----", "<redacted>"),
            ("(?i)([?&](?:signature|sig|token|key|credential|x-amz-signature|x-amz-credential|x-amz-security-token|x-goog-signature|x-goog-credential)=)[^&\\s]+", "$1<redacted>"),
            ("(?i)(https?://)[^/@\\s]+:[^/@\\s]+@", "$1<redacted>@")
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
        return string
    }
}
