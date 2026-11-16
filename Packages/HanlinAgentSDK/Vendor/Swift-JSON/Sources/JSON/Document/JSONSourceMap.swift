// SPDX-License-Identifier: Apache-2.0
/// A half-open range of zero-based byte offsets in owned source bytes.
public struct JSONSourceSpan: Sendable, Equatable {
    /// The included zero-based starting byte offset.
    public let start: UInt64
    /// The excluded zero-based ending byte offset.
    public let end: UInt64
    package init(start: UInt64, end: UInt64) { self.start = start; self.end = end }
}
/// Bounded source spans for values and member keys, addressed by typed paths.
public struct JSONSourceMap: Sendable {
    /// A source range associated with one value or decoded member key.
    public struct Entry: Sendable {
        /// The source token associated with a mapping entry.
        public enum Kind: Sendable {
            /// The byte span of a complete JSON value.
            case value
            /// The byte span of the original encoded object-key token.
            case memberKey
        }
        /// The typed value path for this entry.
        public let path: [JSONLocationComponent]
        /// Whether this entry describes a value or a member-key token.
        public let kind: Kind
        /// The half-open source byte range for this entry.
        public let span: JSONSourceSpan
    }
    /// Owned mapping entries in parser traversal order.
    public let entries: [Entry]
    package init(entries: [Entry]) { self.entries = entries }
    /// Looks up a bounded source span by typed path and entry kind.
    ///
    /// - Returns: The matching half-open byte range, or nil.
    /// - Throws: Resource or configuration failure, or cancellation.
    ///
    /// - Parameters:
    ///   - path: The typed source path.
    ///   - kind: Whether to select a value or member-key token.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public func span(at path: [JSONLocationComponent], kind: Entry.Kind = .value, limits: JSONLimits = .balanced) throws -> JSONSourceSpan? {
        var meter = try JSONWorkMeter(limits: limits, domain: .core)
        return try span(at: path, kind: kind, meter: &meter)
    }
    package func span(at path: [JSONLocationComponent], kind: Entry.Kind = .value, meter: inout JSONWorkMeter) throws -> JSONSourceSpan? {
        for entry in entries {
            try meter.work()
            if entry.kind != kind || entry.path.count != path.count { continue }
            var equal = true
            for (a, b) in zip(entry.path, path) {
                try meter.work()
                switch (a, b) {
                case (.index(let l), .index(let r)): equal = l == r
                case (.key(let l), .key(let r)): equal = try JSONComparison.textEquals(l.string, r.string, meter: &meter)
                default: equal = false
                }
                if !equal { break }
            }
            if equal { return entry.span }
        }
        return nil
    }
}

package struct JSONSourceMapBuilder {
    private struct Frame { let path: [JSONLocationComponent]; let start: UInt64; var nextIndex = 0; var key: JSONKey?; let object: Bool }
    private var stack: [Frame] = []
    private var entries: [JSONSourceMap.Entry] = []
    private mutating func path(meter: inout JSONWorkMeter) throws -> [JSONLocationComponent] {
        guard !stack.isEmpty else { return [] }
        let index = stack.count - 1
        var path: [JSONLocationComponent] = []
        for component in stack[index].path { try meter.work(); try meter.retain(16); path.append(component) }
        try meter.retain(16)
        if stack[index].object {
            guard let key = stack[index].key else { throw JSONFailure(.syntax, code: .invalidOperation) }
            path.append(.key(key)); stack[index].key = nil
        } else { path.append(.index(stack[index].nextIndex)); stack[index].nextIndex += 1 }
        return path
    }
    private mutating func add(path: [JSONLocationComponent], kind: JSONSourceMap.Entry.Kind, start: UInt64, end: UInt64, meter: inout JSONWorkMeter) throws {
        try meter.charge(.sourceMapEntries); try meter.retain(JSONLogicalWeights.sourceMapEntry)
        entries.append(.init(path: path, kind: kind, span: .init(start: start, end: end)))
    }
    package mutating func consume(_ event: JSONMachineEvent, meter: inout JSONWorkMeter) throws {
        try meter.work()
        switch event.kind {
        case .key(let text):
            stack[stack.count - 1].key = try JSONKey(text, meter: &meter)
            var keyPath: [JSONLocationComponent] = []
            for part in stack.last!.path { try meter.work(); try meter.retain(16); keyPath.append(part) }
            try meter.retain(16); keyPath.append(.key(try JSONKey(text, meter: &meter)))
            try add(path: keyPath, kind: .memberKey, start: event.start, end: event.end, meter: &meter)
        case .startObject, .startArray:
            let path = try path(meter: &meter)
            let object: Bool
            if case .startObject = event.kind { object = true } else { object = false }
            try meter.retain(JSONLogicalWeights.frame); stack.append(.init(path: path, start: event.start, object: object))
        case .endObject, .endArray:
            let frame = stack.removeLast(); try meter.release(JSONLogicalWeights.frame)
            try add(path: frame.path, kind: .value, start: frame.start, end: event.end, meter: &meter)
        case .scalar:
            try add(path: path(meter: &meter), kind: .value, start: event.start, end: event.end, meter: &meter)
        }
    }
    package func finish() -> JSONSourceMap { .init(entries: entries) }
}
