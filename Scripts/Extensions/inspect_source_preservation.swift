import Foundation
import SwiftParser
import SwiftSyntax

struct Body: Encodable {
    let kind: String
    let name: String
    let source: String
    let tokens: [String]
}
final class Inventory: SyntaxVisitor {
    var bodies: [Body] = []
    init() { super.init(viewMode: .sourceAccurate) }
    func owner(_ syntax: some SyntaxProtocol) -> String {
        var names: [String] = []
        var parent = syntax.parent
        while let node = parent {
            if let declaration = node.as(StructDeclSyntax.self) { names.append(declaration.name.text) }
            else if let declaration = node.as(ClassDeclSyntax.self) { names.append(declaration.name.text) }
            else if let declaration = node.as(EnumDeclSyntax.self) { names.append(declaration.name.text) }
            else if let declaration = node.as(ActorDeclSyntax.self) { names.append(declaration.name.text) }
            parent = node.parent
        }
        return names.reversed().joined(separator: ".")
    }
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if let body = node.body {
            let labels = node.signature.parameterClause.parameters.map { $0.firstName.text + ":" }.joined()
            let name = [owner(node), node.name.text + "(" + labels + ")"].filter { !$0.isEmpty }.joined(separator: ".")
            bodies.append(.init(kind: "function", name: name, source: body.trimmedDescription,
                tokens: body.tokens(viewMode: .sourceAccurate).map { $0.text }))
        }
        return .skipChildren
    }
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            guard let body = binding.accessorBlock else { continue }
            let name = [owner(node), binding.pattern.trimmedDescription].filter { !$0.isEmpty }.joined(separator: ".")
            bodies.append(.init(kind: "property", name: name, source: body.trimmedDescription,
                tokens: body.tokens(viewMode: .sourceAccurate).map { $0.text }))
        }
        return .skipChildren
    }
}
let source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
let tree = Parser.parse(source: source)
guard !tree.hasError else { throw NSError(domain: "ExtensionSourceSyntax", code: 1) }
let inventory = Inventory(); inventory.walk(tree)
let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
FileHandle.standardOutput.write(try encoder.encode(inventory.bodies))
