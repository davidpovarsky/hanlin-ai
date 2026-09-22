import Foundation
import SwiftParser
import SwiftParserDiagnostics
import SwiftSyntax

public struct HanlinSwiftUIInterfaceInput: Sendable {
    public var module: String
    public var url: URL

    public init(module: String, url: URL) {
        self.module = module
        self.url = url
    }
}

public enum HanlinSwiftUIInterfaceParser {
    public static func parse(_ input: HanlinSwiftUIInterfaceInput) throws -> (
        identity: HanlinSwiftUIInterfaceIdentity,
        declarations: [HanlinSwiftUIDeclaration]
    ) {
        let data = try Data(contentsOf: input.url)
        guard let source = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        let syntax = Parser.parse(source: source)
        let diagnostics = ParseDiagnosticsGenerator.diagnostics(for: syntax)
        guard diagnostics.isEmpty else {
            let summary = diagnostics.prefix(10).map(\.message).joined(separator: "; ")
            throw NSError(
                domain: "HanlinSwiftUIBridgeGenerator",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Swift parser diagnostics in \(input.url.path): \(summary)"]
            )
        }
        let visitor = InventoryVisitor(module: input.module)
        visitor.walk(syntax)
        return (
            .init(module: input.module, fileName: input.url.lastPathComponent, sha256: SHA256.hexDigest(data)),
            visitor.declarations
        )
    }
}

private final class InventoryVisitor: SyntaxVisitor {
    let module: String
    var declarations: [HanlinSwiftUIDeclaration] = []
    private var typeScope: [String] = []
    private var viewExtensionAvailability: [[String]] = []
    private var typeExtensionDepths: [Int] = []
    private var typeExtensionAvailability: [[String]] = []

    init(module: String) {
        self.module = module
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        recordType(
            name: node.name.text,
            modifiers: node.modifiers,
            attributes: node.attributes,
            generics: node.genericParameterClause,
            inheritance: node.inheritanceClause,
            members: node.memberBlock.members,
            protocolKind: false
        )
        typeScope.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        typeScope.removeLast()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        recordType(
            name: node.name.text,
            modifiers: node.modifiers,
            attributes: node.attributes,
            generics: node.genericParameterClause,
            inheritance: node.inheritanceClause,
            members: node.memberBlock.members,
            protocolKind: false
        )
        typeScope.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        typeScope.removeLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        recordType(
            name: node.name.text,
            modifiers: node.modifiers,
            attributes: node.attributes,
            generics: node.genericParameterClause,
            inheritance: node.inheritanceClause,
            members: node.memberBlock.members,
            protocolKind: false
        )
        typeScope.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        typeScope.removeLast()
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        if isPublic(node.modifiers) {
            declarations.append(.init(
                module: module,
                symbol: qualified(node.name.text),
                kind: .protocolDeclaration,
                sourceModule: module,
                genericParameters: node.primaryAssociatedTypeClause?.primaryAssociatedTypes.map(\.name.text) ?? [],
                conformances: node.inheritanceClause?.inheritedTypes.map { $0.type.trimmedDescription } ?? [],
                availability: availability(node.attributes),
                attributes: attributeList(node.attributes),
                isDeprecated: isDeprecatedOnIOS(node.attributes),
                isUnavailable: isUnavailableOnIOS(node.attributes),
                sdkVisibility: sdkVisibility(symbol: qualified(node.name.text), attributes: node.attributes)
            ))
        }
        typeScope.append(node.name.text)
        return isPublic(node.modifiers) ? .visitChildren : .skipChildren
    }

