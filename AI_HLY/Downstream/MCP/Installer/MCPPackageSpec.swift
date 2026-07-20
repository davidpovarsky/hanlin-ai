import Foundation

enum MCPPackageSource: Codable, Hashable, Sendable {
    case npm(name: String, version: String?)
    case remoteArchive(URL)
    case localArchive(URL)
}

struct MCPPackageSpec: Codable, Hashable, Sendable {
    var source: MCPPackageSource

    init(_ rawValue: String) throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: value), let scheme = url.scheme?.lowercased(),
           ["https", "http"].contains(scheme), url.pathExtension.lowercased() == "tgz" {
            source = .remoteArchive(url)
            return
        }

        let name: String
        let version: String?
        if value.hasPrefix("@") {
            guard let slash = value.firstIndex(of: "/") else { throw MCPError.invalidPackageSpec }
            let versionSeparator = value[value.index(after: slash)...].lastIndex(of: "@")
            if let versionSeparator {
                name = String(value[..<versionSeparator])
                version = String(value[value.index(after: versionSeparator)...])
            } else {
                name = value
                version = nil
            }
        } else if let separator = value.lastIndex(of: "@") {
            name = String(value[..<separator])
            version = String(value[value.index(after: separator)...])
        } else {
            name = value
            version = nil
        }
        let pattern = #"^(?:@[a-z0-9][a-z0-9._-]*/)?[a-z0-9][a-z0-9._-]*$"#
        guard name.range(of: pattern, options: .regularExpression) != nil,
              version?.isEmpty != true,
              version?.contains(where: { $0.isWhitespace || $0 == "/" }) != true else {
            throw MCPError.invalidPackageSpec
        }
        source = .npm(name: name, version: version)
    }

    init(localArchive: URL) throws {
        guard localArchive.pathExtension.lowercased() == "tgz" else {
            throw MCPError.invalidPackageSpec
        }
        source = .localArchive(localArchive)
    }

    var hostPayload: [String: String] {
        switch source {
        case .npm(let name, let version):
            var value = ["kind": "npm", "name": name]
            if let version { value["version"] = version }
            return value
        case .remoteArchive(let url):
            return ["kind": "url", "url": url.absoluteString]
        case .localArchive(let url):
            return ["kind": "file", "path": url.path]
        }
    }
}
