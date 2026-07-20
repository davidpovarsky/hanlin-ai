import Foundation

struct MCPFileLayout: Sendable {
    let root: URL

    static let `default`: MCPFileLayout = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return MCPFileLayout(root: support.appending(path: "HanlinMCP", directoryHint: .isDirectory))
    }()

    var runtime: URL { root.appending(path: "runtime", directoryHint: .isDirectory) }
    var registry: URL { root.appending(path: "registry", directoryHint: .isDirectory) }
    var servers: URL { root.appending(path: "servers", directoryHint: .isDirectory) }
    var staging: URL { root.appending(path: "staging", directoryHint: .isDirectory) }
    var cache: URL { root.appending(path: "cache", directoryHint: .isDirectory) }
    var serverRegistry: URL { registry.appending(path: "MCPServerRegistry.json") }
    var chatSelections: URL { registry.appending(path: "MCPChatSelections.json") }
    var featureConfiguration: URL { registry.appending(path: "MCPFeatureConfiguration.json") }
    var runtimeLog: URL { runtime.appending(path: "runtime.log") }

    func serverDirectory(id: UUID) -> URL {
        servers.appending(path: id.uuidString.lowercased(), directoryHint: .isDirectory)
    }

    func prepareIfNeeded() throws {
        let manager = FileManager.default
        for directory in [root, runtime, registry, servers, staging, cache] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        for directory in [runtime, servers, staging, cache] {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableDirectory = directory
            try mutableDirectory.setResourceValues(values)
        }
    }
}

extension JSONEncoder {
    static var mcp: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

extension JSONDecoder {
    static var mcp: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
