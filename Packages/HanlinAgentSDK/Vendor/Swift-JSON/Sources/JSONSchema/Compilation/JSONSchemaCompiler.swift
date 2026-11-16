// SPDX-License-Identifier: Apache-2.0
import JSON
import JSONRegexRuntime

/// An immutable compiler for offline Draft 2020-12 schemas.
///
/// Supply external resources through an immutable registry. Compilation validates
/// meta-schemas, required vocabularies and references, and creates a shareable plan.
public struct JSONSchemaCompiler: Sendable {
    /// The immutable configuration used to create each invocation.
    public let options: JSONSchemaOptions
    /// Creates an immutable compiler facade; resources and limits are checked during compilation.
    ///
    /// - Parameters:
    ///   - options: The value configuration used by this facade or operation.
    public init(options: JSONSchemaOptions = .init()) { self.options = options }
    /// Compiles an admitted document and explicit offline registry into an immutable plan.
    ///
    /// - Returns: A shareable Draft 2020-12 snapshot.
    /// - Throws: Compilation/meta-schema/reference errors, resource failure or cancellation.
    ///
    /// - Parameters:
    ///   - document: The admitted schema document; its construction accounting precedes this call.
    ///   - registry: The immutable explicitly supplied offline resources.
    public func compile(_ document: JSONSchemaDocument, registry: JSONSchemaRegistry = .empty) throws -> CompiledJSONSchema {
        try compileWithReport(document, registry: registry).result
    }
    /// Compiles an offline immutable plan with successful compilation accounting.
    ///
    /// The raw JSON overload includes document admission in the same meter. The document
    /// overload starts after document construction; registry and helpers share compilation work.
    /// - Returns: The plan and charged counts.
    /// - Throws: Compilation errors, resource failure or cancellation.
    ///
    /// - Parameters:
    ///   - document: The admitted schema document; its construction accounting precedes this call.
    ///   - registry: The immutable explicitly supplied offline resources.
    public func compileWithReport(_ document: JSONSchemaDocument, registry: JSONSchemaRegistry = .empty) throws -> JSONOperationReport<CompiledJSONSchema> {
        var meter = try JSONWorkMeter(limits: options.limits, domain: .schemaCompilation)
        var state = JSONSchemaCompilation(options: options)
        let result = try state.compile(document, registry: registry, meter: &meter)
        return .init(result: result, statistics: meter.statistics())
    }
    /// Compiles an offline immutable plan with successful compilation accounting.
    ///
    /// The raw JSON overload includes document admission in the same meter. The document
    /// overload starts after document construction; registry and helpers share compilation work.
    /// - Returns: The plan and charged counts.
    /// - Throws: Compilation errors, resource failure or cancellation.
    ///
    /// - Parameters:
    ///   - raw: The exact raw object or Boolean schema.
    ///   - retrievalURI: An optional absolute retrieval identity; this does not fetch resources.
    ///   - registry: The immutable explicitly supplied offline resources.
    public func compileWithReport(_ raw: JSON, retrievalURI: JSONSchemaURI? = nil, registry: JSONSchemaRegistry = .empty) throws -> JSONOperationReport<CompiledJSONSchema> {
        var meter = try JSONWorkMeter(limits: options.limits, domain: .schemaCompilation)
        let document = try JSONSchemaDocument(raw, retrievalURI: retrievalURI, meter: &meter)
        var state = JSONSchemaCompilation(options: options)
        let result = try state.compile(document, registry: registry, meter: &meter)
        return .init(result: result, statistics: meter.statistics())
    }
    /// Package composition borrows the enclosing ledger, including document admission.
    package func compile(_ raw: JSON, retrievalURI: JSONSchemaURI? = nil,
                         registry: JSONSchemaRegistry = .empty, meter: inout JSONWorkMeter) throws -> CompiledJSONSchema {
        let document = try JSONSchemaDocument(raw, retrievalURI: retrievalURI, meter: &meter)
        var state = JSONSchemaCompilation(options: options)
        return try state.compile(document, registry: registry, meter: &meter)
    }
    /// Package composition preserves the admitted document and its source map.
    package func compile(_ document: JSONSchemaDocument, registry: JSONSchemaRegistry,
                         meter: inout JSONWorkMeter) throws -> CompiledJSONSchema {
        var state = JSONSchemaCompilation(options: options)
        return try state.compile(document, registry: registry, meter: &meter)
    }
}

