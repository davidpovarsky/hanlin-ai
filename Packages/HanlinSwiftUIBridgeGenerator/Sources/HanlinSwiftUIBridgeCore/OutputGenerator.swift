import Foundation

public enum HanlinSwiftUIOutputGenerator {
    public static let version = "3.0.0"

    public static func buildInventory(
        inputs: [HanlinSwiftUIInterfaceInput],
        sdkIdentity: String,
        sdkMetadata: HanlinSwiftUISDKMetadata? = nil,
        configuration: HanlinSwiftUIBridgeConfiguration
    ) throws -> HanlinSwiftUIInventory {
        var identities: [HanlinSwiftUIInterfaceIdentity] = []
        var declarations: [HanlinSwiftUIDeclaration] = []
        for input in inputs.sorted(by: { $0.module < $1.module }) {
            let parsed = try HanlinSwiftUIInterfaceParser.parse(input)
            identities.append(parsed.identity)
            declarations.append(contentsOf: parsed.declarations)
        }
        declarations = mergeOverloads(declarations)
        declarations = HanlinSwiftUIClassifier.classify(declarations: declarations, configuration: configuration)
        return .init(
            generatorVersion: version,
            sdkIdentity: sdkIdentity,
            sdkMetadata: sdkMetadata,
            interfaces: identities,
            declarations: declarations
        )
    }

    public static func write(
        inventory: HanlinSwiftUIInventory,
        configuration: HanlinSwiftUIBridgeConfiguration,
        outputRoot: URL
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: outputRoot, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try appendNewline(encoder.encode(inventory)).write(to: outputRoot.appending(path: "swiftui-inventory.json"))

        let relevant = inventory.declarations.filter { $0.status != nil }
        let counts = Dictionary(grouping: relevant, by: { $0.status?.rawValue ?? "unclassified" })
            .mapValues(\.count)
        let aggregateCounts = Dictionary(grouping: relevant, by: { $0.aggregateStatus?.rawValue ?? "unclassified" })
            .mapValues(\.count)
        let views = relevant.filter { $0.kind == .view }
        let modifiers = relevant.filter { $0.kind == .modifier }
        let kindCounts = [
            "views": views.count,
            "modifiers": modifiers.count,
            "expo-view-symbols": views.count(where: \.expoSymbolExists),
            "expo-modifier-symbols": modifiers.count(where: \.expoSymbolExists),
        ]
        let signatureCounts = makeSignatureCounts(views: views, modifiers: modifiers)
        let inventoryCounts = makeInventoryCounts(inventory.declarations)
        let publicSurfaceCounts = Dictionary(
            grouping: inventory.declarations.compactMap(\.publicSurface),
            by: \.rawValue
        ).mapValues(\.count).merging([
            "exported-symbols": inventory.declarations.count(where: \.exportedToHanlin),
            "sdk-only-symbols": inventory.declarations.count { !$0.exportedToHanlin },
        ]) { _, new in new }
        let coverage = HanlinSwiftUICoverage(
            sdkIdentity: inventory.sdkIdentity,
            sdkMetadata: inventory.sdkMetadata,
            generatorVersion: inventory.generatorVersion,
            bridgeVersion: configuration.bridgeVersion,
            expoUIVersion: configuration.expoUIVersion,
            interfaceHashes: Dictionary(uniqueKeysWithValues: inventory.interfaces.map { ($0.module, $0.sha256) }),
            counts: counts,
            aggregateCounts: aggregateCounts,
            kindCounts: kindCounts,
            signatureCounts: signatureCounts,
            inventoryCounts: inventoryCounts,
            publicSurfaceCounts: publicSurfaceCounts,
            symbols: relevant
        )
        try appendNewline(encoder.encode(coverage)).write(to: outputRoot.appending(path: "coverage.json"))
        try coverageMarkdown(coverage).write(to: outputRoot.appending(path: "coverage.md"), atomically: true, encoding: .utf8)
        try generatedSwift(inventory, configuration: configuration).write(
            to: outputRoot.appending(path: "HanlinGeneratedModifiers.swift"), atomically: true, encoding: .utf8
        )
        try generatedSwiftViews(inventory, configuration: configuration).write(
            to: outputRoot.appending(path: "HanlinGeneratedViews.swift"), atomically: true, encoding: .utf8
        )
        try generatedTypeScript(inventory).write(
            to: outputRoot.appending(path: "modifiers.ts"), atomically: true, encoding: .utf8
        )
        try generatedTypeScriptViews(inventory).write(
            to: outputRoot.appending(path: "views.tsx"), atomically: true, encoding: .utf8
        )
        try generatedManifest(inventory, configuration: configuration).write(
            to: outputRoot.appending(path: "bridge-manifest.ts"), atomically: true, encoding: .utf8
        )
    }

    private static func mergeOverloads(_ declarations: [HanlinSwiftUIDeclaration]) -> [HanlinSwiftUIDeclaration] {
        let declaredKinds = Dictionary(grouping: declarations, by: { "\($0.module)|\($0.symbol)" })
            .mapValues { candidates in
                candidates.contains(where: { $0.kind == .view }) ? HanlinSwiftUIDeclarationKind.view
                    : (candidates.contains(where: { $0.kind == .protocolDeclaration }) ? .protocolDeclaration : .type)
            }
        var merged: [String: HanlinSwiftUIDeclaration] = [:]
        for original in declarations {
            var declaration = original
            if declaration.kind != .modifier {
                declaration.kind = declaredKinds["\(declaration.module)|\(declaration.symbol)"] ?? declaration.kind
            }
            let key = "\(declaration.module)|\(declaration.kind.rawValue)|\(declaration.symbol)"
            if var existing = merged[key] {
                existing.signatures.append(contentsOf: declaration.signatures.filter { !existing.signatures.contains($0) })
                existing.availability = Array(Set(existing.availability + declaration.availability)).sorted()
                existing.attributes = Array(Set(existing.attributes + declaration.attributes)).sorted()
                existing.enumCases = Array(Set(existing.enumCases + declaration.enumCases)).sorted()
                existing.optionSetCases = Array(Set(existing.optionSetCases + declaration.optionSetCases)).sorted()
                existing.isDeprecated = existing.isDeprecated && declaration.isDeprecated
                existing.isUnavailable = existing.isUnavailable && declaration.isUnavailable
                if declaration.sdkVisibility != .public { existing.sdkVisibility = declaration.sdkVisibility }
                merged[key] = existing
            } else {
                merged[key] = declaration
            }
        }
        return merged.values.sorted { ($0.module, $0.symbol, $0.kind.rawValue) < ($1.module, $1.symbol, $1.kind.rawValue) }
    }

