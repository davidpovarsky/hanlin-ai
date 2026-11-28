import Foundation

let root = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)
let output = URL(filePath: CommandLine.arguments[2], directoryHint: .isDirectory)
let decoder = JSONDecoder()
let inventory = try decoder.decode(HanlinSwiftUIInventory.self,
    from: Data(contentsOf: root.appending(path: "Generated/SwiftUIBridge/swiftui-inventory.json")))
let configuration = try decoder.decode(HanlinSwiftUIBridgeConfiguration.self,
    from: Data(contentsOf: root.appending(path: "Tools/SwiftUIBridge/configuration.json")))
try HanlinSwiftUIOutputGenerator.write(inventory: inventory, configuration: configuration, outputRoot: output)
let generated = try Data(contentsOf: output.appending(path: "views.tsx"))
for target in ["Generated/SwiftUIBridge/views.tsx", "Packages/HanlinExpoUI/src/generated/views.tsx"] {
    let checkedIn = try Data(contentsOf: root.appending(path: target))
    guard generated == checkedIn else {
        throw NSError(domain: "GroupBoxGeneratorParity", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Generated wrapper differs from " + target])
    }
    print("EXECUTED_PASS production generator output equals " + target)
}
print("Recorded inventory: " + inventory.sdkIdentity + "; declarations: " + String(inventory.declarations.count))
