// Parse Swift syntax before selecting localization sites. Source edits operate on
// UTF-8 ranges, preserving original literals, comments, interpolation and closures.
// Usage: route_shared_resources.py --root CHECKOUT --report REPORT [--apply]
//        [--exclude repository/relative/file.swift ...]
import Foundation
import SwiftParser
import SwiftSyntax

struct Edit: Codable {
    let offset: Int
    let length: Int
    let old: String
    let replacement: String
    let reason: String
}
struct FileResult: Codable {
    let path: String
    let edits: [Edit]
    let beforeUTF8Bytes: Int
    let afterUTF8Bytes: Int
}
struct Report: Codable {
    let applied: Bool
    let scannedFiles: Int
    let changedFiles: [FileResult]
    let excludedFiles: [String]
    let unresolved: [String]
    let sourceLiteralPreservation: String
}

func callName(_ node: FunctionCallExprSyntax) -> String? {
    if let ref = node.calledExpression.as(DeclReferenceExprSyntax.self) { return ref.baseName.text }
    return node.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
}
func isLocalized(_ expression: ExprSyntax) -> Bool {
    expression.is(StringLiteralExprSyntax.self) || expression.as(FunctionCallExprSyntax.self).map { callName($0) == "LocalizedStringKey" } == true
}
final class LiteralInventory: SyntaxVisitor {
    var literals: [String] = []
    init() { super.init(viewMode: .sourceAccurate) }
    override func visit(_ node: StringSegmentSyntax) -> SyntaxVisitorContinueKind {
        literals.append(node.content.text)
        return .visitChildren
    }
}
final class Router: SyntaxVisitor {
    let path: String
    let source: String
    let bytes: [UInt8]
    let colors: [String: String]
    let converter: SourceLocationConverter
    var edits: [Edit] = []
    var unresolved: [String] = []
    var importsBundle = false
    var chatBodyInsertion: Int?
    var needsLocale = false
    let controls: Set<String> = ["Label", "Button", "Toggle", "Menu", "Picker", "TextField", "Section", "ContentUnavailableView", "LabeledContent", "DatePicker", "ProgressView", "Link"]
    let textModifiers: Set<String> = ["navigationTitle", "alert", "confirmationDialog", "accessibilityLabel", "accessibilityHint", "accessibilityValue", "help"]
    init(path: String, source: String, tree: SourceFileSyntax, colors: [String: String]) {
        self.path = path; self.source = source; self.bytes = Array(source.utf8)
        self.colors = colors; self.converter = SourceLocationConverter(fileName: path, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }
    func add(offset: Int, length: Int = 0, replacement: String, reason: String) {
        let old = String(decoding: bytes[offset..<(offset + length)], as: UTF8.self)
        edits.append(Edit(offset: offset, length: length, old: old, replacement: replacement, reason: reason))
    }
    func replace(_ expression: ExprSyntax, with replacement: String, reason: String) {
        let start = expression.positionAfterSkippingLeadingTrivia.utf8Offset
        add(offset: start, length: expression.endPositionBeforeTrailingTrivia.utf8Offset - start,
            replacement: replacement, reason: reason)
    }
    func wrap(_ expression: ExprSyntax, prefix: String, suffix: String, reason: String) {
        add(offset: expression.positionAfterSkippingLeadingTrivia.utf8Offset, replacement: prefix, reason: reason)
        add(offset: expression.endPositionBeforeTrailingTrivia.utf8Offset, replacement: suffix, reason: reason)
    }
    func bundle(_ node: FunctionCallExprSyntax, reason: String) {
        if let existing = node.arguments.first(where: { $0.label?.text == "bundle" }) {
            if [".main", "Bundle.main"].contains(existing.expression.trimmedDescription) {
                replace(existing.expression, with: "HanlinLocalization.bundle", reason: reason)
            }
            return
        }
        guard let last = node.arguments.last else { return }
        // All existing String/Text overloads order bundle after the key/table.
        // Preserve an explicit locale/comment by inserting before those arguments.
        if let following = node.arguments.first(where: { ["locale", "comment"].contains($0.label?.text ?? "") }) {
            add(offset: following.positionAfterSkippingLeadingTrivia.utf8Offset,
                replacement: "bundle: HanlinLocalization.bundle, ", reason: reason)
        } else {
            add(offset: last.expression.endPositionBeforeTrailingTrivia.utf8Offset,
                replacement: ", bundle: HanlinLocalization.bundle", reason: reason)
        }
    }
    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.path.trimmedDescription == "HanlinLocalization" { importsBundle = true }
        return .visitChildren
    }
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.name.text == "ChatView" {
            chatBodyInsertion = node.memberBlock.leftBrace.endPositionBeforeTrailingTrivia.utf8Offset
        }
        return .visitChildren
    }
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        let name = node.declName.baseName
        if let replacement = colors[name.text] {
            add(offset: name.positionAfterSkippingLeadingTrivia.utf8Offset,
                length: name.trimmedLength.utf8Length, replacement: replacement,
                reason: "shared original color asset")
        }
        return .visitChildren
    }
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let name = callName(node), let first = node.arguments.first else { return .visitChildren }
        if name == "String", first.label?.text == "localized" {
            // A LocalizedStringResource carries its own bundle/table/locale.
            // Its String initializer has no separate bundle argument. Only
            // literal / explicit LocalizationValue overloads accept one.
            if first.expression.is(StringLiteralExprSyntax.self)
                || first.expression.as(FunctionCallExprSyntax.self).map({ callName($0) == "LocalizationValue" }) == true {
                bundle(node, reason: "Foundation localization bundle")
            }
        } else if name == "NSLocalizedString" {
            bundle(node, reason: "named localization table bundle")
        } else if name == "Text", first.label == nil, isLocalized(first.expression) {
            bundle(node, reason: "original SwiftUI localized Text")
        } else if name == "Image", first.label == nil {
            if node.arguments.contains(where: { $0.label?.text == "bundle" }) { return .visitChildren }
            add(offset: first.expression.positionAfterSkippingLeadingTrivia.utf8Offset,
                replacement: "hanlinAsset: ", reason: "shared image with host-name fallback")
        } else if controls.contains(name), first.label == nil, isLocalized(first.expression) {
            if name == "TextField", node.arguments.contains(where: { $0.label?.text == "onCommit" }) {
                guard path == "AI_HLY/ChatView.swift", first.expression.is(StringLiteralExprSyntax.self) else {
                    unresolved.append(path + ":" + String(converter.location(for: first.position).line) + ": legacy TextField requires its original view locale")
                    return .visitChildren
                }
                needsLocale = true
                wrap(first.expression, prefix: "String(localized: ",
                    suffix: ", bundle: HanlinLocalization.bundle, locale: hanlinLocalizationLocale)",
                    reason: "preserve legacy onCommit callback and environment locale")
            } else {
                add(offset: first.expression.positionAfterSkippingLeadingTrivia.utf8Offset,
                    replacement: "hanlin: ", reason: "native control localized label")
            }
        } else if textModifiers.contains(name), first.label == nil, isLocalized(first.expression) {
            wrap(first.expression, prefix: "Text(", suffix: ", bundle: HanlinLocalization.bundle)",
                 reason: "native Text title/accessibility overload")
        }
        if name == "searchable", let prompt = node.arguments.first(where: { $0.label?.text == "prompt" }), isLocalized(prompt.expression) {
            wrap(prompt.expression, prefix: "Text(", suffix: ", bundle: HanlinLocalization.bundle)",
                 reason: "native localized search prompt")
        }
        return .visitChildren
    }
    func finish() throws {
        if needsLocale, !source.contains("var hanlinLocalizationLocale") {
            guard let offset = chatBodyInsertion else { throw Failure.invalid("Missing owning ChatView declaration for its locale") }
            add(offset: offset, replacement: "\n    @Environment(\\.locale) private var hanlinLocalizationLocale\n",
                reason: "retain host locale for legacy prompt")
        }
        if !edits.isEmpty, !importsBundle {
            add(offset: 0, replacement: "import HanlinLocalization\n", reason: "explicit shared resource dependency")
        }
    }
}
enum Failure: Error { case invalid(String) }

