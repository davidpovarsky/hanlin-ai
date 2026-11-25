import Foundation

enum ScriptWidgetNetworkPolicy {
    static func isValidDomainDeclaration(_ value: String) -> Bool {
        if value == "*" { return true } // Host-generated legacy manifest preserves unrestricted network domains.
        let normalized = value.lowercased()
        return value == normalized && !normalized.contains("://") && !normalized.contains("/") && !normalized.contains(":")
            && !normalized.hasPrefix(".") && !normalized.hasSuffix(".")
            && normalized.range(of: "^[a-z0-9*.-]+$", options: .regularExpression) != nil
            && (!normalized.contains("*") || normalized.hasPrefix("*."))
    }

    static func host(_ host: String, matchesAny declarations: [String]) -> Bool {
        let value = host.lowercased()
        return declarations.contains { declaration in
            if declaration == "*" { return true }
            let domain = declaration.lowercased()
            if domain.hasPrefix("*.") {
                let suffix = String(domain.dropFirst(2))
                return value != suffix && value.hasSuffix("." + suffix)
            }
            return value == domain
        }
    }

}

let valid = ["*", "example.com", "*.example.com", "api.example.com"]
let invalid = ["Example.com", "https://example.com", "example.com/path", "example.com:443", ".example.com", "example.com.", "api*.example.com", "bad host", ""]
for value in valid {
    precondition(ScriptWidgetNetworkPolicy.isValidDomainDeclaration(value), "Expected valid: \(value)")
}
for value in invalid {
    precondition(!ScriptWidgetNetworkPolicy.isValidDomainDeclaration(value), "Expected invalid: \(value)")
}
let matching: [(String, [String], Bool)] = [
    ("example.com", ["*"], true),
    ("other.invalid", ["*"], true),
    ("API.EXAMPLE.COM", ["api.example.com"], true),
    ("api.example.com", ["*.example.com"], true),
    ("example.com", ["*.example.com"], false),
    ("api.other.com", ["*.example.com"], false),
    ("api.example.com", ["example.com"], false)
]
for (host, declarations, expected) in matching {
    precondition(ScriptWidgetNetworkPolicy.host(host, matchesAny: declarations) == expected, "Unexpected match: \(host) in \(declarations)")
}
print("PASS: exact installed Swift helper; 4 valid declarations, 9 malformed declarations rejected, 7 existing host-matching cases")