    override func visitPost(_ node: ProtocolDeclSyntax) {
        typeScope.removeLast()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let extended = normalizedQualifiedName(node.extendedType.trimmedDescription)
        if extended == "View" || extended.hasSuffix(".View") {
            viewExtensionAvailability.append(availability(node.attributes))
            typeExtensionDepths.append(0)
            typeExtensionAvailability.append([])
            return .visitChildren
        }
        var components = extended.split(separator: ".").map(String.init)
        if components.first == module { components.removeFirst() }
        typeScope.append(contentsOf: components)
        typeExtensionDepths.append(components.count)
        typeExtensionAvailability.append(availability(node.attributes))
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        let extended = normalizedQualifiedName(node.extendedType.trimmedDescription)
        if extended == "View" || extended.hasSuffix(".View") {
            viewExtensionAvailability.removeLast()
        }
        let depth = typeExtensionDepths.removeLast()
        if depth > 0 { typeScope.removeLast(depth) }
        typeExtensionAvailability.removeLast()
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !viewExtensionAvailability.isEmpty, typeScope.isEmpty, isPublic(node.modifiers) else {
            return .visitChildren
        }
        let signature = makeSignature(
            node.signature,
            generics: node.genericParameterClause?.parameters.map(\.name.text) ?? [],
            attributes: node.attributes
        )
        declarations.append(.init(
            module: module,
            symbol: node.name.text,
            kind: .modifier,
            sourceModule: module,
            genericParameters: signature.genericParameters,
            availability: viewExtensionAvailability.flatMap { $0 } + availability(node.attributes),
            attributes: attributeList(node.attributes),
            signatures: [signature],
            isDeprecated: isDeprecatedOnIOS(node.attributes),
            isUnavailable: isUnavailableOnIOS(node.attributes),
            sdkVisibility: sdkVisibility(symbol: node.name.text, attributes: node.attributes)
        ))
        return .skipChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !typeScope.isEmpty, isPublic(node.modifiers) else { return .skipChildren }
        let symbol = typeScope.joined(separator: ".")
        let declaration = declarations.last(where: { $0.symbol == symbol })
            ?? HanlinSwiftUIDeclaration(
                module: module,
                symbol: symbol,
                kind: .type,
                sourceModule: module
            )
        let signature = makeSignature(
            node.signature,
            generics: node.genericParameterClause?.parameters.map(\.name.text) ?? [],
            attributes: node.attributes
        )
        declarations.append(.init(
            module: module,
            symbol: symbol,
            kind: declaration.kind,
            sourceModule: module,
            genericParameters: declaration.genericParameters,
            conformances: declaration.conformances,
            availability: declaration.availability
                + typeExtensionAvailability.flatMap { $0 }
                + availability(node.attributes),
            attributes: declaration.attributes + attributeList(node.attributes),
            signatures: [signature],
            isDeprecated: declaration.isDeprecated,
            isUnavailable: declaration.isUnavailable,
            sdkVisibility: declaration.sdkVisibility
        ))
        return .skipChildren
    }

    private func recordType(
        name: String,
        modifiers: DeclModifierListSyntax,
        attributes: AttributeListSyntax,
        generics: GenericParameterClauseSyntax?,
        inheritance: InheritanceClauseSyntax?,
        members: MemberBlockItemListSyntax,
        protocolKind: Bool
    ) {
        guard isPublic(modifiers) else { return }
        let conformances = inheritance?.inheritedTypes.map {
            normalizedQualifiedName($0.type.trimmedDescription)
        } ?? []
        let enumCases = members.flatMap { member -> [String] in
            guard let declaration = member.decl.as(EnumCaseDeclSyntax.self) else {
                return []
            }
            return declaration.elements.map(\.name.text)
        }
        let optionSetCases: [String]
        if conformances.contains(where: { $0 == "OptionSet" || $0.hasSuffix(".OptionSet") }) {
            optionSetCases = members.flatMap { member -> [String] in
                guard let declaration = member.decl.as(VariableDeclSyntax.self),
                      isPublic(declaration.modifiers),
                      declaration.modifiers.contains(where: { $0.name.text == "static" }) else {
                    return []
                }
                return declaration.bindings.compactMap { binding in
                    binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
                        .trimmingCharacters(in: CharacterSet(charactersIn: "`"))
                }
            }
        } else {
            optionSetCases = []
        }
        let kind: HanlinSwiftUIDeclarationKind = conformances.contains(where: {
            $0 == "View" || $0.hasSuffix(".View")
        }) ? .view : .type
        declarations.append(.init(
            module: module,
            symbol: qualified(name),
            kind: protocolKind ? .protocolDeclaration : kind,
            sourceModule: module,
            genericParameters: generics?.parameters.map(\.name.text) ?? [],
            conformances: conformances,
            availability: availability(attributes),
            attributes: attributeList(attributes),
            enumCases: enumCases,
            optionSetCases: optionSetCases,
            isDeprecated: isDeprecatedOnIOS(attributes),
            isUnavailable: isUnavailableOnIOS(attributes),
            sdkVisibility: sdkVisibility(symbol: qualified(name), attributes: attributes)
        ))
    }

