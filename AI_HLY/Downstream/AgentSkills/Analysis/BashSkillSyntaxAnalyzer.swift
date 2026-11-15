#if HANLIN_SKILL_ANALYSIS_POC
import CryptoKit
import Foundation
import SwiftTreeSitter
import TreeSitter
import TreeSitterBash

/// One original parser per invocation, confined to this actor. No process, import, source,
/// chdir, filesystem read or network operation runs while visiting untrusted syntax.
public actor BashSkillSyntaxAnalyzer {
    public static let wrapperRevision = "08ef81eb8620617b55b08868126707ad72bf754f"
    public static let coreRevision = "da6fe9beb4f7f67beb75914ca8e0d48ae48d6406"
    public static let grammarRevision = "a06c2e4415e9bc0346c6b86d401879ffb44058f7"
    private let budget: SkillSyntaxBudget
    private var cache: [Data: SkillSyntaxReport] = [:]
    private var cacheOrder: [Data] = []
    public var cachedReportCount: Int { cache.count }

    public init(budget: SkillSyntaxBudget = .init()) { self.budget = budget }
    public func clearCache() { cache.removeAll(); cacheOrder.removeAll() }

    public func scan(file: String, utf8: Data) -> SkillSyntaxReport {
        let language = Language(language: tree_sitter_bash())
        let abi = Int(ts_language_abi_version(language.tsLanguage))
        let provenance = SkillSyntaxProvenance(scanner: "tree-sitter-bash/0.25.1",
            wrapperRevision: Self.wrapperRevision, coreRevision: Self.coreRevision,
            grammarRevision: Self.grammarRevision, languageABI: abi)
        func unavailable(_ reason: String, digest: String? = nil) -> SkillSyntaxReport {
            .init(file: file, sourceSHA256: digest, completion: .unknown, provenance: provenance,
                findings: [.init(kind: .unknown, value: nil, confidence: .unknown,
                    source: .init(file: file, line: 1, utf8Column: 1, byteOffset: 0, byteLength: 0), reason: reason)],
                visitedNodes: 0, inputBytes: utf8.count, limitations: Self.limitations)
        }
        guard !file.isEmpty, file.utf8.count <= 1_024, !file.utf8.contains(0) else { return unavailable("invalidSourceIdentity") }
        guard utf8.count <= budget.maximumBytes else { return unavailable("sourceBudget") }
        guard !Task.isCancelled else { return unavailable("cancelled") }
        guard String(data: utf8, encoding: .utf8) != nil else { return unavailable("invalidUTF8") }
        let digest = SHA256.hash(data: utf8).map { String(format: "%02x", $0) }.joined()
        // Byte identity avoids Swift String's canonical-equivalence coalescing of
        // distinct supplied source identities (e.g. NFC versus NFD filenames).
        var key = Data(file.utf8)
        key.append(0)
        key.append(contentsOf: digest.utf8)
        if let previous = cache[key] { return previous }
        guard abi == 15, Language.minimumCompatibleVersion <= abi, abi <= Language.version else {
            return unavailable("incompatibleGrammar", digest: digest)
        }
        let parser = Parser()
        do { try parser.setLanguage(language) }
        catch { return unavailable("languageAdmissionFailed", digest: digest) }
        // This is the original wrapper's bounded API, supported by the exact0.25 core.
        // No newer core is forced and no private pointer/parser implementation is substituted.
        parser.timeout = budget.parseSeconds
        let oldTree: SwiftTreeSitter.Tree? = nil
        guard let tree = parser.parse(tree: oldTree, encoding: TSInputEncodingUTF8, readBlock: { offset, _ in
            guard offset >= 0, offset < utf8.count else { return nil }
            return utf8.subdata(in: offset..<min(offset + 4_096, utf8.count))
        }), let root = tree.rootNode else { return unavailable("parseBudgetOrFailure", digest: digest) }

        var visitor = BashSyntaxVisitor(file: file, bytes: utf8, budget: budget)
        visitor.visit(root)
        guard !Task.isCancelled else { return unavailable("cancelled", digest: digest) }
        let report = SkillSyntaxReport(file: file, sourceSHA256: digest,
            completion: visitor.partial ? .partial : .complete, provenance: provenance,
            findings: visitor.findings, visitedNodes: visitor.visited, inputBytes: utf8.count,
            limitations: Self.limitations)
        if !visitor.partial {
            if cacheOrder.count == 16, let oldest = cacheOrder.first {
                cacheOrder.removeFirst(); cache.removeValue(forKey: oldest)
            }
            cache[key] = report; cacheOrder.append(key)
        }
        return report
    }

    private static let limitations = ["syntaxOnlyNotReadinessOrPermission", "noAliasOrFunctionResolution",
        "noReferencedFileReadsOrExecution", "conditionalFactsDoNotProveReachability",
        "cooperativeParseDeadlineAndInputBoundsNotHardProcessRSSCap"]
}

