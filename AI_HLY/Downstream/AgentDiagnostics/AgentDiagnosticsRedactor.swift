import Foundation

enum AgentDiagnosticsRedactor {
    private static let latencyMetricKeys: Set<String> = ["time_to_first_token", "time_to_first_answer_token"]
    /// Secrets actually present in structured requests must also be masked if
    /// the provider echoes them in a different, ordinary text field.
    static func credentials(in value: Any) -> Set<String> {
        var found: Set<String> = []
        func visit(_ value: Any) {
            if let object = value as? [String: Any] {
                for (name, value) in object {
                    if isSecretKey(normalizedKey(name)), let text = value as? String, !text.isEmpty {
                        found.insert(text)
                        if text.lowercased().hasPrefix("bearer "), let token = text.split(whereSeparator: \.isWhitespace).last,
                           !token.isEmpty { found.insert(String(token)) }
                        if normalizedKey(name).hasSuffix("cookie") {
                            for part in text.split(separator: ";") {
                                let pair = part.split(separator: "=", maxSplits: 1)
                                guard pair.count == 2 else { continue }
                                let field = pair[0].trimmingCharacters(in: .whitespaces).lowercased()
                                if ["path", "domain", "expires", "max-age", "samesite"].contains(field) { continue }
                                let value = pair[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                                if !value.isEmpty { found.insert(value) }
                            }
                        }
                    } else { visit(value) }
                }
            } else if let values = value as? [Any] { values.forEach(visit) }
            else if let text = value as? String, let data = text.data(using: .utf8),
                    let nested = try? JSONSerialization.jsonObject(with: data),
                    nested is [String: Any] || nested is [Any] { visit(nested) }
            else if let text = value as? String, let url = URLComponents(string: text), url.scheme != nil {
                for item in url.queryItems ?? [] {
                    let name = normalizedKey(item.name)
                    if isSecretKey(name) || name == "key" || name.hasSuffix("_signature") || name.hasSuffix("_credential"),
                       let secret = item.value, !secret.isEmpty { found.insert(secret) }
                }
                if let password = url.password, !password.isEmpty { found.insert(password) }
            }
        }
        visit(value)
        return found
    }

    private static func normalizedKey(_ key: String) -> String {
        var decoded = key
        for _ in 0..<2 {
            guard let next = decoded.removingPercentEncoding, next != decoded else { break }
            decoded = next
        }
        return decoded.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1_$2", options: .regularExpression)
            .lowercased().replacingOccurrences(of: "-", with: "_")
    }
    static func redactKnownCredentials(in value: Any, credentials: Set<String>) -> Any {
        if let object = value as? [String: Any] { return object.mapValues { redactKnownCredentials(in: $0, credentials: credentials) } }
        if let array = value as? [Any] { return array.map { redactKnownCredentials(in: $0, credentials: credentials) } }
        if var text = value as? String {
            for secret in credentials.sorted(by: { $0.count > $1.count }) where !secret.isEmpty {
                if secret.count < 4 {
                    text = text.replacingOccurrences(of: "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: secret) + "(?![\\p{L}\\p{N}_])",
                        with: "<redacted>", options: .regularExpression)
                } else { text = text.replacingOccurrences(of: secret, with: "<redacted>") }
            }
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
                let name = normalizedKey(item.key)
                // These are typed latency measurements, not credentials. The
                // generic *_token rule otherwise replaces Double with String
                // and makes completed session files undecodable. String values
                // under these names still follow the conservative secret rule.
                let isLatency = latencyMetricKeys.contains(name)
                    && (item.value as? NSNumber).map { !["c", "B"].contains(String(cString: $0.objCType)) } == true
                result[item.key] = isSecretKey(name) && !isLatency
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
            || ["_token", "_secret", "_password", "_credential", "_cookie", "_authorization"].contains(where: normalizedKey.hasSuffix)
            || ["authorization_", "proxy_authorization_", "access_token_", "refresh_token_", "auth_token_", "bearer_token_"].contains(where: normalizedKey.hasPrefix)
    }

    static func sanitize(_ value: String) -> String {
        if let data = value.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           object is [String: Any] || object is [Any] {
            return sanitizedJSONString(from: object)
        }
        if value.hasPrefix("data:"), value.contains(";base64,") { return "<binary attachment retained in encrypted raw>" }
        var result = value
        if let pattern = try? NSRegularExpression(pattern: "https?://[^\\s<>\"']+", options: .caseInsensitive) {
            for match in pattern.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                result.replaceSubrange(range, with: sanitizeURL(String(result[range])))
            }
        }
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

    private static func sanitizeURL(_ value: String) -> String {
        guard var url = URLComponents(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false else { return value }
        var changed = false
        if url.password != nil { url.user = "<redacted>"; url.password = nil; changed = true }
        if let query = url.queryItems {
            let items = query.map { item -> URLQueryItem in
                let name = normalizedKey(item.name)
                guard isSecretKey(name) || name == "key" || name.hasSuffix("_signature") || name.hasSuffix("_credential") else { return item }
                changed = true
                return URLQueryItem(name: item.name, value: "<redacted>")
            }
            if changed { url.queryItems = items }
        }
        return changed ? (url.string ?? "<redacted URL>") : value
    }

    static func sanitizedJSONString(from object: Any, pretty: Bool = false) -> String {
        let sanitized = sanitizeJSONObject(object)
        guard JSONSerialization.isValidJSONObject(sanitized),
              let data = try? JSONSerialization.data(withJSONObject: sanitized, options: pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }
}