    private func makeSignature(
        _ signature: FunctionSignatureSyntax,
        generics: [String],
        attributes: AttributeListSyntax
    ) -> HanlinSwiftUISignature {
        let parameters = signature.parameterClause.parameters.map { parameter in
            let external = parameter.firstName.text == "_" ? nil : parameter.firstName.text
            let local = parameter.secondName?.text ?? parameter.firstName.text
            let type = normalizedQualifiedName(parameter.type.trimmedDescription)
            let attributes = parameter.attributes.compactMap { element -> String? in
                guard case let .attribute(attribute) = element else { return nil }
                return normalizedQualifiedName(attribute.attributeName.trimmedDescription)
            }
            return HanlinSwiftUIParameter(
                externalName: external,
                localName: local == "_" ? "value" : local,
                type: type,
                defaultValue: parameter.defaultValue?.value.trimmedDescription,
                attributes: attributes,
                isBinding: type.contains("Binding<"),
                isViewBuilder: attributes.contains(where: {
                    $0.hasSuffix("ViewBuilder") || $0.hasSuffix("ContentBuilder")
                }),
                isClosure: type.contains("->")
            )
        }
        return .init(
            parameters: parameters,
            returnType: signature.returnClause.map { normalizedQualifiedName($0.type.trimmedDescription) },
            genericParameters: generics,
            isAsync: signature.effectSpecifiers?.asyncSpecifier != nil,
            isThrowing: signature.effectSpecifiers?.throwsClause != nil,
            availability: availability(attributes),
            attributes: attributeList(attributes),
            isDeprecated: isDeprecatedOnIOS(attributes),
            isUnavailable: isUnavailableOnIOS(attributes)
        )
    }

    private func qualified(_ name: String) -> String {
        (typeScope + [name]).joined(separator: ".")
    }

    private func normalizedQualifiedName(_ value: String) -> String {
        value.replacingOccurrences(of: "::", with: ".")
    }

    private func isPublic(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { $0.name.text == "public" || $0.name.text == "open" }
    }

    private func availability(_ attributes: AttributeListSyntax) -> [String] {
        attributes.compactMap { element -> String? in
            guard case let .attribute(attribute) = element,
                  attribute.attributeName.trimmedDescription == "available" else { return nil }
            return attribute.trimmedDescription
        }
    }

    private func attributeText(_ attributes: AttributeListSyntax) -> String {
        attributes.trimmedDescription
    }

    private func attributeList(_ attributes: AttributeListSyntax) -> [String] {
        attributes.compactMap { element -> String? in
            guard case let .attribute(attribute) = element else { return nil }
            return attribute.trimmedDescription
        }
    }

    private func sdkVisibility(symbol: String, attributes: AttributeListSyntax) -> HanlinSwiftUISDKVisibility {
        if attributeList(attributes).contains(where: { $0.hasPrefix("@_spi") }) { return .spi }
        let shortName = symbol.split(separator: ".").last.map(String.init) ?? symbol
        return shortName.hasPrefix("_") ? .underscored : .public
    }

    private func isUnavailableOnIOS(_ attributes: AttributeListSyntax) -> Bool {
        targetAvailability(attributes).contains { text in
            text.contains("unavailable")
        }
    }

    private func isDeprecatedOnIOS(_ attributes: AttributeListSyntax) -> Bool {
        targetAvailability(attributes).contains { text in
            text.contains("deprecated") && !text.contains("deprecated: 100000")
        }
    }

    private func targetAvailability(_ attributes: AttributeListSyntax) -> [String] {
        availability(attributes).filter { text in
            text.hasPrefix("@available(iOS,") || text.hasPrefix("@available(*,")
        }
    }
}
