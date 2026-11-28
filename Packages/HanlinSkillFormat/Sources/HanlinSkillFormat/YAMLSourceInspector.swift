import CYaml
import Foundation

struct YAMLSourceInspection: Hashable, Sendable {
    let scalarFieldRanges: [String: Range<Int>]
    let rootIsFlow: Bool
    let rootIndent: Int
    let rootEndOffset: Int
    let flowHasTrailingComma: Bool
    let anchoredFields: Set<String>
}

/// Uses ORIGINAL libyaml events/tokens from the pinned Yams dependency for resource preflight
/// and source spans. It does not recognize YAML grammar or construct a replacement value tree.
/// Actual metadata composition and scalar resolution remain Yams' public compose/Node APIs.
enum YAMLSourceInspector {
    private enum Kind { case mapping, sequence }
    private struct Weight { var nodes: Int; var bytes: Int; var depth: Int = 1 }
    private struct Frame {
        let kind: Kind
        let anchor: Data?
        var weight = Weight(nodes: 1, bytes: 0)
        var expectsKey = true
        var key: String?
    }
    private struct Candidate { let start: Int; let end: Int }

    static func inspect(_ data: Data, globalOffset: Int, limits: SkillMarkdownLimits) throws -> YAMLSourceInspection {
        guard let text = String(data: data, encoding: .utf8) else { throw SkillMarkdownError(.invalidUTF8, "Frontmatter must be UTF-8.") }
        var byteOffsets = [0], byteCount = 0
        for scalar in text.unicodeScalars { byteCount += scalar.utf8.count; byteOffsets.append(byteCount) }
        func localOffset(_ mark: yaml_mark_t) throws -> Int {
            guard let index = Int(exactly: mark.index), byteOffsets.indices.contains(index) else {
                throw SkillMarkdownError(.malformedYAML, "The YAML backend returned an invalid source position.")
            }
            return byteOffsets[index]
        }
        func position(_ mark: yaml_mark_t) -> SkillSourcePosition {
            .init(line: Int(mark.line) + 2, column: Int(mark.column) + 1,
                  byteOffset: globalOffset + ((try? localOffset(mark)) ?? 0))
        }
        func failure(_ parser: yaml_parser_t) -> SkillMarkdownError {
            let message = parser.problem.map { String(cString: $0) } ?? "Malformed YAML."
            return .init(.malformedYAML, message, position: position(parser.problem_mark))
        }
        guard !data.isEmpty else {
            return .init(scalarFieldRanges: [:], rootIsFlow: false, rootIndent: 0,
                         rootEndOffset: globalOffset, flowHasTrailingComma: false, anchoredFields: [])
        }
        var candidates = [String: Candidate](), frames = [Frame](), anchors = [Data: Weight]()
        var activeAnchors = Set<Data>(), aliases = 0, nodes = 0, documents = 0
        var flow = false, indent = 0, rootEnd = data.count, rootEndCharacterIndex: Int?
        var anchoredFields = Set<String>()
        func raw(_ pointer: UnsafePointer<UInt8>?) -> Data? {
            pointer.map { Data(String(cString: $0).utf8) }
        }
        func complete(_ weight: Weight, scalarKey: String? = nil) throws {
            guard weight.depth <= limits.maximumDepth else { throw SkillMarkdownError(.nestingLimit, "Expanded YAML nesting exceeds its budget.") }
            guard weight.nodes <= limits.maximumExpandedNodes, weight.bytes <= limits.maximumExpandedScalarBytes else {
                throw SkillMarkdownError(.expansionLimit, "Expanded YAML metadata exceeds its node/text budget.")
            }
            if var parent = frames.popLast() {
                guard parent.weight.nodes <= limits.maximumExpandedNodes - weight.nodes,
                      parent.weight.bytes <= limits.maximumExpandedScalarBytes - weight.bytes else {
                    throw SkillMarkdownError(.expansionLimit, "Expanded YAML metadata exceeds its node/text budget.")
                }
                parent.weight.nodes += weight.nodes; parent.weight.bytes += weight.bytes
                parent.weight.depth = max(parent.weight.depth, weight.depth + 1)
                if parent.kind == .mapping {
                    if parent.expectsKey { parent.key = scalarKey; parent.expectsKey = false }
                    else { parent.key = nil; parent.expectsKey = true }
                }
                frames.append(parent)
            }
        }
        try data.withUnsafeBytes { buffer in
            var parser = yaml_parser_t()
            guard yaml_parser_initialize(&parser) == 1 else { throw SkillMarkdownError(.inputLimit, "Unable to allocate the YAML parser.") }
            defer { yaml_parser_delete(&parser) }
            yaml_parser_set_encoding(&parser, YAML_UTF8_ENCODING)
            yaml_parser_set_input_string(&parser, buffer.baseAddress!.assumingMemoryBound(to: UInt8.self), buffer.count)
            var ended = false, events = 0
            while !ended {
                events += 1
                if events % 256 == 0 { try Task.checkCancellation() }
                var event = yaml_event_t()
                guard yaml_parser_parse(&parser, &event) == 1 else { throw failure(parser) }
                defer { yaml_event_delete(&event) }
                switch event.type {
                case YAML_DOCUMENT_START_EVENT:
                    documents += 1
                    guard documents == 1 else { throw SkillMarkdownError(.malformedYAML, "Frontmatter must contain one YAML document.", position: position(event.start_mark)) }
                case YAML_MAPPING_START_EVENT, YAML_SEQUENCE_START_EVENT:
                    nodes += 1
                    guard frames.count < limits.maximumDepth else { throw SkillMarkdownError(.nestingLimit, "YAML metadata nesting exceeds its budget.", position: position(event.start_mark)) }
                    let mapping = event.type == YAML_MAPPING_START_EVENT
                    let anchor = mapping ? raw(event.data.mapping_start.anchor) : raw(event.data.sequence_start.anchor)
                    if frames.isEmpty, mapping {
                        flow = event.data.mapping_start.style == YAML_FLOW_MAPPING_STYLE
                        indent = Int(event.start_mark.column)
                    }
                    if let anchor { activeAnchors.insert(anchor) }
                    let tag = mapping ? raw(event.data.mapping_start.tag) : raw(event.data.sequence_start.tag)
                    frames.append(.init(kind: mapping ? .mapping : .sequence, anchor: anchor,
                                        weight: .init(nodes: 1, bytes: tag?.count ?? 64)))
                case YAML_MAPPING_END_EVENT, YAML_SEQUENCE_END_EVENT:
                    guard let frame = frames.popLast() else { throw SkillMarkdownError(.malformedYAML, "Unbalanced YAML structure.", position: position(event.start_mark)) }
                    if let anchor = frame.anchor { anchors[anchor] = frame.weight; activeAnchors.remove(anchor) }
                    if frames.isEmpty {
                        rootEnd = try localOffset(event.start_mark)
                        rootEndCharacterIndex = Int(event.start_mark.index)
                    }
                    try complete(frame.weight)
                case YAML_SCALAR_EVENT:
                    nodes += 1
                    let value = String(decoding: UnsafeBufferPointer(start: event.data.scalar.value, count: Int(event.data.scalar.length)), as: UTF8.self)
                    if frames.count == 1, frames[0].kind == .mapping, !frames[0].expectsKey,
                       let key = frames[0].key, ["name", "title", "description"].contains(key) {
                        candidates[key] = .init(start: Int(event.start_mark.index), end: Int(event.end_mark.index))
                        if event.data.scalar.anchor != nil { anchoredFields.insert(key) }
                    }
                    let weight = Weight(nodes: 1, bytes: Int(event.data.scalar.length) + (raw(event.data.scalar.tag)?.count ?? 64))
                    if let anchor = raw(event.data.scalar.anchor) { anchors[anchor] = weight }
                    try complete(weight, scalarKey: value)
                case YAML_ALIAS_EVENT:
                    nodes += 1; aliases += 1
                    guard aliases <= limits.maximumAliases, let anchor = raw(event.data.alias.anchor) else { throw SkillMarkdownError(.aliasLimit, "YAML aliases exceed their budget.", position: position(event.start_mark)) }
                    guard !activeAnchors.contains(anchor) else { throw SkillMarkdownError(.aliasLimit, "Cyclic YAML aliases cannot form a finite metadata tree.", position: position(event.start_mark)) }
                    guard let weight = anchors[anchor] else { throw SkillMarkdownError(.malformedYAML, "Undefined YAML alias.", position: position(event.start_mark)) }
                    if frames.count == 1, frames[0].kind == .mapping, !frames[0].expectsKey,
                       let key = frames[0].key, ["name", "title", "description"].contains(key) {
                        candidates[key] = .init(start: Int(event.start_mark.index), end: Int(event.end_mark.index))
                    }
                    try complete(weight)
                case YAML_STREAM_END_EVENT: ended = true
                default: break
                }
                guard nodes <= limits.maximumNodes else { throw SkillMarkdownError(.nodeLimit, "YAML metadata exceeds its node budget.", position: position(event.start_mark)) }
            }
        }
        // Source marks are CHARACTER indices, not UTF-8 offsets. Map them through the original
        // scalar/byte table and use the upstream scanner's scalar token range (excluding tags/
        // anchors) so a known-field edit cannot remove an anchor used by an unknown field.
        var ranges = [String: Range<Int>](), trailingComma = false
        try data.withUnsafeBytes { buffer in
            var parser = yaml_parser_t()
            guard yaml_parser_initialize(&parser) == 1 else { throw SkillMarkdownError(.inputLimit, "Unable to allocate the YAML scanner.") }
            defer { yaml_parser_delete(&parser) }
            yaml_parser_set_encoding(&parser, YAML_UTF8_ENCODING)
            yaml_parser_set_input_string(&parser, buffer.baseAddress!.assumingMemoryBound(to: UInt8.self), buffer.count)
            var ended = false, tokens = 0
            var previous = YAML_NO_TOKEN
            while !ended {
                tokens += 1
                if tokens % 256 == 0 { try Task.checkCancellation() }
                guard tokens <= limits.maximumNodes * 8 + 1024 else { throw SkillMarkdownError(.nodeLimit, "YAML token budget exceeded.") }
                var token = yaml_token_t()
                guard yaml_parser_scan(&parser, &token) == 1 else { throw failure(parser) }
                defer { yaml_token_delete(&token) }
                if token.type == YAML_SCALAR_TOKEN || token.type == YAML_ALIAS_TOKEN {
                    for (key, candidate) in candidates where Int(token.end_mark.index) == candidate.end && Int(token.start_mark.index) >= candidate.start {
                        let start = globalOffset + (try localOffset(token.start_mark)), end = globalOffset + (try localOffset(token.end_mark))
                        ranges[key] = start..<end
                    }
                }
                if flow, token.type == YAML_FLOW_MAPPING_END_TOKEN, Int(token.start_mark.index) == rootEndCharacterIndex {
                    trailingComma = previous == YAML_FLOW_ENTRY_TOKEN
                }
                previous = token.type
                ended = token.type == YAML_STREAM_END_TOKEN
            }
        }
        return .init(scalarFieldRanges: ranges, rootIsFlow: flow, rootIndent: indent,
                     rootEndOffset: globalOffset + rootEnd, flowHasTrailingComma: trailingComma, anchoredFields: anchoredFields)
    }
}
