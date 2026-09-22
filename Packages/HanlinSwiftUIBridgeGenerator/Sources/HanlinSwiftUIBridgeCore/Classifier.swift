import Foundation

public enum HanlinSwiftUIClassifier {
    public static func classify(
        declarations: [HanlinSwiftUIDeclaration],
        configuration: HanlinSwiftUIBridgeConfiguration
    ) -> [HanlinSwiftUIDeclaration] {
        let expoViews = Set(configuration.expoViews)
        let expoModifiers = Set(configuration.expoModifiers)
        let reviewedExpoViews = Set(configuration.expoReviewedViews)
        let reviewedExpoModifiers = Set(configuration.expoReviewedModifiers)
        let enums = Dictionary(uniqueKeysWithValues: declarations
            .filter { !$0.enumCases.isEmpty || !$0.optionSetCases.isEmpty }
            .map { ($0.symbol, $0.enumCases + $0.optionSetCases) })

        return declarations.map { declaration in
            var item = declaration
            let shortName = item.symbol.split(separator: ".").last.map(String.init) ?? item.symbol
            item.expoSymbolExists = (item.kind == .view && expoViews.contains(shortName))
                || (item.kind == .modifier && expoModifiers.contains(shortName))
            let expoSurfaceReviewed = (item.kind == .view && reviewedExpoViews.contains(shortName))
                || (item.kind == .modifier && reviewedExpoModifiers.contains(shortName))
            if item.kind == .view || item.kind == .modifier {
                item.tier = tier(for: item)
            }

            if let rule = configuration.rules[item.symbol] ?? configuration.rules[shortName] {
                apply(rule: rule, to: &item, enums: enums)
                return item
            }
            guard item.kind == .view || item.kind == .modifier else { return item }
            if item.isDeprecated || item.isUnavailable {
                item.status = .unsupported
                item.reason = item.isDeprecated
                    ? "The current SDK marks this declaration deprecated; it is not emitted as a new bridge API."
                    : "The current SDK marks this declaration unavailable."
                item.signatures = item.signatures.map {
                    covered($0, status: .unsupported, reason: item.reason!, strategy: item.isDeprecated ? "deprecated-sdk-api" : "unavailable-sdk-api")
                }
                item.aggregateStatus = .unsupported
                return item
            }
            if item.expoSymbolExists {
                item.status = .expoUpstream
                if expoSurfaceReviewed {
                    item.signatures = item.signatures.map { signature in
                        classifyReviewedExpoSignature(
                            signature,
                            declaration: item,
                            enums: enums,
                            surface: "@expo/ui/\(shortName)"
                        )
                    }
                    item.aggregateStatus = aggregate(for: item.signatures)
                    item.expoParity = item.aggregateStatus == .full ? .verified : .partial
                    item.reason = item.aggregateStatus == .full
                        ? "The installed Expo TypeScript/native surface was reviewed and covers every discovered semantic signature."
                        : "The installed Expo surface was reviewed; matched semantic signatures are covered and unmatched Apple overloads remain explicit."
                } else {
                    item.expoParity = .unknown
                    item.reason = "@expo/ui \(configuration.expoUIVersion) exports this symbol, but Apple overload parity has not been verified."
                    item.signatures = item.signatures.map {
                        covered(
                            $0,
                            status: .needsInvestigation,
                            reason: "Expo exports the symbol, but this Apple signature has not been matched to the Expo TypeScript/native surface.",
                            strategy: "expo-parity-unknown",
                            surface: "@expo/ui/\(shortName)"
                        )
                    }
                    item.aggregateStatus = .partial
                }
                return item
            }
            if item.sourceModule != "SwiftUI" && item.sourceModule != "SwiftUICore" {
                item.status = .companionFramework
                item.reason = "Inventoried separately from core SwiftUI."
                item.signatures = item.signatures.map {
                    covered($0, status: .needsInvestigation, reason: item.reason!, strategy: "companion-framework")
                }
                item.aggregateStatus = .needsInvestigation
                return item
            }

            item.signatures = classifySignatures(item, enums: enums)
            item.aggregateStatus = aggregate(for: item.signatures)
            let statuses = item.signatures.compactMap(\.status)
            if statuses.contains(where: \.isCovered) {
                item.status = .generated
                item.reason = item.aggregateStatus == .full
                    ? "All discovered signatures map to generated or shared typed bridge surfaces."
                    : "At least one signature is covered, but unresolved overloads remain visible below."
            } else if !statuses.isEmpty && statuses.allSatisfy({ $0 == .unsupported }) {
                item.status = .unsupported
                item.reason = "Every discovered signature uses semantics that cannot be bridged safely."
            } else {
                item.status = .needsInvestigation
                item.reason = item.signatures.isEmpty
                    ? "No public initializer or modifier signature was discovered in the selected interface."
                    : "No discovered signature currently has a safe generated or shared bridge surface."
            }
            return item
        }
    }

