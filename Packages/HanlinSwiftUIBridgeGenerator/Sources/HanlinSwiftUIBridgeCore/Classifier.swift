import Foundation

public enum HanlinSwiftUIClassifier {
    public static func classify(
        declarations: [HanlinSwiftUIDeclaration],
        configuration: HanlinSwiftUIBridgeConfiguration
    ) -> [HanlinSwiftUIDeclaration] {
        let expoViews = Set(configuration.expoViews)
        let expoModifiers = Set(configuration.expoModifiers)
        let enums = Dictionary(uniqueKeysWithValues: declarations
            .filter { !$0.enumCases.isEmpty }
            .map { ($0.symbol, $0.enumCases) })

        return declarations.map { declaration in
            var item = declaration
            guard item.kind == .view || item.kind == .modifier else { return item }
            let shortName = item.symbol.split(separator: ".").last.map(String.init) ?? item.symbol
            if let rule = configuration.rules[item.symbol] ?? configuration.rules[shortName] {
                item.status = rule.status
                item.reason = rule.reason
                item.manualAdapter = rule.adapter
                item.tier = tier(for: item)
                return item
            }
            if item.isUnavailable {
                item.status = .unsupported
                item.reason = "The SDK marks this declaration unavailable."
                item.tier = .t4Semantic
                return item
            }
            if (item.kind == .view && expoViews.contains(shortName))
                || (item.kind == .modifier && expoModifiers.contains(shortName)) {
                item.status = .expoUpstream
                item.reason = "Provided by @expo/ui \(configuration.expoUIVersion)."
                item.tier = tier(for: item)
                return item
            }
            if item.sourceModule != "SwiftUI" && item.sourceModule != "SwiftUICore" {
                item.status = .companionFramework
                item.reason = "Inventoried separately from core SwiftUI."
                item.tier = tier(for: item)
                return item
            }
            item.tier = tier(for: item)
            let signatures = item.signatures
            if signatures.isEmpty {
                item.status = .needsInvestigation
                item.reason = "No public initializer or serializable modifier signature was discovered."
                return item
            }
            if signatures.contains(where: { $0.isAsync || $0.isThrowing }) {
                item.status = .needsInvestigation
                item.reason = "Async or throwing semantics require an explicit bridge policy."
                return item
            }
            if signatures.contains(where: { signature in signature.parameters.contains(where: { $0.isBinding }) }) {
                item.status = .needsInvestigation
                item.reason = "Binding state requires the reusable controlled/uncontrolled adapter template."
                return item
            }
            if signatures.contains(where: { signature in
                signature.parameters.contains(where: { $0.isClosure && !$0.isViewBuilder })
            }) {
                item.status = .needsInvestigation
                item.reason = "Non-ViewBuilder closures are not mechanically serializable."
                return item
            }
            let supported = signatures.contains { signature in
                switch item.kind {
                case .view:
                    isGeneratableViewSignature(signature, symbol: item.symbol, generics: item.genericParameters, enums: enums)
                case .modifier:
                    isGeneratableModifierSignature(signature, enums: enums)
                default:
                    false
                }
            }
            if supported {
                item.status = .generated
                item.reason = "At least one signature is representable by the mechanical primitive/content templates."
            } else {
                item.status = .needsInvestigation
                item.reason = "No initializer or modifier overload uses only currently serializable types."
            }
            return item
        }
    }

    private static func tier(for declaration: HanlinSwiftUIDeclaration) -> HanlinSwiftUIBridgeTier {
        let parameters = declaration.signatures.flatMap(\.parameters)
        if parameters.contains(where: \.isBinding) { return .t3Binding }
        if parameters.contains(where: { $0.isClosure && !$0.isViewBuilder }) { return .t4Semantic }
        if parameters.contains(where: \.isViewBuilder) { return .t2Content }
        return .t1Mechanical
    }

    private static func isSerializable(_ type: String, enums: [String: [String]]) -> Bool {
        let normalized = type
            .replacingOccurrences(of: "Swift.", with: "")
            .replacingOccurrences(of: "?", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let primitives: Set<String> = ["Bool", "Int", "Int32", "Int64", "Double", "Float", "CGFloat", "String"]
        if primitives.contains(normalized) { return true }
        if enums[normalized] != nil || enums.first(where: { normalized.hasSuffix($0.key) }) != nil { return true }
        return false
    }

    private static func isGeneratableModifierSignature(
        _ signature: HanlinSwiftUISignature,
        enums: [String: [String]]
    ) -> Bool {
        !signature.isAsync
            && !signature.isThrowing
            && signature.parameters.allSatisfy {
                !$0.isBinding && !$0.isClosure && !$0.isViewBuilder && isSerializable($0.type, enums: enums)
            }
    }

    private static func isGeneratableViewSignature(
        _ signature: HanlinSwiftUISignature,
        symbol: String,
        generics: [String],
        enums: [String: [String]]
    ) -> Bool {
        guard !signature.isAsync, !signature.isThrowing, !symbol.contains(".") else { return false }
        let builders = signature.parameters.filter(\.isViewBuilder)
        guard builders.count <= 1,
              builders.allSatisfy({ $0.type.replacingOccurrences(of: " ", with: "").hasPrefix("()->") }),
              builders.first == nil || signature.parameters.last?.isViewBuilder == true,
              signature.parameters.allSatisfy({ parameter in
                  parameter.isViewBuilder || (!parameter.isBinding && !parameter.isClosure && isSerializable(parameter.type, enums: enums))
              }) else { return false }

        if generics.isEmpty { return true }
        guard let builder = builders.first else { return false }
        return generics.allSatisfy { builder.type.contains($0) }
    }
}
