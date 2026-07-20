import CryptoKit
import Foundation

enum MCPToolNameCodec {
    static func slug(_ value: String) -> String {
        var result = value.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : "_"
        }.reduce(into: "") { $0.append($1) }
        result = result.replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if result.first?.isLetter != true { result = "s_\(result)" }
        return result.isEmpty ? "server" : result
    }

    static func exposedName(serverSlug: String, toolName: String, discriminator: String) -> String {
        let base = "mcp__\(slug(serverSlug))__\(slug(toolName))"
        guard base.count > 64 else { return base }
        let suffix = shortHash("\(base):\(discriminator)")
        return "\(base.prefix(55))_\(suffix)"
    }

    static func collisionName(_ name: String, discriminator: String) -> String {
        let suffix = shortHash(discriminator)
        return "\(name.prefix(55))_\(suffix)"
    }

    private static func shortHash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}
