import Foundation
import Testing
@testable import HanlinSwiftUIBridgeCore

@Suite("Hanlin SwiftUI bridge generator")
struct HanlinSwiftUIBridgeCoreTests {
    private func fixture(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
    }

    @Test("SwiftSyntax parser captures views, modifiers, overloads, bindings, and lifecycle APIs")
    func parserAndClassifier() throws {
        let configuration = try JSONDecoder().decode(
            HanlinSwiftUIBridgeConfiguration.self,
            from: Data(contentsOf: fixture("configuration.json"))
        )
        let inventory = try HanlinSwiftUIOutputGenerator.buildInventory(
            inputs: [
                .init(module: "SwiftUICore", url: fixture("SwiftUICore.swiftinterface")),
                .init(module: "SwiftUI", url: fixture("SwiftUI.swiftinterface")),
            ],
            sdkIdentity: "fixture-ios26",
            configuration: configuration
        )
        let byName = Dictionary(grouping: inventory.declarations, by: \.symbol)
        #expect(byName["NavigationStack"]?.first?.status == .expoUpstream)
        #expect(byName["TextEditor"]?.first?.tier == .t3Binding)
        #expect(byName["TextEditor"]?.first?.status == .manual)
        #expect(byName["LazyVGrid"]?.first?.status == .manual)
        #expect(byName["LazyHGrid"]?.first?.status == .manual)
        #expect(byName["WindowGroup"]?.first?.status == .hostLifecycleOnly)
        #expect(byName["navigationBarTitleDisplayMode"]?.first?.status == .generated)
        #expect(byName["Group"]?.first?.tier == .t2Content)
        #expect(byName["Group"]?.first?.status == .generated)
        #expect(byName["EditButton"]?.first?.status == .generated)
        #expect(byName["EmptyView"]?.first?.status == .generated)
        #expect(byName["AsyncImage"]?.first?.status == .needsInvestigation)
        #expect(byName["searchable"]?.first?.tier == .t3Binding)
        #expect(byName["searchable"]?.first?.status == .needsInvestigation)
        #expect(byName["environmentObject"]?.first?.status == .unsupported)
        #expect(byName["onPreferenceChange"]?.first?.status == .unsupported)
        #expect(byName["lineLimit"]?.first?.signatures.count == 2)
    }

    @Test("Generation is deterministic and Swift/TypeScript symbols stay consistent")
    func deterministicOutput() throws {
        let configuration = try JSONDecoder().decode(
            HanlinSwiftUIBridgeConfiguration.self,
            from: Data(contentsOf: fixture("configuration.json"))
        )
        let inventory = try HanlinSwiftUIOutputGenerator.buildInventory(
            inputs: [
                .init(module: "SwiftUICore", url: fixture("SwiftUICore.swiftinterface")),
                .init(module: "SwiftUI", url: fixture("SwiftUI.swiftinterface")),
            ],
            sdkIdentity: "fixture-ios26",
            configuration: configuration
        )
        let first = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let second = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        try HanlinSwiftUIOutputGenerator.write(inventory: inventory, configuration: configuration, outputRoot: first)
        try HanlinSwiftUIOutputGenerator.write(inventory: inventory, configuration: configuration, outputRoot: second)
        for name in ["swiftui-inventory.json", "coverage.json", "coverage.md", "HanlinGeneratedModifiers.swift", "HanlinGeneratedViews.swift", "modifiers.ts", "views.tsx", "bridge-manifest.ts"] {
            #expect(FileManager.default.contentsEqual(atPath: first.appending(path: name).path, andPath: second.appending(path: name).path))
        }
        let swift = try String(contentsOf: first.appending(path: "HanlinGeneratedModifiers.swift"), encoding: .utf8)
        let typeScript = try String(contentsOf: first.appending(path: "modifiers.ts"), encoding: .utf8)
        let swiftViews = try String(contentsOf: first.appending(path: "HanlinGeneratedViews.swift"), encoding: .utf8)
        let typeScriptViews = try String(contentsOf: first.appending(path: "views.tsx"), encoding: .utf8)
        #expect(swift.contains("navigationBarTitleDisplayMode"))
        #expect(typeScript.contains("navigationBarTitleDisplayMode"))
        #expect(swiftViews.contains("HanlinGeneratedGroupView"))
        #expect(typeScriptViews.contains("export function Group"))
    }

    @Test("Manifest keeps same-named declarations module-qualified")
    func namingCollisions() throws {
        let configuration = try JSONDecoder().decode(
            HanlinSwiftUIBridgeConfiguration.self,
            from: Data(contentsOf: fixture("configuration.json"))
        )
        let inventory = HanlinSwiftUIInventory(
            generatorVersion: HanlinSwiftUIOutputGenerator.version,
            sdkIdentity: "collision-fixture",
            interfaces: [],
            declarations: [
                .init(module: "SwiftUI", symbol: "SharedView", kind: .view, sourceModule: "SwiftUI", status: .expoUpstream),
                .init(module: "SwiftUICore", symbol: "SharedView", kind: .view, sourceModule: "SwiftUICore", status: .expoUpstream),
            ]
        )
        let output = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: output) }
        try HanlinSwiftUIOutputGenerator.write(inventory: inventory, configuration: configuration, outputRoot: output)
        let manifest = try String(contentsOf: output.appending(path: "bridge-manifest.ts"), encoding: .utf8)
        #expect(manifest.contains("'SwiftUI.SharedView': 'expo-upstream'"))
        #expect(manifest.contains("'SwiftUICore.SharedView': 'expo-upstream'"))
        #expect(manifest.components(separatedBy: "  'SharedView',").count == 2)
    }
}
