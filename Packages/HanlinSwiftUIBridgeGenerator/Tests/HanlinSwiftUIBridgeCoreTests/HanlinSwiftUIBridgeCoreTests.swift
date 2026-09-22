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
        #expect(byName["NavigationStack"]?.first?.aggregateStatus == .partial)
        #expect(byName["NavigationStack"]?.first?.expoParity == .unknown)
        #expect(byName["NavigationStack"]?.first?.signatures.first?.status == .needsInvestigation)
        #expect(byName["NavigationView"]?.first?.status == .superseded)
        #expect(byName["NavigationView"]?.first?.replacement == ["NavigationStack", "NavigationSplitView"])
        #expect(byName["NavigationView"]?.first?.exportedToHanlin == false)
        #expect(byName["_PrivateView"]?.first?.status == .internalPrivate)
        #expect(byName["_PrivateView"]?.first?.exportedToHanlin == false)
        #expect(byName["_AllowedView"]?.first?.status == .generated)
        #expect(byName["_AllowedView"]?.first?.exportedToHanlin == true)
        #expect(byName["TextEditor"]?.first?.tier == .t3Binding)
        #expect(byName["TextEditor"]?.first?.status == .manual)
        #expect(byName["TextEditor"]?.first?.signatures.first?.status == .coveredByManualAdapter)
        #expect(byName["LazyVGrid"]?.first?.status == .manual)
        #expect(byName["LazyHGrid"]?.first?.status == .manual)
        #expect(byName["WindowGroup"]?.first?.status == .hostLifecycleOnly)
        #expect(byName["App"]?.first?.status == .hostLifecycleOnly)
        #expect(byName["navigationBarTitleDisplayMode"]?.first?.status == .generated)
        #expect(byName["Group"]?.first?.tier == .t2Content)
        #expect(byName["Group"]?.first?.status == .generated)
        #expect(byName["Group"]?.first?.aggregateStatus == .full)
        #expect(byName["GroupBox"]?.first?.aggregateStatus == .full)
        #expect(byName["GroupBox"]?.first?.signatures.first?.bridgeStrategy == "multi-slot-view-builder")
        #expect(byName["PartialView"]?.first?.status == .generated)
        #expect(byName["PartialView"]?.first?.aggregateStatus == .partial)
        #expect(byName["PartialView"]?.first?.signatures.map(\.status).contains(.directGenerated) == true)
        #expect(byName["PartialView"]?.first?.signatures.map(\.status).contains(.unsupported) == true)
        #expect(byName["EditButton"]?.first?.status == .generated)
        #expect(byName["IOSUnavailableView"]?.first?.status == .unavailable)
        #expect(byName["DeprecatedView"]?.first?.status == .deprecated)
        #expect(byName["EmptyView"]?.first?.status == .generated)
        #expect(byName["AsyncImage"]?.first?.status == .needsInvestigation)
        #expect(byName["AsyncImage"]?.first?.signatures.count == 1)
        #expect(byName["searchable"]?.first?.tier == .t3Binding)
        #expect(byName["searchable"]?.first?.status == .needsInvestigation)
        #expect(byName["environmentObject"]?.first?.status == .unsupported)
        #expect(byName["onPreferenceChange"]?.first?.status == .unsupported)
        #expect(byName["lineLimit"]?.first?.signatures.count == 2)
        #expect(byName["testAxes"]?.first?.signatures.first?.status == .directGenerated)
        #expect(byName["conditionalModifier"]?.first?.signatures.count == 1)
        #expect(byName["ExtendedView"]?.first?.kind == .view)
        #expect(byName["ExtendedView"]?.first?.signatures.count == 1)
        #expect(byName["safeAreaInset"]?.first?.signatures.first?.parameters.last?.isViewBuilder == true)
        #expect(byName["_privateModifier"]?.first?.status == .internalPrivate)
        #expect(byName["mixedAvailability"]?.first?.status == .generated)
        #expect(byName["mixedAvailability"]?.first?.signatures.map(\.status).contains(.deprecated) == true)
        #expect(byName["mixedAvailability"]?.first?.signatures.map(\.status).contains(.directGenerated) == true)
        #expect(byName["Axis.Set"]?.first?.optionSetCases == ["horizontal", "vertical"])
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
        #expect(swift.contains("HanlinGeneratedAxisSetValue"))
        #expect(swift.contains("values.reduce(into: Axis.Set())"))
        #expect(typeScript.contains("axes?: ('horizontal' | 'vertical')[]"))
        #expect(typeScript.contains("optional: number | undefined, required: number"))
        #expect(swiftViews.contains("HanlinGeneratedGroupView"))
        #expect(typeScriptViews.contains("export function Group"))
        #expect(swiftViews.contains("HanlinGeneratedSlotView"))
        #expect(swiftViews.contains("namedSlot(\"content\")"))
        #expect(typeScriptViews.contains("label?: React.ReactNode"))
        #expect(swiftViews.contains("HanlinGenerated_AllowedViewView"))
        #expect(typeScriptViews.contains("export function _AllowedView"))
        #expect(!swiftViews.contains("HanlinGeneratedPrivateViewView"))
        #expect(!typeScriptViews.contains("export function NavigationView"))
        #expect(!typeScript.contains("_privateModifier"))
        let coverage = try JSONDecoder().decode(
            HanlinSwiftUICoverage.self,
            from: Data(contentsOf: first.appending(path: "coverage.json"))
        )
        #expect(coverage.signatureCounts["view.total", default: 0] > 0)
        #expect(coverage.signatureCounts["view.covered", default: 0] > 0)
        #expect(coverage.aggregateCounts["partial", default: 0] > 0)
        #expect(coverage.inventoryCounts["declarations.underscored", default: 0] >= 2)
        #expect(coverage.publicSurfaceCounts["internal-private", default: 0] >= 2)
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
                .init(module: "SwiftUI", symbol: "SharedView", kind: .view, sourceModule: "SwiftUI", status: .expoUpstream, exportedToHanlin: true),
                .init(module: "SwiftUICore", symbol: "SharedView", kind: .view, sourceModule: "SwiftUICore", status: .expoUpstream, exportedToHanlin: true),
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