    private static func coverageMarkdown(_ coverage: HanlinSwiftUICoverage) -> String {
        var lines = [
            "<!-- Generated by hanlin-swiftui-bridge. Do not edit. -->",
            "# Hanlin SwiftUI bridge coverage",
            "",
            "- SDK/toolchain identity: `\(coverage.sdkIdentity)`",
            "- Generator: `\(coverage.generatorVersion)`",
            "- Bridge: `\(coverage.bridgeVersion)`",
            "- Expo UI: `\(coverage.expoUIVersion)`",
        ]
        if let metadata = coverage.sdkMetadata {
            lines.append("- Xcode: `\(metadata.xcodeVersion.replacingOccurrences(of: "\n", with: " / "))`")
            lines.append("- SDK: `\(metadata.sdk) \(metadata.sdkVersion)`")
            lines.append("- Target: `\(metadata.target)`")
            for (module, item) in metadata.modules.sorted(by: { $0.key < $1.key }) {
                lines.append("- \(module) interface: `\(item.sourceFile)` (`\(item.sha256)`)")
            }
        }
        lines.append(contentsOf: ["", "| Classification | Count |", "| --- | ---: |"])
        for status in HanlinSwiftUIBridgeStatus.allCases {
            lines.append("| \(status.rawValue) | \(coverage.counts[status.rawValue, default: 0]) |")
        }
        lines.append(contentsOf: ["", "## SDK inventory", "", "| Metric | Count |", "| --- | ---: |"])
        for key in coverage.inventoryCounts.keys.sorted() {
            lines.append("| \(key) | \(coverage.inventoryCounts[key, default: 0]) |")
        }
        lines.append(contentsOf: ["", "## Hanlin public surface", "", "| Classification | Count |", "| --- | ---: |"])
        for key in coverage.publicSurfaceCounts.keys.sorted() {
            lines.append("| \(key) | \(coverage.publicSurfaceCounts[key, default: 0]) |")
        }
        lines.append(contentsOf: ["", "## Derived aggregate status", "", "| Aggregate | Count |", "| --- | ---: |"])
        for status in HanlinSwiftUIAggregateStatus.allCases {
            lines.append("| \(status.rawValue) | \(coverage.aggregateCounts[status.rawValue, default: 0]) |")
        }
        lines.append(contentsOf: [
            "",
            "## Signature coverage",
            "",
            "| Metric | Count |",
            "| --- | ---: |",
            "| View symbols discovered | \(coverage.kindCounts["views", default: 0]) |",
            "| Expo view symbols present | \(coverage.kindCounts["expo-view-symbols", default: 0]) |",
            "| View initializers discovered | \(coverage.signatureCounts["view.total", default: 0]) |",
            "| View initializers covered | \(coverage.signatureCounts["view.covered", default: 0]) |",
            "| View initializers uncovered | \(coverage.signatureCounts["view.uncovered", default: 0]) |",
            "| Modifier symbols discovered | \(coverage.kindCounts["modifiers", default: 0]) |",
            "| Expo modifier symbols present | \(coverage.kindCounts["expo-modifier-symbols", default: 0]) |",
            "| Modifier overloads discovered | \(coverage.signatureCounts["modifier.total", default: 0]) |",
            "| Modifier overloads covered | \(coverage.signatureCounts["modifier.covered", default: 0]) |",
            "| Modifier overloads uncovered | \(coverage.signatureCounts["modifier.uncovered", default: 0]) |",
        ])
        lines.append(contentsOf: ["", "## Symbols", "", "| Module | Symbol | Kind | SDK visibility | Public surface | Exported | Tier | Source | Aggregate | Expo parity | Replacement | Reason |", "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"])
        for symbol in coverage.symbols {
            let reason = (symbol.reason ?? "").replacingOccurrences(of: "|", with: "\\|")
            let replacement = symbol.replacement.joined(separator: ", ")
            lines.append("| \(symbol.module) | `\(symbol.symbol)` | \(symbol.kind.rawValue) | \(symbol.sdkVisibility.rawValue) | \(symbol.publicSurface?.rawValue ?? "-") | \(symbol.exportedToHanlin ? "yes" : "no") | \(symbol.tier?.rawValue ?? "-") | \(symbol.status?.rawValue ?? "-") | \(symbol.aggregateStatus?.rawValue ?? "-") | \(symbol.expoParity?.rawValue ?? "-") | \(replacement) | \(reason) |")
        }
        lines.append(contentsOf: ["", "## Overloads", ""])
        for symbol in coverage.symbols where !symbol.signatures.isEmpty {
            lines.append("### \(symbol.module).\(symbol.symbol)")
            lines.append("")
            lines.append("Aggregate: `\(symbol.aggregateStatus?.rawValue ?? "-")`")
            lines.append("")
            for signature in symbol.signatures {
                let reason = (signature.reason ?? "Unclassified signature.").replacingOccurrences(of: "\n", with: " ")
                lines.append("- `\(signatureDescription(signature, kind: symbol.kind))` → **\(signature.status?.rawValue ?? "unclassified")** (`\(signature.bridgeStrategy ?? "none")`): \(reason)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }

    private static func makeSignatureCounts(
        views: [HanlinSwiftUIDeclaration],
        modifiers: [HanlinSwiftUIDeclaration]
    ) -> [String: Int] {
        var result: [String: Int] = [:]
        for (prefix, declarations) in [("view", views), ("modifier", modifiers)] {
            let signatures = declarations.flatMap(\.signatures)
            let publicSignatures = signatures.filter { signature in
                ![.internalPrivate, .deprecated, .superseded, .unavailable, .hostLifecycle].contains(signature.status)
            }
            result["\(prefix).total"] = signatures.count
            result["\(prefix).public-total"] = publicSignatures.count
            result["\(prefix).covered"] = publicSignatures.count { $0.status?.isCovered == true }
            result["\(prefix).uncovered"] = publicSignatures.count { $0.status?.isCovered != true }
            result["\(prefix).host-lifecycle"] = signatures.count { $0.status == .hostLifecycle }
            for status in HanlinSwiftUISignatureStatus.allCases {
                result["\(prefix).\(status.rawValue)"] = signatures.count { $0.status == status }
            }
        }
        return result
    }

    private static func makeInventoryCounts(
        _ declarations: [HanlinSwiftUIDeclaration]
    ) -> [String: Int] {
        var result = [
            "declarations.total": declarations.count,
            "declarations.public": declarations.count { $0.sdkVisibility == .public },
            "declarations.underscored": declarations.count { $0.sdkVisibility == .underscored },
            "declarations.spi": declarations.count { $0.sdkVisibility == .spi },
            "declarations.deprecated": declarations.count(where: \.isDeprecated),
            "declarations.unavailable": declarations.count(where: \.isUnavailable),
            "declarations.exported": declarations.count(where: \.exportedToHanlin),
        ]
        for kind in [
            HanlinSwiftUIDeclarationKind.view,
            .modifier,
            .type,
            .protocolDeclaration,
        ] {
            result["kind.\(kind.rawValue)"] = declarations.count { $0.kind == kind }
        }
        return result
    }

    private static func signatureDescription(
        _ signature: HanlinSwiftUISignature,
        kind: HanlinSwiftUIDeclarationKind
    ) -> String {
        let parameters = signature.parameters.map { parameter in
            "\(parameter.externalName.map { "\($0) " } ?? "")\(parameter.localName): \(parameter.type)"
        }.joined(separator: ", ")
        return "\(kind == .view ? "init" : "func")(\(parameters))"
    }

    private static func generatedSwift(
        _ inventory: HanlinSwiftUIInventory,
        configuration: HanlinSwiftUIBridgeConfiguration
    ) -> String {
        let modifiers = inventory.declarations.filter {
            $0.kind == .modifier && $0.status == .generated && $0.exportedToHanlin
                && !configuration.expoModifiers.contains($0.symbol)
        }
        var lines = [
            "// Generated by hanlin-swiftui-bridge \(version). Do not edit.",
            "import ExpoModulesCore",
            "import ExpoUI",
            "import SwiftUI",
            "",
        ]
        let enumDeclarations = Dictionary(uniqueKeysWithValues: inventory.declarations
            .filter { !$0.enumCases.isEmpty || !$0.optionSetCases.isEmpty }
            .map { ($0.symbol, $0) })
        let usedEnums = Set(modifiers.flatMap { modifier in
            selectedModifierSignature(modifier)?.parameters.compactMap { parameter in
                enumDeclaration(for: parameter.type, enums: enumDeclarations)?.symbol
            } ?? []
        })
        let usedStructures = Set(modifiers.flatMap { modifier in
            selectedModifierSignature(modifier)?.parameters.compactMap { structuralValueName($0.type) } ?? []
        })
        let usedOptionSets = Set(modifiers.flatMap { modifier in
            selectedModifierSignature(modifier)?.parameters.compactMap { parameter in
                optionSetDeclaration(for: parameter.type, declarations: enumDeclarations)?.symbol
            } ?? []
        })
        appendStructuralValueDeclarations(usedStructures, prefix: "HanlinGenerated", to: &lines)
        appendOptionSetDeclarations(usedOptionSets, declarations: enumDeclarations, prefix: "HanlinGenerated", to: &lines)
        for enumName in usedEnums.sorted() {
            guard let declaration = enumDeclarations[enumName] else { continue }
            let bridgeType = generatedEnumType(enumName)
            lines.append("public enum \(bridgeType): String, Enumerable {")
            for enumCase in declaration.enumCases.sorted() {
                lines.append("    case \(enumCase)")
            }
            lines.append("")
            lines.append("    var swiftUIValue: \(enumName) {")
            lines.append("        switch self {")
            for enumCase in declaration.enumCases.sorted() {
                lines.append("        case .\(enumCase): .\(enumCase)")
            }
            lines.append("        }")
            lines.append("    }")
            lines.append("}")
            lines.append("")
        }
        for modifier in modifiers {
            guard let signature = selectedModifierSignature(modifier) else { continue }
            let typeName = "HanlinGenerated\(upperCamel(modifier.symbol))Modifier"
            lines.append("public struct \(typeName): ViewModifier, Record {")
            for parameter in signature.parameters {
                lines.append("    @Field public var \(parameter.localName): \(fieldType(parameter, enums: enumDeclarations)) = \(fieldDefault(parameter, enums: enumDeclarations))")
            }
            lines.append("")
            lines.append("    public init() {}")
            lines.append("")
            lines.append("    public func body(content: Content) -> some View {")
            let arguments = signature.parameters.map { parameter in
                let value = nativeValue(parameter, enums: enumDeclarations)
                return parameter.externalName.map { "\($0): \(value)" } ?? value
            }.joined(separator: ", ")
            lines.append("        content.\(modifier.symbol)(\(arguments))")
            lines.append("    }")
            lines.append("}")
            lines.append("")
        }
        lines.append("public enum HanlinGeneratedModifierRegistry {")
        lines.append("    @MainActor public static func register() {")
        for modifier in modifiers {
            let typeName = "HanlinGenerated\(upperCamel(modifier.symbol))Modifier"
            lines.append("        ViewModifierRegistry.register(\"\(modifier.symbol)\") { params, appContext, _ in")
            lines.append("            try \(typeName)(from: params, appContext: appContext)")
            lines.append("        }")
        }
        lines.append("    }")
        lines.append("")
        lines.append("    public static func unregister() {")
        for modifier in modifiers {
            lines.append("        ViewModifierRegistry.unregister(\"\(modifier.symbol)\")")
        }
        lines.append("    }")
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func generatedTypeScript(_ inventory: HanlinSwiftUIInventory) -> String {
        let modifiers = inventory.declarations.filter {
            $0.kind == .modifier && $0.status == .generated && $0.exportedToHanlin
        }
        var lines = [
            "// Generated by hanlin-swiftui-bridge \(version). Do not edit.",
            "import { createModifier, type ModifierConfig } from '@expo/ui/swift-ui/modifiers';",
            "",
        ]
        for modifier in modifiers {
            guard let signature = selectedModifierSignature(modifier) else { continue }
            let parameters = signature.parameters.enumerated().map { index, parameter in
                let hasRequiredParameterAfter = signature.parameters[(index + 1)...]
                    .contains { $0.defaultValue == nil }
                let optional = parameter.defaultValue != nil && !hasRequiredParameterAfter ? "?" : ""
                let undefined = parameter.defaultValue != nil && hasRequiredParameterAfter ? " | undefined" : ""
                return "\(parameter.localName)\(optional): \(typescriptType(parameter.type, inventory: inventory))\(undefined)"
            }.joined(separator: ", ")
            let object = signature.parameters.map { "\($0.localName): \($0.localName)" }.joined(separator: ", ")
            lines.append("export const \(modifier.symbol) = (\(parameters)): ModifierConfig =>")
            lines.append("  createModifier('\(modifier.symbol)', { \(object) });")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func generatedSwiftViews(
        _ inventory: HanlinSwiftUIInventory,
        configuration: HanlinSwiftUIBridgeConfiguration
    ) -> String {
        let views = inventory.declarations.filter {
            $0.kind == .view && $0.status == .generated && $0.exportedToHanlin
        }
        let hasMultiSlotView = views.contains { view in
            (selectedViewSignature(view)?.parameters.count(where: \.isViewBuilder) ?? 0) > 1
        }
        let enumDeclarations = Dictionary(uniqueKeysWithValues: inventory.declarations
            .filter { !$0.enumCases.isEmpty || !$0.optionSetCases.isEmpty }
            .map { ($0.symbol, $0) })
        var lines = [
            "// Generated by hanlin-swiftui-bridge \(version). Do not edit.",
            "import ExpoModulesCore",
            "import ExpoUI",
            "import SwiftUI",
            "",
        ]
        if hasMultiSlotView {
            lines.append(contentsOf: [
                "public final class HanlinGeneratedSlotProps: UIBaseViewProps {",
                "    @Field public var name = \"\"",
                "}",
                "",
                "public struct HanlinGeneratedSlotView: ExpoSwiftUI.View {",
                "    @ObservedObject public var props: HanlinGeneratedSlotProps",
                "    public var body: some View { Children() }",
                "}",
                "",
            ])
        }
        let usedEnums = Set(views.flatMap { view in
            selectedViewSignature(view)?.parameters.compactMap { parameter in
                enumDeclaration(for: parameter.type, enums: enumDeclarations)?.symbol
            } ?? []
        })
        let usedStructures = Set(views.flatMap { view in
            selectedViewSignature(view)?.parameters.compactMap { structuralValueName($0.type) } ?? []
        })
        let usedOptionSets = Set(views.flatMap { view in
            selectedViewSignature(view)?.parameters.compactMap { parameter in
                optionSetDeclaration(for: parameter.type, declarations: enumDeclarations)?.symbol
            } ?? []
        })
        appendStructuralValueDeclarations(usedStructures, prefix: "HanlinGeneratedView", to: &lines)
        appendOptionSetDeclarations(usedOptionSets, declarations: enumDeclarations, prefix: "HanlinGeneratedView", to: &lines)
        for enumName in usedEnums.sorted() {
            guard let declaration = enumDeclarations[enumName] else { continue }
            let bridgeType = generatedViewEnumType(enumName)
            lines.append("public enum \(bridgeType): String, Enumerable {")
            for enumCase in declaration.enumCases.sorted() { lines.append("    case \(enumCase)") }
            lines.append("")
            lines.append("    var swiftUIValue: \(enumName) {")
            lines.append("        switch self {")
            for enumCase in declaration.enumCases.sorted() { lines.append("        case .\(enumCase): .\(enumCase)") }
            lines.append("        }")
            lines.append("    }")
            lines.append("}")
            lines.append("")
        }
        for view in views {
            guard let signature = selectedViewSignature(view) else { continue }
            let baseName = upperCamel(view.symbol)
            let propsName = "HanlinGenerated\(baseName)Props"
            let viewName = "HanlinGenerated\(baseName)View"
            let valueParameters = signature.parameters.filter { !$0.isViewBuilder }
            let builderParameters = signature.parameters.filter(\.isViewBuilder)
            lines.append("public final class \(propsName): UIBaseViewProps {")
            for parameter in valueParameters {
                lines.append("    @Field public var \(parameter.localName): \(viewFieldType(parameter, enums: enumDeclarations)) = \(viewFieldDefault(parameter, enums: enumDeclarations))")
            }
            lines.append("}")
            lines.append("")
            lines.append("public struct \(viewName): ExpoSwiftUI.View {")
            lines.append("    @ObservedObject public var props: \(propsName)")
            lines.append("")
            lines.append("    public var body: some View {")
            let arguments = valueParameters.map { parameter in
                let value = viewNativeValue(parameter, enums: enumDeclarations)
                return parameter.externalName.map { "\($0): \(value)" } ?? value
            }.joined(separator: ", ")
            if builderParameters.count == 1 {
                lines.append("        SwiftUI.\(view.symbol)(\(arguments)) {")
                lines.append("            Children()")
                lines.append("        }")
            } else if builderParameters.count > 1 {
                let first = builderParameters[0]
                lines.append("        SwiftUI.\(view.symbol)(\(arguments)) {")
                lines.append("            namedSlot(\"\(first.localName)\")")
                lines.append("        }" + builderParameters.dropFirst().map { parameter in
                    " \(parameter.externalName ?? parameter.localName): { namedSlot(\"\(parameter.localName)\") }"
                }.joined())
            } else {
                lines.append("        SwiftUI.\(view.symbol)(\(arguments))")
            }
            lines.append("    }")
            if builderParameters.count > 1 {
                lines.append("")
                lines.append("    @ViewBuilder private func namedSlot(_ name: String) -> some View {")
                lines.append("        if let slot = props.children?.compactMap({ $0.childView as? HanlinGeneratedSlotView }).first(where: { $0.props.name == name }) {")
                lines.append("            slot")
                lines.append("        }")
                lines.append("    }")
            }
            lines.append("}")
            lines.append("")
        }
        lines.append("public enum HanlinGeneratedBridgeMetadata {")
        lines.append("    public static let runtimeVersion = \"\(configuration.runtimeVersion)\"")
        lines.append("    public static let bridgeVersion = \"\(configuration.bridgeVersion)\"")
        lines.append("    public static let inventoryIdentity = \"\(inventory.sdkIdentity)\"")
        lines.append("}")
        lines.append("")
        lines.append("public final class HanlinGeneratedExpoUIModule: Module {")
        lines.append("    public func definition() -> ModuleDefinition {")
        lines.append("        Name(\"HanlinGeneratedExpoUI\")")
        if hasMultiSlotView { lines.append("        ExpoUIView(HanlinGeneratedSlotView.self)") }
        for view in views {
            lines.append("        ExpoUIView(HanlinGenerated\(upperCamel(view.symbol))View.self)")
        }
        lines.append("    }")
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func generatedTypeScriptViews(_ inventory: HanlinSwiftUIInventory) -> String {
        let views = inventory.declarations.filter {
            $0.kind == .view && $0.status == .generated && $0.exportedToHanlin
        }
        let hasMultiSlotView = views.contains { view in
            (selectedViewSignature(view)?.parameters.count(where: \.isViewBuilder) ?? 0) > 1
        }
        var lines = [
            "// Generated by hanlin-swiftui-bridge \(version). Do not edit.",
            "import React from 'react';",
            "import { requireNativeView } from 'expo';",
            "import type { CommonViewModifierProps } from '@expo/ui/swift-ui';",
            "import { createViewModifierEventListener } from '@expo/ui/swift-ui/modifiers';",
            "",
        ]
        if hasMultiSlotView {
            lines.append(contentsOf: [
                "interface HanlinGeneratedSlotProps { name: string; children?: React.ReactNode }",
                "const HanlinGeneratedSlot = requireNativeView<HanlinGeneratedSlotProps>('HanlinGeneratedExpoUI', 'HanlinGeneratedSlotView');",
                "",
            ])
        }
        for view in views {
            guard let signature = selectedViewSignature(view) else { continue }
            let name = upperCamel(view.symbol)
            let values = signature.parameters.filter { !$0.isViewBuilder }
            let builders = signature.parameters.filter(\.isViewBuilder)
            lines.append("export interface \(name)Props extends CommonViewModifierProps {")
            for parameter in values {
                let optional = parameter.defaultValue == nil ? "" : "?"
                lines.append("  \(parameter.localName)\(optional): \(typescriptType(parameter.type, inventory: inventory));")
            }
            if builders.count == 1 { lines.append("  children?: React.ReactNode;") }
            if builders.count > 1 {
                for builder in builders { lines.append("  \(builder.localName)?: React.ReactNode;") }
                lines.append("  children?: React.ReactNode;")
            }
            lines.append("}")
            lines.append("")
            lines.append("const Native\(name) = requireNativeView<\(name)Props>('HanlinGeneratedExpoUI', 'HanlinGenerated\(name)View');")
            lines.append("")
            let slotBindings = builders.count > 1 ? ", " + builders.map(\.localName).joined(separator: ", ") : ""
            lines.append("export function \(name)({ modifiers\(slotBindings), ...props }: \(name)Props) {")
            lines.append("  return (")
            lines.append("    <Native\(name)")
            lines.append("      {...props}")
            lines.append("      modifiers={modifiers}")
            lines.append("      {...(modifiers ? createViewModifierEventListener(modifiers) : undefined)}")
            if builders.count > 1 {
                lines.append("    >")
                for builder in builders {
                    lines.append("      {\(builder.localName) === undefined ? null : <HanlinGeneratedSlot name=\"\(builder.localName)\">{\(builder.localName)}</HanlinGeneratedSlot>}")
                }
                lines.append("    </Native\(name)>")
            } else {
                lines.append("    />")
            }
            lines.append("  );")
            lines.append("}")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func generatedManifest(
        _ inventory: HanlinSwiftUIInventory,
        configuration: HanlinSwiftUIBridgeConfiguration
    ) -> String {
        let relevant = inventory.declarations.filter { $0.kind == .view || $0.kind == .modifier }
        let symbols = Set(relevant
            .filter(\.exportedToHanlin)
            .map(\.symbol))
            .sorted()
            .map { "  '\($0)'," }
            .joined(separator: "\n")
        let classifications = relevant
            .map { "  '\($0.module).\($0.symbol)': '\($0.status?.rawValue ?? "unclassified")'," }
            .joined(separator: "\n")
        return """
        // Generated by hanlin-swiftui-bridge \(version). Do not edit.
        export const HANLIN_EXPO_RUNTIME_VERSION = '\(configuration.runtimeVersion)' as const;
        export const HANLIN_EXPO_UI_BRIDGE_VERSION = '\(configuration.bridgeVersion)' as const;
        export const HANLIN_SWIFTUI_SDK_IDENTITY = '\(inventory.sdkIdentity)' as const;
        export const HANLIN_SWIFTUI_SYMBOLS = [
        \(symbols)
        ] as const;
        export type HanlinSwiftUISymbol = (typeof HANLIN_SWIFTUI_SYMBOLS)[number];
        export const HANLIN_SWIFTUI_CLASSIFICATIONS = {
        \(classifications)
        } as const;
        """ + "\n"
    }

    private static func fieldType(
        _ parameter: HanlinSwiftUIParameter,
        enums: [String: HanlinSwiftUIDeclaration]
    ) -> String {
        let type = parameter.type
        if let declaration = optionSetDeclaration(for: type, declarations: enums) {
            let optional = isOptional(type) || parameter.defaultValue != nil ? "?" : ""
            return "[\(generatedEnumType(declaration.symbol))]\(optional)"
        }
        if let declaration = enumDeclaration(for: type, enums: enums) {
            return generatedEnumType(declaration.symbol) + (isOptional(type) ? "?" : "")
        }
        if let structural = structuralValueName(type) {
            let optional = isOptional(type) || parameter.defaultValue != nil ? "?" : ""
            if structural == "Angle" || structural == "LocalizedStringKey" || structural == "Text" {
                return (structural == "Angle" ? "Double" : "String") + optional
            }
            return "HanlinGenerated\(structural)Value" + optional
        }
        return normalizedSwiftType(type)
    }

    private static func fieldDefault(
        _ parameter: HanlinSwiftUIParameter,
        enums: [String: HanlinSwiftUIDeclaration]
    ) -> String {
        if optionSetDeclaration(for: parameter.type, declarations: enums) != nil {
            return parameter.defaultValue != nil || isOptional(parameter.type) ? "nil" : "[]"
        }
        if parameter.defaultValue == nil && parameter.type.trimmingCharacters(in: .whitespaces).hasSuffix("?") {
            return "nil"
        }
        if let structural = structuralValueName(parameter.type) {
            if parameter.defaultValue != nil || isOptional(parameter.type) { return "nil" }
            if structural == "Angle" { return "0" }
            if structural == "LocalizedStringKey" || structural == "Text" { return "\"\"" }
            return "HanlinGenerated\(structural)Value()"
        }
        if let declaration = enumDeclaration(for: parameter.type, enums: enums) {
            return parameter.defaultValue ?? declaration.enumCases.sorted().first.map { ".\($0)" } ?? ".automatic"
        }
        if let value = parameter.defaultValue { return value }
        let type = parameter.type.replacingOccurrences(of: "Swift.", with: "")
        if type.contains("Bool") { return "false" }
        if type.contains("String") { return "\"\"" }
        return "0"
    }

    private static func nativeValue(
        _ parameter: HanlinSwiftUIParameter,
        enums: [String: HanlinSwiftUIDeclaration]
    ) -> String {
        if let declaration = optionSetDeclaration(for: parameter.type, declarations: enums) {
            return optionSetNativeValue(parameter, declaration: declaration, reference: parameter.localName)
        }
        if let structural = structuralValueName(parameter.type) {
            return structuralNativeValue(structural, reference: parameter.localName, defaultValue: parameter.defaultValue)
        }
        guard enumDeclaration(for: parameter.type, enums: enums) != nil else { return parameter.localName }
        return parameter.type.trimmingCharacters(in: .whitespaces).hasSuffix("?")
            ? "\(parameter.localName)?.swiftUIValue"
            : "\(parameter.localName).swiftUIValue"
    }

    private static func typescriptType(_ type: String, inventory: HanlinSwiftUIInventory) -> String {
        let normalized = normalizedSwiftType(type).replacingOccurrences(of: "?", with: "")
        if ["Bool"].contains(normalized) { return "boolean" }
        if ["Int", "Int32", "Int64", "Double", "Float", "CGFloat"].contains(normalized) { return "number" }
        if normalized == "String" { return "string" }
        if let structural = structuralValueName(type) {
            switch structural {
            case "UnitPoint", "CGPoint": return "{ x: number; y: number }"
            case "EdgeInsets": return "{ top: number; leading: number; bottom: number; trailing: number }"
            case "CGSize": return "{ width: number; height: number }"
            case "Angle": return "number"
            case "LocalizedStringKey", "Text": return "string"
            default: break
            }
        }
        if let optionSet = inventory.declarations.first(where: {
            !$0.optionSetCases.isEmpty && typeMatches(type, symbol: $0.symbol)
        }) {
            let values = optionSet.optionSetCases.sorted().map { "'\($0)'" }.joined(separator: " | ")
            return "(\(values))[]"
        }
        if let enumDeclaration = inventory.declarations.first(where: {
            !$0.enumCases.isEmpty && ($0.symbol == normalized || normalized.hasSuffix($0.symbol))
        }) {
            return enumDeclaration.enumCases.map { "'\($0)'" }.joined(separator: " | ")
        }
        return "never"
    }

    private static func upperCamel(_ value: String) -> String {
        guard let first = value.first else { return value }
        return first.uppercased() + value.dropFirst()
    }

    private static func generatedEnumType(_ value: String) -> String {
        "HanlinGenerated" + value.split(separator: ".").map { upperCamel(String($0)) }.joined() + "Value"
    }

    private static func selectedViewSignature(_ declaration: HanlinSwiftUIDeclaration) -> HanlinSwiftUISignature? {
        declaration.signatures.first { $0.status == .directGenerated }
    }

    private static func selectedModifierSignature(_ declaration: HanlinSwiftUIDeclaration) -> HanlinSwiftUISignature? {
        declaration.signatures.first { signature in
            signature.status == .directGenerated && !signature.parameters.contains(where: \.isViewBuilder)
        }
    }

    private static func enumDeclaration(
        for type: String,
        enums: [String: HanlinSwiftUIDeclaration]
    ) -> HanlinSwiftUIDeclaration? {
        let normalized = type
            .replacingOccurrences(of: "Swift.", with: "")
            .replacingOccurrences(of: "?", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = enums[normalized], exact.optionSetCases.isEmpty { return exact }
        guard let key = enums.keys.sorted().first(where: { normalized.hasSuffix($0) && enums[$0]?.optionSetCases.isEmpty == true }) else { return nil }
        return enums[key]
    }

    private static func optionSetDeclaration(
        for type: String,
        declarations: [String: HanlinSwiftUIDeclaration]
    ) -> HanlinSwiftUIDeclaration? {
        let normalized = type
            .replacingOccurrences(of: "Swift.", with: "")
            .replacingOccurrences(of: "SwiftUICore.", with: "")
            .replacingOccurrences(of: "SwiftUI.", with: "")
            .replacingOccurrences(of: "?", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = declarations[normalized], !exact.optionSetCases.isEmpty { return exact }
        guard let key = declarations.keys.sorted().first(where: {
            normalized.hasSuffix($0) && declarations[$0]?.optionSetCases.isEmpty == false
        }) else { return nil }
        return declarations[key]
    }

    private static func typeMatches(_ type: String, symbol: String) -> Bool {
        let normalized = normalizedSwiftType(type)
            .replacingOccurrences(of: "?", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized == symbol || normalized.hasSuffix(symbol)
    }

    private static func viewFieldType(
        _ parameter: HanlinSwiftUIParameter,
        enums: [String: HanlinSwiftUIDeclaration]
    ) -> String {
        let type = parameter.type
        if let declaration = optionSetDeclaration(for: type, declarations: enums) {
            let optional = isOptional(type) || parameter.defaultValue != nil ? "?" : ""
            return "[\(generatedViewEnumType(declaration.symbol))]\(optional)"
        }
        guard let declaration = enumDeclaration(for: type, enums: enums) else {
            if let structural = structuralValueName(type) {
                let optional = isOptional(type) || parameter.defaultValue != nil ? "?" : ""
                if structural == "Angle" || structural == "LocalizedStringKey" || structural == "Text" {
                    return (structural == "Angle" ? "Double" : "String") + optional
                }
                return "HanlinGeneratedView\(structural)Value" + optional
            }
            return normalizedSwiftType(type)
        }
        let optional = type.trimmingCharacters(in: .whitespaces).hasSuffix("?") ? "?" : ""
        return generatedViewEnumType(declaration.symbol) + optional
    }

    private static func viewFieldDefault(
        _ parameter: HanlinSwiftUIParameter,
        enums: [String: HanlinSwiftUIDeclaration]
    ) -> String {
        if optionSetDeclaration(for: parameter.type, declarations: enums) != nil {
            return parameter.defaultValue != nil || isOptional(parameter.type) ? "nil" : "[]"
        }
        if parameter.defaultValue == nil && parameter.type.trimmingCharacters(in: .whitespaces).hasSuffix("?") {
            return "nil"
        }
        if let structural = structuralValueName(parameter.type) {
            if parameter.defaultValue != nil || isOptional(parameter.type) { return "nil" }
            if structural == "Angle" { return "0" }
            if structural == "LocalizedStringKey" || structural == "Text" { return "\"\"" }
            return "HanlinGeneratedView\(structural)Value()"
        }
        if let declaration = enumDeclaration(for: parameter.type, enums: enums) {
            return parameter.defaultValue ?? declaration.enumCases.sorted().first.map { ".\($0)" } ?? ".automatic"
        }
        return fieldDefault(parameter, enums: enums)
    }

    private static func viewNativeValue(
        _ parameter: HanlinSwiftUIParameter,
        enums: [String: HanlinSwiftUIDeclaration]
    ) -> String {
        if let declaration = optionSetDeclaration(for: parameter.type, declarations: enums) {
            return optionSetNativeValue(parameter, declaration: declaration, reference: "props.\(parameter.localName)")
        }
        if let structural = structuralValueName(parameter.type) {
            return structuralNativeValue(structural, reference: "props.\(parameter.localName)", defaultValue: parameter.defaultValue)
        }
        guard enumDeclaration(for: parameter.type, enums: enums) != nil else { return "props.\(parameter.localName)" }
        return parameter.type.trimmingCharacters(in: .whitespaces).hasSuffix("?")
            ? "props.\(parameter.localName)?.swiftUIValue"
            : "props.\(parameter.localName).swiftUIValue"
    }

    private static func generatedViewEnumType(_ value: String) -> String {
        "HanlinGeneratedView" + value.split(separator: ".").map { upperCamel(String($0)) }.joined() + "Value"
    }

    private static func normalizedSwiftType(_ type: String) -> String {
        var result = type
        for prefix in ["Swift.", "SwiftUICore.", "SwiftUI.", "CoreFoundation.", "CoreGraphics."] {
            result = result.replacingOccurrences(of: prefix, with: "")
        }
        return result
    }

    private static func isOptional(_ type: String) -> Bool {
        type.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?") || type.contains("Optional<")
    }

    private static func structuralValueName(_ type: String) -> String? {
        var normalized = normalizedSwiftType(type).trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasSuffix("?") { normalized.removeLast() }
        let supported: Set<String> = ["UnitPoint", "EdgeInsets", "CGPoint", "CGSize", "Angle", "LocalizedStringKey", "Text"]
        return supported.contains(normalized) ? normalized : nil
    }

    private static func structuralNativeValue(
        _ structural: String,
        reference: String,
        defaultValue: String?
    ) -> String {
        let converted: String
        let optionalConverted: String
        switch structural {
        case "Angle":
            converted = "SwiftUI.Angle.degrees(\(reference))"
            optionalConverted = "\(reference).map(SwiftUI.Angle.degrees)"
        case "LocalizedStringKey":
            converted = "SwiftUI.LocalizedStringKey(\(reference))"
            optionalConverted = "\(reference).map(SwiftUI.LocalizedStringKey.init)"
        case "Text":
            converted = "SwiftUI.Text(\(reference))"
            optionalConverted = "\(reference).map(SwiftUI.Text.init)"
        default:
            converted = "\(reference).swiftUIValue"
            optionalConverted = "\(reference)?.swiftUIValue"
        }
        guard let defaultValue else { return converted }
        return "\(optionalConverted) ?? \(defaultValue)"
    }

    private static func optionSetNativeValue(
        _ parameter: HanlinSwiftUIParameter,
        declaration: HanlinSwiftUIDeclaration,
        reference: String
    ) -> String {
        let type = declaration.symbol
        let reduce = "values.reduce(into: \(type)()) { result, value in result.formUnion(value.swiftUIValue) }"
        if let defaultValue = parameter.defaultValue {
            return "\(reference).map { values in \(reduce) } ?? \(defaultValue)"
        }
        if isOptional(parameter.type) {
            return "\(reference).map { values in \(reduce) }"
        }
        return "\(reference).reduce(into: \(type)()) { result, value in result.formUnion(value.swiftUIValue) }"
    }

    private static func appendOptionSetDeclarations(
        _ names: Set<String>,
        declarations: [String: HanlinSwiftUIDeclaration],
        prefix: String,
        to lines: inout [String]
    ) {
        for name in names.sorted() {
            guard let declaration = declarations[name] else { continue }
            let bridgeType = prefix + name.split(separator: ".").map { upperCamel(String($0)) }.joined() + "Value"
            lines.append("public enum \(bridgeType): String, Enumerable {")
            for option in declaration.optionSetCases.sorted() {
                lines.append("    case `\(option)`")
            }
            lines.append("")
            lines.append("    var swiftUIValue: \(name) {")
            lines.append("        switch self {")
            for option in declaration.optionSetCases.sorted() {
                lines.append("        case .`\(option)`: .\(option)")
            }
            lines.append("        }")
            lines.append("    }")
            lines.append("}")
            lines.append("")
        }
    }

    private static func appendStructuralValueDeclarations(
        _ names: Set<String>,
        prefix: String,
        to lines: inout [String]
    ) {
        for name in names.sorted() {
            switch name {
            case "UnitPoint":
                lines.append(contentsOf: structuralRecord(
                    name: "\(prefix)UnitPointValue",
                    fields: [("x", "CGFloat", "0.5"), ("y", "CGFloat", "0.5")],
                    nativeType: "SwiftUI.UnitPoint",
                    initializer: "SwiftUI.UnitPoint(x: x, y: y)"
                ))
            case "EdgeInsets":
                lines.append(contentsOf: structuralRecord(
                    name: "\(prefix)EdgeInsetsValue",
                    fields: [("top", "CGFloat", "0"), ("leading", "CGFloat", "0"), ("bottom", "CGFloat", "0"), ("trailing", "CGFloat", "0")],
                    nativeType: "SwiftUI.EdgeInsets",
                    initializer: "SwiftUI.EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing)"
                ))
            case "CGPoint":
                lines.append(contentsOf: structuralRecord(
                    name: "\(prefix)CGPointValue",
                    fields: [("x", "CGFloat", "0"), ("y", "CGFloat", "0")],
                    nativeType: "CGPoint",
                    initializer: "CGPoint(x: x, y: y)"
                ))
            case "CGSize":
                lines.append(contentsOf: structuralRecord(
                    name: "\(prefix)CGSizeValue",
                    fields: [("width", "CGFloat", "0"), ("height", "CGFloat", "0")],
                    nativeType: "CGSize",
                    initializer: "CGSize(width: width, height: height)"
                ))
            default:
                continue
            }
        }
    }

    private static func structuralRecord(
        name: String,
        fields: [(String, String, String)],
        nativeType: String,
        initializer: String
    ) -> [String] {
        var lines = ["public final class \(name): Record {"]
        for (field, type, defaultValue) in fields {
            lines.append("    @Field public var \(field): \(type) = \(defaultValue)")
        }
        lines.append("    public required init() {}")
        lines.append("    var swiftUIValue: \(nativeType) { \(initializer) }")
        lines.append("}")
        lines.append("")
        return lines
    }

    private static func appendNewline(_ data: Data) -> Data {
        var result = data
        result.append(0x0A)
        return result
    }
}