/// Invocation-owned mutable graph builder. Every lookup remains exact and charged.
private struct JSONSchemaCompilation {
    typealias Plan = JSONSchemaPlan
    let options: JSONSchemaOptions
    var documents: [JSONSchemaDocument] = []
    var nodes: [Plan.Node] = []
    var resources: [Plan.Resource] = []
    var roots: [Int] = []
    var selectedRoots: [Int] = []
    // One fixed case-sensitive u-equivalent dialect/Unicode13 profile per compilation.
    // The key is exact UTF-8 spelling; searches never share mutable matcher state.
    var patternPrograms: [(String,RegexProgram)] = []
    var processed = 0

    mutating func reserve(_ bytes: UInt64, meter: inout JSONWorkMeter) throws {
        try meter.retain(bytes)
    }
    func same(_ a: JSONPointer, _ b: JSONPointer, meter: inout JSONWorkMeter) throws -> Bool {
        guard a.tokens.count == b.tokens.count else { return false }
        for i in a.tokens.indices { if try !JSONComparison.textEquals(a.tokens[i].string, b.tokens[i].string, meter: &meter) { return false } }
        return true
    }
    func prefix(_ a: JSONPointer, _ b: JSONPointer, meter: inout JSONWorkMeter) throws -> Bool {
        guard a.tokens.count <= b.tokens.count else { return false }
        for i in a.tokens.indices { if try !JSONComparison.textEquals(a.tokens[i].string, b.tokens[i].string, meter: &meter) { return false } }
        return true
    }
    func findNode(document: Int, pointer: JSONPointer, meter: inout JSONWorkMeter) throws -> Int? {
        for i in nodes.indices {
            try meter.work()
            if nodes[i].document == document, try same(nodes[i].pointer, pointer, meter: &meter) { return i }
        }
        return nil
    }
    func findResource(_ uri: JSONSchemaURI, meter: inout JSONWorkMeter) throws -> Int? {
        for i in resources.indices { if try JSONComparison.textEquals(resources[i].uri.string, uri.string, meter: &meter) { return i } }
        return nil
    }
    mutating func resource(_ uri: JSONSchemaURI, root: Int, meter: inout JSONWorkMeter) throws -> Int {
        let key = try uri.withoutFragment(meter: &meter)
        if let existing = try findResource(key, meter: &meter) {
            guard resources[existing].root == root else { throw JSONSchemaCompilationFailure(.identifier, location: nodes[root].pointer) }
            return existing
        }
        try reserve(32, meter: &meter); resources.append(.init(uri: key, root: root)); return resources.count-1
    }
    mutating func appendNode(_ raw: JSON, document: Int, pointer: JSONPointer, base: JSONSchemaURI,
                             resource: Int, meter: inout JSONWorkMeter) throws -> Int {
        switch raw { case .boolean, .object: break; default: throw JSONSchemaCompilationFailure(.schemaSyntax, location: pointer) }
        if let existing = try findNode(document: document, pointer: pointer, meter: &meter) { return existing }
        try meter.work(); try reserve(64, meter: &meter)
        nodes.append(.init(raw: raw, document: document, pointer: pointer, base: base, resource: resource, formatAssertion: options.formatAssertion))
        return nodes.count-1
    }
    func location(_ pointer: JSONPointer, _ tokens: [JSONKey], meter: inout JSONWorkMeter) throws -> JSONPointer {
        try JSONPointer.decodedTokens([pointer.tokens, tokens].lazy.flatMap { $0 }, meter: &meter)
    }
    mutating func child(_ raw: JSON, parent: Int, keyword: Plan.Keyword, token: JSONKey?, meter: inout JSONWorkMeter) throws {
        let key = try JSONKey(keyword.rawValue, meter: &meter)
        let pointer = try location(nodes[parent].pointer, token.map { [key, $0] } ?? [key], meter: &meter)
        let target = try appendNode(raw, document: nodes[parent].document, pointer: pointer,
                                    base: nodes[parent].base, resource: nodes[parent].resource, meter: &meter)
        nodes[target].vocabulary = nodes[parent].vocabulary
        nodes[target].metaSchema = nodes[parent].metaSchema
        nodes[target].formatAssertion = nodes[parent].formatAssertion
        try reserve(24, meter: &meter); nodes[parent].children.append(.init(keyword: keyword, token: token, target: target))
    }
    mutating func anchor(_ name: String, node: Int, dynamic: Bool, meter: inout JSONWorkMeter) throws {
        var first = true
        for byte in name.utf8 {
            try meter.work()
            let alpha = (65...90).contains(byte) || (97...122).contains(byte) || byte == 95
            guard alpha || (!first && ((48...57).contains(byte) || byte == 45 || byte == 46)) else { throw JSONSchemaCompilationFailure(.anchor, location: nodes[node].pointer) }
            first = false
        }
        guard !first else { throw JSONSchemaCompilationFailure(.anchor, location: nodes[node].pointer) }
        let resource = nodes[node].resource
        for existing in resources[resource].anchors {
            if try JSONComparison.textEquals(existing.name.string, name, meter: &meter) {
                throw JSONSchemaCompilationFailure(.anchor, location: nodes[node].pointer)
            }
        }
        try reserve(32, meter: &meter)
        resources[resource].anchors.append(.init(name: try JSONKey(name, meter: &meter), node: node, dynamic: dynamic))
    }
    mutating func pattern(_ text: String, parent: Int, keyword: Plan.Keyword, key: JSONKey?, meter: inout JSONWorkMeter) throws {
        for (spelling,cached) in patternPrograms {
            var a = spelling.utf8.makeIterator(), b = text.utf8.makeIterator(), equal = true
            while true {
                try RegexBudget.compileStep(meter: &meter)
                let x = a.next(), y = b.next()
                if x != y { equal = false; break }; if x == nil { break }
            }
            if equal {
                var bytes: UInt64 = 0
                for _ in text.utf8 {
                    try RegexBudget.compileStep(meter: &meter); bytes += 1
                    try meter.require(.regexPatternBytes,bytes); try meter.charge(.aggregateRegexPatternBytes)
                }
                try reserve(24,meter: &meter); nodes[parent].patterns.append(.init(keyword: keyword,key: key,program: cached)); return
            }
        }
        let program: RegexProgram
        do { program = try RegexCompiler.compile(text, meter: &meter) }
        catch is RegexFailure { throw JSONSchemaCompilationFailure(.schemaSyntax, location: nodes[parent].pointer) }
        try reserve(32,meter: &meter); patternPrograms.append((text,program))
        try reserve(24, meter: &meter); nodes[parent].patterns.append(.init(keyword: keyword, key: key, program: program))
    }
    mutating func process(meter: inout JSONWorkMeter) throws {
        while processed < nodes.count {
            let id = processed; processed += 1; try meter.work()
            guard let object = nodes[id].raw.objectValue else { continue }
            if let declaration = try object.lookup("$id", meter: &meter) {
                guard let text = declaration.stringValue else { throw JSONSchemaCompilationFailure(.schemaSyntax, location: nodes[id].pointer) }
                let base = try JSONSchemaURI.parse(text, relativeTo: nodes[id].base, meter: &meter)
                guard base.fragment?.isEmpty ?? true else { throw JSONSchemaCompilationFailure(.identifier, location: nodes[id].pointer) }
                nodes[id].base = try base.withoutFragment(meter: &meter)
                nodes[id].resource = try resource(nodes[id].base, root: id, meter: &meter)
            }
            try dialect(id, meter: &meter)
            for member in object {
                try meter.work()
                guard let keyword = try Plan.Keyword.classify(member.key, meter: &meter), nodes[id].vocabulary.applies(keyword) else { continue }
                let pointer = try location(nodes[id].pointer, [member.key], meter: &meter)
                try JSONSchemaShape.validate(keyword, value: member.value, location: pointer, meter: &meter)
                switch keyword {
                case .anchor: try anchor(member.value.stringValue!, node: id, dynamic: false, meter: &meter)
                case .dynamicAnchor: try anchor(member.value.stringValue!, node: id, dynamic: true, meter: &meter)
                case .defs, .definitions, .properties, .patternProperties, .dependentSchemas:
                    for entry in member.value.objectValue! {
                        try meter.work(); try child(entry.value, parent: id, keyword: keyword, token: entry.key, meter: &meter)
                        if keyword == .patternProperties { try pattern(entry.key.string, parent: id, keyword: keyword, key: entry.key, meter: &meter) }
                    }
                case .dependencies:
                    for entry in member.value.objectValue! { try meter.work(); if entry.value.arrayValue == nil { try child(entry.value, parent: id, keyword: keyword, token: entry.key, meter: &meter) } }
                case .allOf, .anyOf, .oneOf, .prefixItems:
                    for (index, entry) in member.value.arrayValue!.enumerated() {
                        try meter.work(); try child(entry, parent: id, keyword: keyword, token: JSONKey(String(index), meter: &meter), meter: &meter)
                    }
                case .not, .if, .then, .else, .items, .contains, .additionalProperties, .propertyNames, .unevaluatedProperties, .unevaluatedItems, .contentSchema:
                    try child(member.value, parent: id, keyword: keyword, token: nil, meter: &meter)
                case .format:
                    if nodes[id].vocabulary.contains(.formatAssertion), try JSONSchemaFormats.name(member.value.stringValue!,meter: &meter) == nil { throw JSONSchemaCompilationFailure(.vocabulary, location: pointer) }
                case .pattern: try pattern(member.value.stringValue!, parent: id, keyword: keyword, key: nil, meter: &meter)
                default: break
                }
            }
        }
    }
    mutating func resolve(_ text: String, node: Int, keyword: Plan.Keyword, meter: inout JSONWorkMeter) throws -> Plan.Reference {
        do { return try resolveTarget(text, node: node, keyword: keyword, meter: &meter) }
        catch let error as JSONFailure where error.category != .resource { throw JSONSchemaCompilationFailure(.reference, location: nodes[node].pointer) }
    }
    mutating func resolveTarget(_ text: String, node: Int, keyword: Plan.Keyword, meter: inout JSONWorkMeter) throws -> Plan.Reference {
        let uri = try JSONSchemaURI.parse(text, relativeTo: nodes[node].base, meter: &meter)
        let base = try uri.withoutFragment(meter: &meter)
        guard let resource = try findResource(base, meter: &meter) else { throw JSONSchemaCompilationFailure(.missingResource, location: nodes[node].pointer) }
        let root = resources[resource].root
        let fragment = try JSONPointer.fragmentText("#" + (uri.fragment ?? ""), meter: &meter)
        var target = root, dynamicName: JSONKey?
        if !fragment.isEmpty {
            if fragment.utf8.first == 47 {
                let relative = try JSONPointer.parse(fragment, meter: &meter)
                let pointer = try location(nodes[root].pointer, relative.tokens, meter: &meter)
                if let existing = try findNode(document: nodes[root].document, pointer: pointer, meter: &meter) { target = existing }
                else {
                    let raw: JSON
                    do { raw = try relative.resolve(in: nodes[root].raw, meter: &meter) }
                    catch let failure as JSONFailure where failure.category != .resource { throw JSONSchemaCompilationFailure(.reference, location: nodes[node].pointer) }
                    var parent = root
                    for candidate in nodes.indices {
                        try meter.work()
                        if nodes[candidate].document == nodes[root].document,
                           nodes[candidate].pointer.tokens.count > nodes[parent].pointer.tokens.count,
                           try prefix(nodes[candidate].pointer, pointer, meter: &meter) { parent = candidate }
                    }
                    target = try appendNode(raw, document: nodes[root].document, pointer: pointer,
                                             base: nodes[parent].base, resource: nodes[parent].resource, meter: &meter)
                    nodes[target].vocabulary = nodes[parent].vocabulary
                    nodes[target].metaSchema = nodes[parent].metaSchema
                    nodes[target].formatAssertion = nodes[parent].formatAssertion
                    try reserve(8,meter: &meter); selectedRoots.append(target)
                    try process(meter: &meter)
                }
            } else {
                var found: Plan.Anchor?
                for anchor in resources[nodes[root].resource].anchors {
                    if try JSONComparison.textEquals(anchor.name.string, fragment, meter: &meter) { found = anchor; break }
                }
                guard let anchor = found else { throw JSONSchemaCompilationFailure(.reference, location: nodes[node].pointer) }
                target = anchor.node
                if keyword == .dynamicRef && anchor.dynamic { dynamicName = anchor.name }
            }
        }
        try meter.charge(.referenceEdges); try reserve(24, meter: &meter)
        return .init(keyword: keyword, target: target, dynamicAnchor: dynamicName)
    }
    mutating func dialect(_ id: Int, meter: inout JSONWorkMeter) throws {
        guard let object = nodes[id].raw.objectValue,
              let text = try object.lookup("$schema", meter: &meter)?.stringValue else { return }
        guard resources[nodes[id].resource].root == id else { throw JSONSchemaCompilationFailure(.dialect, location: nodes[id].pointer) }
        let uri: JSONSchemaURI
        do { uri = try JSONSchemaURI.parse(text, relativeTo: nil, meter: &meter) }
        catch is JSONSchemaCompilationFailure { throw JSONSchemaCompilationFailure(.dialect, location: nodes[id].pointer) }
        let base = try uri.withoutFragment(meter: &meter)
        guard let index = try findResource(base, meter: &meter) else { throw JSONSchemaCompilationFailure(.dialect, location: nodes[id].pointer) }
        var root = resources[index].root
        let fragment = try JSONPointer.fragmentText("#" + (uri.fragment ?? ""),meter: &meter)
        if !fragment.isEmpty {
            let resourceRoot = root
            let relative: JSONPointer
            if fragment.utf8.first == 47 { relative = try JSONPointer.parse(fragment,meter: &meter) }
            else {
                guard let found = try metaAnchor(fragment,root: root,meter: &meter) else { throw JSONSchemaCompilationFailure(.dialect,location: nodes[id].pointer) }
                relative = found
            }
            let pointer = try location(nodes[resourceRoot].pointer,relative.tokens,meter: &meter)
            if let existing = try findNode(document: nodes[resourceRoot].document,pointer: pointer,meter: &meter) { root = existing }
            else {
                let raw: JSON
                do { raw = try relative.resolve(in: nodes[resourceRoot].raw,meter: &meter) }
                catch let error as JSONFailure where error.category != .resource { throw JSONSchemaCompilationFailure(.dialect,location: nodes[id].pointer) }
                root = try appendNode(raw,document: nodes[resourceRoot].document,pointer: pointer,base: base,resource: index,meter: &meter)
                nodes[root].vocabulary = nodes[resourceRoot].vocabulary
                nodes[root].metaSchema = nodes[resourceRoot].metaSchema
                nodes[root].formatAssertion = nodes[resourceRoot].formatAssertion
                try reserve(8,meter: &meter); selectedRoots.append(root)
            }
        }
        nodes[id].metaSchema = root
        if let declaration = try nodes[root].raw.objectValue?.lookup("$vocabulary", meter: &meter) {
            guard let vocabulary = declaration.objectValue else { throw JSONSchemaCompilationFailure(.vocabulary, location: nodes[root].pointer) }
            var active: JSONSchemaVocabulary = .core
            let supported: [(String,JSONSchemaVocabulary)] = [("core",.core),("applicator",.applicator),("validation",.validation),("unevaluated",.unevaluated),("meta-data",.metadata),("format-annotation",.formatAnnotation),("format-assertion",.formatAssertion),("content",.content)]
            for member in vocabulary {
                try meter.work()
                guard let required = member.value.booleanValue else { throw JSONSchemaCompilationFailure(.vocabulary, location: nodes[root].pointer) }
                let declared = try JSONSchemaURI.parse(member.key.string, relativeTo: nil, meter: &meter)
                var recognized = false
                for (name,mask) in supported {
                    if try JSONComparison.textEquals(declared.string, "https://json-schema.org/draft/2020-12/vocab/" + name, meter: &meter) {
                        recognized = true; active.insert(mask); break
                    }
                }
                if required && !recognized { throw JSONSchemaCompilationFailure(.vocabulary, location: nodes[root].pointer) }
            }
            nodes[id].vocabulary = active
            nodes[id].formatAssertion = options.formatAssertion || active.contains(.formatAssertion)
        }
    }
    /// Discover a meta-schema anchor before the ordinary processing queue reaches its document.
    /// Only declared schema locations are visited; another $id starts a separate resource.
    func metaAnchor(_ name: String,root: Int,meter: inout JSONWorkMeter) throws -> JSONPointer? {
        var stack: [(JSON,JSONPointer)] = []
        func push(_ raw: JSON,_ pointer: JSONPointer,meter: inout JSONWorkMeter) throws {
            try meter.work(); try meter.retain(16); stack.append((raw,pointer))
        }
        let empty = try JSONPointer.decodedTokens([JSONKey](),meter: &meter)
        try push(nodes[root].raw,empty,meter: &meter)
        var found: JSONPointer?
        while let (raw,pointer) = stack.popLast() {
            try meter.work(); try meter.release(16)
            guard let object = raw.objectValue else { continue }
            if !pointer.tokens.isEmpty, try object.lookup("$id",meter: &meter) != nil { continue }
            for keyword in ["$anchor","$dynamicAnchor"] {
                if let declared = try object.lookup(keyword,meter: &meter)?.stringValue,
                   try JSONComparison.textEquals(declared,name,meter: &meter) {
                    guard found == nil else { throw JSONSchemaCompilationFailure(.anchor,location: nodes[root].pointer) }; found = pointer
                }
            }
            for member in object {
                try meter.work()
                guard let keyword = try Plan.Keyword.classify(member.key,meter: &meter), nodes[root].vocabulary.applies(keyword) else { continue }
                let prefix = try location(pointer,[member.key],meter: &meter)
                switch keyword {
                case .defs,.definitions,.properties,.patternProperties,.dependentSchemas,.dependencies:
                    if let entries = member.value.objectValue {
                        for entry in entries { try meter.work(); if entry.value.objectValue != nil || entry.value.booleanValue != nil { try push(entry.value,location(prefix,[entry.key],meter: &meter),meter: &meter) } }
                    }
                case .allOf,.anyOf,.oneOf,.prefixItems:
                    if let entries = member.value.arrayValue { for (index,entry) in entries.enumerated() { try push(entry,location(prefix,[JSONKey(String(index),meter: &meter)],meter: &meter),meter: &meter) } }
                case .not,.if,.then,.else,.items,.contains,.additionalProperties,.propertyNames,.unevaluatedProperties,.unevaluatedItems,.contentSchema:
                    try push(member.value,prefix,meter: &meter)
                default: break
                }
            }
        }
        return found
    }
    mutating func admit(_ document: JSONSchemaDocument, meter: inout JSONWorkMeter) throws {
        try meter.charge(.schemaDocuments); try meter.resetValueBounds()
        try JSONAdmission.value(document.raw, meter: &meter, owned: true)
        var cursor = JSONWritingCursor(value: document.raw, options: .init())
        var bytes: UInt64 = 0
        while try cursor.next(meter: &meter) != nil { try meter.work(); bytes += 1; try meter.require(.inputBytes, bytes) }
        try meter.charge(.schemaBytes, bytes); try reserve(16, meter: &meter); documents.append(document)
    }
    mutating func compile(_ document: JSONSchemaDocument, registry: JSONSchemaRegistry, meter: inout JSONWorkMeter) throws -> CompiledJSONSchema {
        try admit(document, meter: &meter)
        for entry in registry.documents { try meter.work(); try admit(entry, meter: &meter) }
        let builtin = try JSONSchemaRegistry.loadBuiltins(meter: &meter)
        for entry in builtin {
            var duplicate = false
            for existing in documents {
                try meter.work()
                if let a = existing.retrievalURI, let b = entry.retrievalURI,
                   try JSONComparison.textEquals(a.string, b.string, meter: &meter) {
                    guard try JSONComparison.equals(existing.raw, entry.raw, meter: &meter) else { throw JSONSchemaCompilationFailure(.identifier) }
                    duplicate = true; break
                }
            }
            if !duplicate {
                try reserve(16, meter: &meter); documents.append(entry)
            }
        }
        for (index, entry) in documents.enumerated() {
            try meter.work()
            let base = try entry.retrievalURI ?? JSONSchemaURI.parse("urn:swift-json:root", relativeTo: nil, meter: &meter)
            let pointer = try JSONPointer.decodedTokens([JSONKey](), meter: &meter)
            let root = try appendNode(entry.raw, document: index, pointer: pointer, base: base, resource: -1, meter: &meter)
            nodes[root].resource = try resource(base, root: root, meter: &meter)
            try reserve(8, meter: &meter); roots.append(root)
        }
        for root in roots {
            if let text = try nodes[root].raw.objectValue?.lookup("$id", meter: &meter)?.stringValue {
                let uri = try JSONSchemaURI.parse(text, relativeTo: nodes[root].base, meter: &meter)
                guard uri.fragment?.isEmpty ?? true else { throw JSONSchemaCompilationFailure(.identifier, location: nodes[root].pointer) }
                _ = try resource(uri, root: root, meter: &meter)
            }
        }
        try process(meter: &meter)
        var current = 0
        while current < nodes.count {
            let id = current; current += 1; try meter.work()
            guard let object = nodes[id].raw.objectValue else { continue }
            for keyword in [Plan.Keyword.ref, .dynamicRef] {
                if nodes[id].vocabulary.applies(keyword), let text = try object.lookup(keyword.rawValue, meter: &meter)?.stringValue {
                    let reference = try resolve(text, node: id, keyword: keyword, meter: &meter)
                    nodes[id].references.append(reference)
                }
            }
        }
        // Programs now belong to immutable plan nodes. Retire the temporary lookup slots.
        try meter.release(UInt64(patternPrograms.count)*32); patternPrograms = []
        let plan = Plan(documents: documents, nodes: nodes, resources: resources, root: roots[0])
        let officialURI = try JSONSchemaURI.parse("https://json-schema.org/draft/2020-12/schema", relativeTo: nil, meter: &meter)
        guard let officialResource = try findResource(officialURI, meter: &meter) else { throw JSONSchemaCompilationFailure(.metaSchema) }
        let official = resources[officialResource].root
        var evaluationOptions = options; evaluationOptions.output = .flag; evaluationOptions.collectAnnotations = false
        // The fixed shape grammar builds a finite immutable bootstrap graph. The loaded official
        // documents are then evaluated by that graph before any caller schema is accepted.
        var evaluator = JSONSchemaEvaluation(plan: plan, options: evaluationOptions)
        for root in roots.dropFirst(1 + registry.documents.count) {
            try meter.work()
            let result = try evaluator.evaluate(nodes[root].raw, at: official, meter: &meter)
            guard result.isValid else { throw JSONSchemaCompilationFailure(.metaSchema, location: nodes[root].pointer) }
        }
        for root in roots.prefix(1 + registry.documents.count) {
            try meter.work()
            let result = try evaluator.evaluate(nodes[root].raw, at: nodes[root].metaSchema ?? official, meter: &meter)
            guard result.isValid else { throw JSONSchemaCompilationFailure(.metaSchema, location: nodes[root].pointer) }
        }
        for id in nodes.indices {
            try meter.work()
            guard resources[nodes[id].resource].root == id else { continue }
            var top = false
            for root in roots { try meter.work(); if root == id { top = true; break } }
            if top { continue }
            let result = try evaluator.evaluate(nodes[id].raw, at: nodes[id].metaSchema ?? official, meter: &meter)
            guard result.isValid else { throw JSONSchemaCompilationFailure(.metaSchema, location: nodes[id].pointer) }
        }
        // An unknown keyword's value becomes a schema when a Pointer reference selects it.
        // Its parent meta-schema may not have traversed that location, so validate it explicitly.
        for id in selectedRoots {
            try meter.work()
            let result = try evaluator.evaluate(nodes[id].raw,at: nodes[id].metaSchema ?? official,meter: &meter)
            guard result.isValid else { throw JSONSchemaCompilationFailure(.metaSchema,location: nodes[id].pointer) }
        }
        return .init(document: document, plan: plan)
    }
}