    private static func apply(
        rule: HanlinSwiftUIManualRule,
        to item: inout HanlinSwiftUIDeclaration,
        enums: [String: [String]]
    ) {
        item.status = rule.status
        item.reason = rule.reason
        item.manualAdapter = rule.adapter
        switch rule.status {
        case .manual:
            item.signatures = item.signatures.map {
                covered(
                    $0,
                    status: .coveredByManualAdapter,
                    reason: rule.reason,
                    strategy: $0.parameters.contains(where: \.isBinding) ? "controlled-binding-adapter" : "manual-semantic-adapter",
                    surface: rule.adapter
                )
            }
            item.aggregateStatus = .full
        case .hostLifecycleOnly:
            item.signatures = item.signatures.map {
                covered($0, status: .hostLifecycle, reason: rule.reason, strategy: "host-lifecycle")
            }
            item.aggregateStatus = .lifecycleOnly
        case .unsupported:
            item.signatures = item.signatures.map {
                covered($0, status: .unsupported, reason: rule.reason, strategy: "unsupported-semantic-family")
            }
            item.aggregateStatus = .unsupported
        case .expoUpstream:
            item.expoSymbolExists = true
            item.expoParity = .partial
            item.signatures = item.signatures.map { signature in
                if isGeneratable(signature, declaration: item, enums: enums) || hasSupportedBinding(signature, enums: enums) {
                    return covered(
                        signature,
                        status: .expoUpstream,
                        reason: rule.reason,
                        strategy: hasSupportedBinding(signature, enums: enums) ? "controlled-binding-adapter" : "expo-reviewed-surface",
                        surface: "@expo/ui"
                    )
                }
                return covered(
                    signature,
                    status: .needsInvestigation,
                    reason: "The reviewed Expo symbol exists, but this generic Apple overload is not proven equivalent.",
                    strategy: "expo-overload-parity-unverified",
                    surface: "@expo/ui"
                )
            }
            item.aggregateStatus = aggregate(for: item.signatures)
        case .generated, .companionFramework, .needsInvestigation:
            item.signatures = classifySignatures(item, enums: enums)
            item.aggregateStatus = aggregate(for: item.signatures)
        }
    }

