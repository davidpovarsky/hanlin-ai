import Foundation
import HanlinSwiftUIBridgeCore

// Exercise the public module without @testable imports or substitute definitions.
do {
    let args = CommandLine.arguments
    let operation = args[1]
    let configuration = try JSONDecoder().decode(
        HanlinSwiftUIBridgeConfiguration.self,
        from: Data(contentsOf: URL(filePath: args[2]))
    )
    let first = try HanlinSwiftUIInterfaceParser.parse(
        .init(module: args[3], url: URL(filePath: args[4]))
    )
    let second = try HanlinSwiftUIInterfaceParser.parse(
        .init(module: args[5], url: URL(filePath: args[6]))
    )
    var declarations = first.declarations + second.declarations
    if operation == "classify" {
        // Previously classified public values must not retain an exported surface
        // when a later caller supplies an ambiguous input batch.
        let value = declarations.first { !$0.enumCases.isEmpty || !$0.optionSetCases.isEmpty }!
        declarations.append(.init(
            module: "SwiftUI", symbol: "probe", kind: .modifier, sourceModule: "SwiftUI",
            signatures: [.init(
                parameters: [.init(
                    externalName: nil, localName: "value", type: "\(value.module).\(value.symbol)",
                    defaultValue: nil, attributes: [], isBinding: false,
                    isViewBuilder: false, isClosure: false
                )],
                status: .directGenerated, publicSurface: .supported, exportedToHanlin: true
            )],
            status: .generated, aggregateStatus: .full,
            publicSurface: .supported, exportedToHanlin: true
        ))
        let classified = HanlinSwiftUIClassifier.classify(
            declarations: declarations, configuration: configuration
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        print(String(decoding: try encoder.encode(classified), as: UTF8.self))
    } else {
        let inventory = HanlinSwiftUIInventory(
            generatorVersion: HanlinSwiftUIOutputGenerator.version,
            sdkIdentity: "bridge-input-admission-public-client",
            interfaces: [first.identity, second.identity],
            declarations: declarations
        )
        try HanlinSwiftUIOutputGenerator.write(
            inventory: inventory, configuration: configuration, outputRoot: URL(filePath: args[7])
        )
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