private struct BashSyntaxVisitor {
    typealias SyntaxNode = SwiftTreeSitter.Node
    let file: String
    let bytes: Data
    let budget: SkillSyntaxBudget
    var findings: [SkillSyntaxFinding] = []
    var partial = false
    var visited = 0

    mutating func visit(_ root: SyntaxNode) {
        var pending: [(SyntaxNode, Int, Bool)] = [(root, 0, false)]
        if root.hasError { append(.unknown, nil, root, false, "syntaxError") }
        while let (node, depth, inheritedConditional) = pending.popLast() {
            guard visited < budget.maximumNodes, depth <= budget.maximumDepth, !Task.isCancelled else {
                append(.unknown, nil, node, inheritedConditional, "traversalBudgetOrCancellation"); break
            }
            visited += 1
            let conditional = inheritedConditional || ["function_definition", "if_statement", "case_statement",
                "while_statement", "for_statement", "c_style_for_statement", "list"].contains(node.nodeType ?? "")
            if node.nodeType == "command" { command(node, conditional) }
            if node.nodeType == "comment", node.byteRange.lowerBound == 0 { shebang(node) }
            if ["simple_expansion", "expansion", "command_substitution", "process_substitution",
                "arithmetic_expansion", "concatenation"].contains(node.nodeType ?? "") {
                append(.unknown, nil, node, conditional, "dynamicExpansion")
            }
            if node.nodeType == "word", let value = text(node), value.contains(where: { "*?[]{}~".contains($0) }) {
                append(.unknown, nil, node, conditional, "pathnameOrBraceExpansion")
            }
            if node.nodeType == "file_redirect", let destination = node.child(byFieldName: "destination") {
                append(literal(destination) == nil ? .unknown : .redirection, literal(destination), destination,
                    conditional, literal(destination) == nil ? "dynamicRedirect" : "literalRedirect")
            }
            if node.isMissing || node.nodeType == "ERROR" { append(.unknown, nil, node, conditional, "syntaxError") }
            if findings.count >= budget.maximumFindings - 1 {
                append(.unknown, nil, node, conditional, "findingBudget"); break
            }
            // Bound the pending queue as well as visits; a wide hostile tree cannot allocate
            // all children before the next visit-budget check.
            guard node.namedChildCount <= budget.maximumNodes - visited - pending.count else {
                append(.unknown, nil, node, conditional, "pendingNodeBudget"); break
            }
            for i in (0..<node.namedChildCount).reversed() {
                if let child = node.namedChild(at: i) { pending.append((child, depth + 1, conditional)) }
            }
        }
    }

