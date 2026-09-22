import Foundation
import HanlinSwiftUIBridgeCore

struct Arguments {
    var interfaces: [HanlinSwiftUIInterfaceInput] = []
    var sdkIdentity = "unknown"
    var configuration: URL?
    var output: URL?
    var swiftDestination: URL?
    var swiftViewsDestination: URL?
    var typeScriptDestination: URL?
    var check = false
}

func parseArguments() throws -> Arguments {
    var parsed = Arguments()
    var iterator = CommandLine.arguments.dropFirst().makeIterator()
    while let argument = iterator.next() {
        switch argument {
        case "--interface":
            guard let value = iterator.next(), let separator = value.firstIndex(of: "=") else {
                throw NSError(domain: "HanlinSwiftUIBridgeGenerator", code: 2, userInfo: [NSLocalizedDescriptionKey: "--interface expects Module=path"])
            }
            let module = String(value[..<separator])
            let path = String(value[value.index(after: separator)...])
            parsed.interfaces.append(.init(module: module, url: URL(filePath: path)))
        case "--sdk-identity": parsed.sdkIdentity = iterator.next() ?? "unknown"
        case "--configuration": parsed.configuration = iterator.next().map { URL(filePath: $0) }
        case "--output": parsed.output = iterator.next().map { URL(filePath: $0) }
        case "--swift-destination": parsed.swiftDestination = iterator.next().map { URL(filePath: $0) }
        case "--swift-views-destination": parsed.swiftViewsDestination = iterator.next().map { URL(filePath: $0) }
        case "--typescript-destination": parsed.typeScriptDestination = iterator.next().map { URL(filePath: $0) }
        case "--check": parsed.check = true
        default:
            throw NSError(domain: "HanlinSwiftUIBridgeGenerator", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown argument: \(argument)"])
        }
    }
    return parsed
}

do {
    let arguments = try parseArguments()
    guard !arguments.interfaces.isEmpty, let configurationURL = arguments.configuration, let outputURL = arguments.output else {
        throw NSError(domain: "HanlinSwiftUIBridgeGenerator", code: 2, userInfo: [NSLocalizedDescriptionKey: "Required: --interface Module=path --configuration path --output path"])
    }
    let decoder = JSONDecoder()
    let configuration = try decoder.decode(HanlinSwiftUIBridgeConfiguration.self, from: Data(contentsOf: configurationURL))
    let inventory = try HanlinSwiftUIOutputGenerator.buildInventory(
        inputs: arguments.interfaces,
        sdkIdentity: arguments.sdkIdentity,
        configuration: configuration
    )
    if arguments.check {
        let temporary = FileManager.default.temporaryDirectory.appending(path: "hanlin-swiftui-bridge-check-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try HanlinSwiftUIOutputGenerator.write(inventory: inventory, configuration: configuration, outputRoot: temporary)
        for name in ["swiftui-inventory.json", "coverage.json", "coverage.md", "HanlinGeneratedModifiers.swift", "HanlinGeneratedViews.swift", "modifiers.ts", "views.tsx", "bridge-manifest.ts"] {
            let expected = outputURL.appending(path: name)
            let generated = temporary.appending(path: name)
            guard FileManager.default.contentsEqual(atPath: expected.path, andPath: generated.path) else {
                throw NSError(domain: "HanlinSwiftUIBridgeGenerator", code: 3, userInfo: [NSLocalizedDescriptionKey: "Generated output is stale: \(name)"])
            }
        }
        if let destination = arguments.swiftDestination {
            guard FileManager.default.contentsEqual(
                atPath: destination.path,
                andPath: temporary.appending(path: "HanlinGeneratedModifiers.swift").path
            ) else {
                throw NSError(domain: "HanlinSwiftUIBridgeGenerator", code: 3, userInfo: [NSLocalizedDescriptionKey: "Generated Swift destination is stale"])
            }
        }
        if let destination = arguments.swiftViewsDestination {
            guard FileManager.default.contentsEqual(
                atPath: destination.path,
                andPath: temporary.appending(path: "HanlinGeneratedViews.swift").path
            ) else {
                throw NSError(domain: "HanlinSwiftUIBridgeGenerator", code: 3, userInfo: [NSLocalizedDescriptionKey: "Generated Swift views destination is stale"])
            }
        }
        if let destination = arguments.typeScriptDestination {
            for name in ["modifiers.ts", "views.tsx", "bridge-manifest.ts"] {
                guard FileManager.default.contentsEqual(
                    atPath: destination.appending(path: name).path,
                    andPath: temporary.appending(path: name).path
                ) else {
                    throw NSError(domain: "HanlinSwiftUIBridgeGenerator", code: 3, userInfo: [NSLocalizedDescriptionKey: "Generated TypeScript destination is stale: \(name)"])
                }
            }
        }
    } else {
        try HanlinSwiftUIOutputGenerator.write(inventory: inventory, configuration: configuration, outputRoot: outputURL)
        if let destination = arguments.swiftDestination {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: outputURL.appending(path: "HanlinGeneratedModifiers.swift"), to: destination)
        }
        if let destination = arguments.swiftViewsDestination {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: outputURL.appending(path: "HanlinGeneratedViews.swift"), to: destination)
        }
        if let destination = arguments.typeScriptDestination {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            for name in ["modifiers.ts", "views.tsx", "bridge-manifest.ts"] {
                let target = destination.appending(path: name)
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.copyItem(at: outputURL.appending(path: name), to: target)
            }
        }
    }
    print("Hanlin SwiftUI inventory: \(inventory.declarations.count) declarations")
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
