import Foundation

struct MCPFileLayout: Sendable {
    let root: URL

    static let `default` = MCPFileLayout(root: RuntimeFileLayout.default.root)

    private var shared: RuntimeFileLayout { RuntimeFileLayout(root: root) }
    var runtime: URL { shared.nodeRuntime }
    var registry: URL { shared.registry.appending(path: "mcp", directoryHint: .isDirectory) }
    var servers: URL { shared.mcpPackages }
    var staging: URL { shared.staging.appending(path: "mcp", directoryHint: .isDirectory) }
    var cache: URL { shared.npmCache }
    var serverRegistry: URL { registry.appending(path: "MCPServerRegistry.json") }
    var chatSelections: URL { registry.appending(path: "MCPChatSelections.json") }
    var featureConfiguration: URL { registry.appending(path: "MCPFeatureConfiguration.json") }
    var runtimeLog: URL { shared.logs.appending(path: "mcp-runtime.log") }

    func serverDirectory(id: UUID) -> URL {
        servers.appending(path: id.uuidString.lowercased(), directoryHint: .isDirectory)
    }

    func prepareIfNeeded() throws {
        let manager = FileManager.default
        try shared.prepareIfNeeded()
        for directory in [root, runtime, registry, servers, staging, cache] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        for directory in [runtime, servers, staging, cache] {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableDirectory = directory
            try mutableDirectory.setResourceValues(values)
        }
        try migrateLegacyDataIfNeeded()
    }

    private func migrateLegacyDataIfNeeded() throws {
        let manager = FileManager.default
        let legacy = RuntimeFileLayout.legacyMCPRoot
        guard manager.fileExists(atPath: legacy.path), legacy.standardizedFileURL != root.standardizedFileURL else { return }
        let mappings: [(URL, URL)] = [
            (legacy.appending(path: "registry", directoryHint: .isDirectory), registry),
            (legacy.appending(path: "servers", directoryHint: .isDirectory), servers)
        ]
        for (source, destination) in mappings where manager.fileExists(atPath: source.path) {
            let children = try manager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            for child in children {
                let target = destination.appending(path: child.lastPathComponent, directoryHint: .inferFromPath)
                guard !manager.fileExists(atPath: target.path) else { continue }
                try manager.copyItem(at: child, to: target)
            }
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