    private mutating func command(_ node: SyntaxNode, _ conditional: Bool) {
        guard let name = node.child(byFieldName: "name"), let value = literal(name) else {
            append(.unknown, nil, node, conditional, "dynamicCommand"); return
        }
        append(.command, value, name, conditional, "literalCommandNameNotExecutableProof")
        guard node.childCount <= budget.maximumNodes - visited else {
            append(.unknown, nil, node, conditional, "argumentNodeBudget"); return
        }
        var arguments: [SyntaxNode] = []
        for i in 0..<node.childCount where node.fieldNameForChild(at: i) == "argument" {
            if let argument = node.child(at: i) { arguments.append(argument) }
        }
        if value == "source" || value == "." || value == "cd" {
            let argument = arguments.first
            let target = argument.flatMap { literal($0) }
            append(target == nil ? .unknown : value == "cd" ? .workingDirectory : .scriptReference,
                target, argument ?? name, conditional, target == nil ? "dynamicOrImplicitReference" : "literalReferenceNotExecuted")
        }
        if ["eval", "exec", "alias"].contains(value)
            || (["bash", "sh", "zsh", "python", "python3", "node", "nodejs"].contains(value)
                && arguments.contains(where: { literal($0) == "-c" || literal($0) == "-e" })) {
            append(.unknown, nil, node, conditional, "dynamicEvaluationOrNameResolution")
        }
        if value.hasSuffix(".sh") && (value.hasPrefix("./") || value.hasPrefix("/")) {
            append(.scriptReference, value, name, conditional, "literalInvocationNotExecutableProof")
        }
        // Only the immediate, literal script operand is supported. A later argument
        // ending in .py/.js may be data, module arguments or code for -c/-e.
        if ["bash", "sh", "zsh", "python", "python3", "node", "nodejs"].contains(value),
           let argument = arguments.first, let path = literal(argument), !path.hasPrefix("-"),
           [".sh", ".py", ".js", ".mjs", ".cjs", ".ts", ".tsx"].contains(where: path.hasSuffix) {
            append(.scriptReference, path, argument, conditional, "literalInterpreterReferenceNotExecuted")
        }
        if ["python", "python3"].contains(value), arguments.count >= 2,
           literal(arguments[0]) == "-m", let module = literal(arguments[1]) {
            append(.moduleReference, module, arguments[1], conditional, "literalModuleNotDistributionMapping")
        }
    }

    private mutating func shebang(_ node: SyntaxNode) {
        guard let header = text(node), header.hasPrefix("#!") else { return }
        let words = header.dropFirst(2).split(whereSeparator: \.isWhitespace)
        guard let first = words.first, !first.contains(where: { "$`\\\"'".contains($0) }) else {
            append(.unknown, nil, node, false, "dynamicShebang"); return
        }
        if first == "/usr/bin/env" {
            guard words.count == 2, let name = words.last,
                  !name.hasPrefix("-"), !name.contains(where: { "$`\\\"'".contains($0) }) else {
                append(.unknown, nil, node, false, "complexEnvShebang"); return
            }
            append(.interpreter, String(name), node, false, "literalShebangNotAvailabilityProof")
        } else {
            append(.interpreter, String(first), node, false, "literalShebangNotAvailabilityProof")
        }
    }

    private func literal(_ node: SyntaxNode, depth: Int = 0) -> String? {
        guard depth < 8 else { return nil }
        if node.nodeType == "command_name", node.namedChildCount == 1, let child = node.namedChild(at: 0) {
            return literal(child, depth: depth + 1)
        }
        guard let text = text(node), text.utf8.count <= 256, !text.contains("\\") else { return nil }
        if node.nodeType == "word", node.namedChildCount == 0,
           !text.contains(where: { "$`*?[]{}~".contains($0) }) { return text }
        if node.nodeType == "raw_string", text.first == "'", text.last == "'" { return String(text.dropFirst().dropLast()) }
        if node.nodeType == "string" {
            guard (0..<node.namedChildCount).allSatisfy({ node.namedChild(at: $0)?.nodeType == "string_content" }),
                  text.first == "\"", text.last == "\"" else { return nil }
            return String(text.dropFirst().dropLast())
        }
        return nil
    }

    private func text(_ node: SyntaxNode) -> String? {
        let range = Int(node.byteRange.lowerBound)..<Int(node.byteRange.upperBound)
        guard range.lowerBound >= 0, range.upperBound <= bytes.count, range.count <= 1_024 else { return nil }
        return String(data: bytes.subdata(in: range), encoding: .utf8)
    }

    private mutating func append(_ kind: SkillSyntaxFinding.Kind, _ value: String?, _ node: SyntaxNode,
                                 _ conditional: Bool, _ reason: String) {
        guard findings.count < budget.maximumFindings else { partial = true; return }
        if kind == .unknown { partial = true }
        let point = node.pointRange.lowerBound
        findings.append(.init(kind: kind, value: value,
            confidence: kind == .unknown ? .unknown : conditional ? .conditionalSyntax : .literalSyntax,
            source: .init(file: file, line: Int(point.row) + 1, utf8Column: Int(point.column) + 1,
                byteOffset: Int(node.byteRange.lowerBound), byteLength: Int(node.byteRange.count)), reason: reason))
    }
}
#endif