var arguments = Array(CommandLine.arguments.dropFirst())
let apply = arguments.contains("--apply")
arguments.removeAll(where: { $0 == "--apply" })
var root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
var reportURL: URL?
var excluded: Set<String> = []
var sourceRoots: [String] = []
while !arguments.isEmpty {
    let flag = arguments.removeFirst()
    guard !arguments.isEmpty else { throw Failure.invalid("Missing value for " + flag) }
    let value = arguments.removeFirst()
    switch flag {
    case "--root": root = URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
    case "--report": reportURL = URL(fileURLWithPath: value)
    case "--exclude": excluded.insert(value)
    case "--source-root": sourceRoots.append(value)
    default: throw Failure.invalid("Unknown argument " + flag)
    }
}
guard let reportURL else { throw Failure.invalid("Pass --report PATH; default is a read-only audit") }
let assetRoot = root.appendingPathComponent("Packages/HanlinPresentationSDK/Sources/HanlinLocalization/Resources/HanlinAssets.xcassets")
let assetDirectories = try FileManager.default.contentsOfDirectory(at: assetRoot, includingPropertiesForKeys: nil)
let colors = Dictionary(uniqueKeysWithValues: assetDirectories.filter { $0.pathExtension == "colorset" && $0.lastPathComponent.hasPrefix("HL") }.map {
    let name = $0.deletingPathExtension().lastPathComponent
    return ("hl" + name.dropFirst(2), "hanlin" + name)
})
var prepared: [(URL, String, FileResult)] = []
var unresolved: [String] = []
var scanned = 0
if sourceRoots.isEmpty {
    sourceRoots = ["AI_HLY", "Packages/HanlinPresentationSDK/Sources",
                   "Packages/HanlinAppExtensionsSDK/Sources", "Packages/HanlinWidgetSDK/Sources"]
}
for component in sourceRoots {
    let directory = root.appendingPathComponent(component)
    let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)!
    for case let url as URL in files where url.pathExtension == "swift" {
        let relative = String(url.path.dropFirst(root.path.count + 1))
        if relative.contains("/Sources/HanlinLocalization/") || excluded.contains(relative) { continue }
        let source = try String(contentsOf: url, encoding: .utf8)
        let tree = Parser.parse(source: source)
        guard !tree.hasError else { throw Failure.invalid("Pre-existing syntax error: " + relative) }
        scanned += 1
        let router = Router(path: relative, source: source, tree: tree, colors: colors)
        router.walk(tree)
        try router.finish()
        unresolved += router.unresolved
        guard !router.edits.isEmpty else { continue }
        var bytes = Array(source.utf8)
        let edits = router.edits.sorted { $0.offset > $1.offset }
        var ceiling = bytes.count
        for edit in edits {
            guard edit.offset + edit.length <= ceiling else { throw Failure.invalid("Overlapping source edits: " + relative) }
            guard String(decoding: bytes[edit.offset..<(edit.offset + edit.length)], as: UTF8.self) == edit.old else {
                throw Failure.invalid("Source range changed: " + relative)
            }
            bytes.replaceSubrange(edit.offset..<(edit.offset + edit.length), with: edit.replacement.utf8)
            ceiling = edit.offset
        }
        let rewritten = String(decoding: bytes, as: UTF8.self)
        let checked = Parser.parse(source: rewritten)
        guard !checked.hasError else { throw Failure.invalid("Edited syntax failed: " + relative) }
        let before = LiteralInventory(); before.walk(tree)
        let after = LiteralInventory(); after.walk(checked)
        guard before.literals == after.literals else { throw Failure.invalid("Original literal bytes/order changed: " + relative) }
        prepared.append((url, rewritten, FileResult(path: relative, edits: edits,
            beforeUTF8Bytes: source.utf8.count, afterUTF8Bytes: rewritten.utf8.count)))
    }
}
// No writes occur until every planned source and literal-preservation check passes.
if apply {
    guard unresolved.isEmpty else { throw Failure.invalid("Resolve unsupported sites before applying: " + unresolved.joined(separator: "; ")) }
    for (url, rewritten, _) in prepared { try rewritten.write(to: url, atomically: true, encoding: .utf8) }
}
let report = Report(applied: apply, scannedFiles: scanned, changedFiles: prepared.map { $0.2 },
    excludedFiles: excluded.sorted(), unresolved: unresolved,
    sourceLiteralPreservation: "All original Swift string segments retained in original order; callback structure and unrelated source bytes preserved. Only the recorded bundle, label-initializer and color-reference edits are applied.")
let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(report).write(to: reportURL)
print("\(apply ? "Applied" : "Planned") \(prepared.count) files, \(prepared.reduce(0) { $0 + $1.2.edits.count }) syntax-selected edits; \(scanned) files parsed; unresolved \(unresolved.count)")