    private static func classifySignatures(
        _ declaration: HanlinSwiftUIDeclaration,
        enums: [String: [String]]
    ) -> [HanlinSwiftUISignature] {
        var semanticSurfaces: [String: String] = [:]
        return declaration.signatures.enumerated().map { index, signature in
            let surface = semanticKey(signature)
            if let existing = semanticSurfaces[surface] {
                return covered(
                    signature,
                    status: .redundantOverload,
                    reason: "This Swift-language convenience overload collapses into the same typed React surface as \(existing).",
                    strategy: "semantic-overload-collapse",
                    surface: existing
                )
            }
            if signature.isAsync || signature.isThrowing {
                return covered(
                    signature,
                    status: .needsInvestigation,
                    reason: "Async or throwing semantics require an explicit asynchronous event/error bridge.",
                    strategy: "async-event-callback"
                )
            }
            if signature.parameters.contains(where: \.isBinding) {
                let supported = hasSupportedBinding(signature, enums: enums)
                return covered(
                    signature,
                    status: supported ? .needsInvestigation : .unsupported,
                    reason: supported
                        ? "A controlled/uncontrolled React binding template is available for the value family, but this symbol still needs a native semantic adapter."
                        : "The binding value is generic or non-serializable and cannot use the shared controlled binding template.",
                    strategy: supported ? "controlled-binding-template" : "non-serializable-binding"
                )
            }
            let nonBuilderClosures = signature.parameters.filter { $0.isClosure && !$0.isViewBuilder }
            if !nonBuilderClosures.isEmpty {
                let events = nonBuilderClosures.allSatisfy(isEventCallback)
                return covered(
                    signature,
                    status: events ? .needsInvestigation : .unsupported,
                    reason: events
                        ? "The closure is an event callback shape, but this symbol still needs event payload and lifecycle mapping."
                        : "The closure carries arbitrary generic or return-value semantics and is not serializable.",
                    strategy: events ? "event-callback-template" : "non-bridgeable-generic-closure"
                )
            }
            if isGeneratable(signature, declaration: declaration, enums: enums) {
                let slots = signature.parameters.filter(\.isViewBuilder).map(\.localName)
                let strategy = slots.count > 1 ? "multi-slot-view-builder" : (slots.isEmpty ? "mechanical-value" : "single-slot-view-builder")
                let reactSurface = "\(declaration.symbol)#\(index)"
                semanticSurfaces[surface] = reactSurface
                return covered(
                    signature,
                    status: .directGenerated,
                    reason: slots.count > 1
                        ? "Serializable values and named ViewBuilder slots map to a generated typed React component."
                        : "The signature uses mechanically serializable values and supported content slots.",
                    strategy: strategy,
                    surface: reactSurface
                )
            }
            let unsupported = signature.parameters.contains { isDefinitelyUnsupported($0.type, generics: declaration.genericParameters + signature.genericParameters) }
            return covered(
                signature,
                status: unsupported ? .unsupported : .needsInvestigation,
                reason: unsupported
                    ? "The signature depends on arbitrary generic, key-path, protocol, or associated-type semantics."
                    : "At least one value type has no safe typed React serialization rule yet.",
                strategy: unsupported ? "non-serializable-generic-semantics" : "missing-value-serialization"
            )
        }
    }

    private static func covered(
        _ signature: HanlinSwiftUISignature,
        status: HanlinSwiftUISignatureStatus,
        reason: String,
        strategy: String,
        surface: String? = nil
    ) -> HanlinSwiftUISignature {
        var result = signature
        result.status = status
        result.reason = reason
        result.bridgeStrategy = strategy
        result.sharedSurface = surface
        return result
    }

    private static func aggregate(for signatures: [HanlinSwiftUISignature]) -> HanlinSwiftUIAggregateStatus {
        guard !signatures.isEmpty else { return .needsInvestigation }
        let statuses = signatures.compactMap(\.status)
        if statuses.allSatisfy({ $0 == .hostLifecycle }) { return .lifecycleOnly }
        if statuses.allSatisfy({ $0 == .unsupported }) { return .unsupported }
        let coveredCount = statuses.count(where: \.isCovered)
        if coveredCount == statuses.count { return .full }
        if coveredCount > 0 { return .partial }
        return statuses.contains(.needsInvestigation) ? .needsInvestigation : .unsupported
    }

    private static func tier(for declaration: HanlinSwiftUIDeclaration) -> HanlinSwiftUIBridgeTier {
        let parameters = declaration.signatures.flatMap(\.parameters)
        if parameters.contains(where: \.isBinding) { return .t3Binding }
        if parameters.contains(where: { $0.isClosure && !$0.isViewBuilder }) { return .t4Semantic }
        if parameters.contains(where: \.isViewBuilder) { return .t2Content }
        return .t1Mechanical
    }

    private static func isGeneratable(
        _ signature: HanlinSwiftUISignature,
        declaration: HanlinSwiftUIDeclaration,
        enums: [String: [String]]
    ) -> Bool {
        switch declaration.kind {
        case .view:
            isGeneratableViewSignature(signature, symbol: declaration.symbol, generics: declaration.genericParameters, enums: enums)
        case .modifier:
            isGeneratableModifierSignature(signature, enums: enums)
        default:
            false
        }
    }

    private static func normalizedType(_ type: String) -> String {
        var result = type.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Swift.", "SwiftUICore.", "SwiftUI.", "CoreFoundation.", "CoreGraphics."] {
            result = result.replacingOccurrences(of: prefix, with: "")
        }
        if result.hasPrefix("Optional<"), result.hasSuffix(">") {
            result = String(result.dropFirst("Optional<".count).dropLast()) + "?"
        }
        return result
    }

    private static func isSerializable(_ type: String, enums: [String: [String]]) -> Bool {
        var normalized = normalizedType(type)
        if normalized.hasSuffix("?") {
            normalized.removeLast()
            return isSerializable(normalized, enums: enums)
        }
        let primitives: Set<String> = [
            "Bool", "Int", "Int8", "Int16", "Int32", "Int64",
            "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
            "Double", "Float", "CGFloat", "String",
        ]
        if primitives.contains(normalized) { return true }
        let structuralValues: Set<String> = [
            "UnitPoint", "EdgeInsets", "CGPoint", "CGSize", "Angle", "LocalizedStringKey", "Text",
        ]
        if structuralValues.contains(normalized) { return true }
        if normalized.hasPrefix("[") && normalized.hasSuffix("]") {
            return isPrimitiveCollectionElement(String(normalized.dropFirst().dropLast()))
        }
        if normalized.hasPrefix("Array<") && normalized.hasSuffix(">") {
            return isPrimitiveCollectionElement(String(normalized.dropFirst("Array<".count).dropLast()))
        }
        if enums[normalized] != nil || enums.keys.contains(where: { normalized.hasSuffix($0) || $0.hasSuffix(normalized) }) {
            return true
        }
        return false
    }

    private static func isPrimitiveCollectionElement(_ type: String) -> Bool {
        let normalized = normalizedType(type)
        return [
            "Bool", "Int", "Int8", "Int16", "Int32", "Int64",
            "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
            "Double", "Float", "CGFloat", "String",
        ].contains(normalized)
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
        let firstBuilderIndex = signature.parameters.firstIndex(where: \.isViewBuilder)
        guard firstBuilderIndex.map({ signature.parameters[$0...].allSatisfy(\.isViewBuilder) }) ?? true,
              builders.allSatisfy(isViewBuilderClosure),
              signature.parameters.allSatisfy({ parameter in
                  parameter.isViewBuilder || (!parameter.isBinding && !parameter.isClosure && isSerializable(parameter.type, enums: enums))
              }) else { return false }
        if generics.isEmpty { return true }
        guard !builders.isEmpty else { return false }
        let builderTypes = builders.map(\.type).joined(separator: " ")
        return generics.allSatisfy { builderTypes.contains($0) }
    }

    private static func isViewBuilderClosure(_ parameter: HanlinSwiftUIParameter) -> Bool {
        guard parameter.isViewBuilder else { return false }
        let type = parameter.type
            .replacingOccurrences(of: "@escaping", with: "")
            .replacingOccurrences(of: "@Sendable", with: "")
            .replacingOccurrences(of: " ", with: "")
        return type.hasPrefix("()->")
    }

    private static func bindingValue(_ type: String) -> String? {
        let normalized = normalizedType(type).replacingOccurrences(of: " ", with: "")
        guard let start = normalized.range(of: "Binding<"), normalized.hasSuffix(">") else { return nil }
        return String(normalized[start.upperBound..<normalized.index(before: normalized.endIndex)])
    }

    private static func hasSupportedBinding(_ signature: HanlinSwiftUISignature, enums: [String: [String]]) -> Bool {
        let bindings = signature.parameters.filter(\.isBinding)
        guard !bindings.isEmpty else { return false }
        let supported: Set<String> = ["String", "Bool", "Int", "Double", "Float", "CGFloat", "String?", "Int?", "Double?"]
        return bindings.allSatisfy { parameter in
            guard let value = bindingValue(parameter.type) else { return false }
            let normalized = normalizedType(value)
            return supported.contains(normalized)
                || enums.keys.contains(where: { normalized == $0 || normalized.hasSuffix($0) || $0.hasSuffix(normalized) })
        }
    }

    private static func classifyReviewedExpoSignature(
        _ signature: HanlinSwiftUISignature,
        declaration: HanlinSwiftUIDeclaration,
        enums: [String: [String]],
        surface: String
    ) -> HanlinSwiftUISignature {
        if signature.isAsync || signature.isThrowing {
            return covered(
                signature,
                status: .needsInvestigation,
                reason: "The reviewed Expo surface does not prove this async/throwing Apple overload.",
                strategy: "expo-async-parity-unverified",
                surface: surface
            )
        }
        let builders = signature.parameters.filter(\.isViewBuilder)
        let callbacks = signature.parameters.filter { $0.isClosure && !$0.isViewBuilder }
        let values = signature.parameters.filter { !$0.isClosure && !$0.isViewBuilder && !$0.isBinding }
        let buildersSupported = builders.allSatisfy(isViewBuilderClosure)
        let callbacksSupported = callbacks.allSatisfy(isEventCallback)
        let valuesSupported = values.allSatisfy {
            isExpoSemanticValue(
                $0.type,
                generics: declaration.genericParameters + signature.genericParameters,
                enums: enums
            )
        }
        let bindingsSupported = hasSupportedBinding(signature, enums: enums)
            || !signature.parameters.contains(where: \.isBinding)
        guard buildersSupported, callbacksSupported, valuesSupported, bindingsSupported else {
            return covered(
                signature,
                status: .needsInvestigation,
                reason: "This Apple overload contains generic, closure, binding, or value semantics not matched by the reviewed Expo surface.",
                strategy: "expo-overload-parity-unverified",
                surface: surface
            )
        }
        let strategy: String
        if signature.parameters.contains(where: \.isBinding) {
            strategy = "controlled-binding-adapter"
        } else if builders.count > 1 {
            strategy = "multi-slot-view-builder"
        } else if !callbacks.isEmpty {
            strategy = "event-callback-template"
        } else {
            strategy = "expo-reviewed-semantic-surface"
        }
        return covered(
            signature,
            status: strategy == "expo-reviewed-semantic-surface" ? .expoUpstream : .coveredBySharedTSSurface,
            reason: "Matched to the reviewed installed Expo TypeScript/native semantic surface.",
            strategy: strategy,
            surface: surface
        )
    }

    private static func isExpoSemanticValue(
        _ type: String,
        generics: [String],
        enums: [String: [String]]
    ) -> Bool {
        if isSerializable(type, enums: enums) { return true }
        let normalized = normalizedType(type)
        if isDefinitelyUnsupported(normalized, generics: generics) { return false }
        let known: Set<String> = [
            "LocalizedStringKey", "Foundation.LocalizedStringResource", "LocalizedStringResource", "Text",
            "Color", "CGColor", "Date", "URL", "UnitPoint", "Alignment", "HorizontalAlignment",
            "VerticalAlignment", "Edge.Set", "Axis.Set", "EdgeInsets", "ClosedRange<Double>",
            "ClosedRange<Float>", "ClosedRange<CGFloat>", "ClosedRange<Int>",
        ]
        if known.contains(normalized) { return true }
        if normalized.hasPrefix("Set<"), normalized.hasSuffix(">") {
            return isSerializable(String(normalized.dropFirst("Set<".count).dropLast()), enums: enums)
        }
        return false
    }

    private static func isEventCallback(_ parameter: HanlinSwiftUIParameter) -> Bool {
        let normalized = normalizedType(parameter.type)
            .replacingOccurrences(of: "@escaping", with: "")
            .replacingOccurrences(of: "@Sendable", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard normalized.contains("->") else { return false }
        let returnType = normalized.split(separator: ">", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        return returnType == "Void" || returnType == "()"
    }

    private static func isDefinitelyUnsupported(_ type: String, generics: [String]) -> Bool {
        let normalized = normalizedType(type)
        if normalized.contains("KeyPath<") || normalized.contains(".Type") || normalized.hasPrefix("some ") { return true }
        if normalized.contains("any ") || normalized.contains("PreferenceKey") { return true }
        return generics.contains(where: { normalized == $0 || normalized.hasPrefix("\($0).") })
    }

    private static func semanticKey(_ signature: HanlinSwiftUISignature) -> String {
        signature.parameters.map { parameter in
            let role = parameter.isViewBuilder ? "slot" : (parameter.isBinding ? "binding" : (parameter.isClosure ? "callback" : "value"))
            var type = normalizedType(parameter.type)
            for stringType in ["LocalizedStringKey", "Foundation.LocalizedStringResource", "LocalizedStringResource", "Text", "some StringProtocol"] {
                type = type.replacingOccurrences(of: stringType, with: "String")
            }
            return "\(parameter.externalName ?? "_"):\(parameter.localName):\(role):\(type)"
        }.joined(separator: "|")
    }
}
