// SPDX-License-Identifier: Apache-2.0
package struct JSONMachineEvent: Sendable {
    package enum Kind: Sendable { case startObject, endObject, startArray, endArray, key(String), scalar(JSON) }
    package init(kind: Kind, start: UInt64, end: UInt64) { self.kind = kind; self.start = start; self.end = end }
    package let kind: Kind
    package let start: UInt64
    package let end: UInt64
}

/// One strict grammar for complete bytes and all stream framing adapters.
package struct JSONTokenMachine {
    package enum State: Sendable { case ready, reading, complete, failed, finished }
    private enum Expectation { case objectFirstKey, objectKey, colon, objectValue, objectEnd, arrayFirstValue, arrayValue, arrayEnd }
    private struct Frame { var expectation: Expectation; var count: UInt64 = 0; var keys = JSONExactKeyIndex() }
    private var lexer = JSONLexer()
    private let topLevelArrayStreaming: Bool
    package init(topLevelArrayStreaming: Bool = false, offset: UInt64 = 0) {
        self.topLevelArrayStreaming = topLevelArrayStreaming; self.offset = offset
    }
    private var frames: [Frame] = []
    private var rootStarted = false
    private var rootComplete = false
    package private(set) var offset: UInt64 = 0
    package private(set) var state: State = .ready
    package var hasCompleteRoot: Bool { rootComplete && lexer.idle }
    private var expectingKey: Bool {
        guard let expectation = frames.last?.expectation else { return false }
        return expectation == .objectFirstKey || expectation == .objectKey
    }
    private func failure(_ token: JSONToken, _ code: JSONFailure.Code = .invalidSyntax) -> JSONFailure {
        .init(.syntax, code: code, location: .init(byteOffset: token.start))
    }
    private mutating func beginValue(_ token: JSONToken, meter: inout JSONWorkMeter) throws {
        if frames.isEmpty {
            guard !rootStarted else { throw failure(token, .trailingData) }
            if topLevelArrayStreaming { guard case .leftArray = token.kind else { throw failure(token) } }
            rootStarted = true
        } else {
            let index = frames.count - 1
            switch frames[index].expectation {
            case .objectValue: frames[index].expectation = .objectEnd
            case .arrayFirstValue, .arrayValue:
                let count: UInt64
                if topLevelArrayStreaming && index == 0 {
                    count = try meter.adding(.totalRecords, frames[index].count, 1)
                } else { count = try meter.adding(.arrayItems, frames[index].count, 1) }
                frames[index].count = count; frames[index].expectation = .arrayEnd
            default: throw failure(token)
            }
        }
        if !topLevelArrayStreaming || !frames.isEmpty { try meter.charge(.nodes) }
        if meter.domain == .streaming { try meter.charge(.totalScannedNodes) }
    }
    private mutating func accept(_ token: JSONToken, meter: inout JSONWorkMeter) throws -> JSONMachineEvent? {
        switch token.kind {
        case .comma:
            guard !frames.isEmpty else { throw failure(token) }
            let index = frames.count - 1
            switch frames[index].expectation {
            case .objectEnd: frames[index].expectation = .objectKey
            case .arrayEnd: frames[index].expectation = .arrayValue
            default: throw failure(token)
            }
            return nil
        case .colon:
            guard frames.last?.expectation == .colon else { throw failure(token) }
            frames[frames.count - 1].expectation = .objectValue; return nil
        case .rightObject, .rightArray:
            guard let frame = frames.last else { throw failure(token) }
            let object: Bool
            if case .rightObject = token.kind { object = true } else { object = false }
            if object {
                guard frame.expectation == .objectFirstKey || frame.expectation == .objectEnd else { throw failure(token) }
            } else {
                guard frame.expectation == .arrayFirstValue || frame.expectation == .arrayEnd else { throw failure(token) }
            }
            frames.removeLast(); try meter.release(JSONLogicalWeights.frame)
            // Key payload remains in a materialized value or in the caller's event; index slots are grammar-owned.
            try meter.release(frame.keys.retainedBytes)
            if frames.isEmpty { rootComplete = true; state = .complete }
            return .init(kind: object ? .endObject : .endArray, start: token.start, end: token.end)
        case .string(let text) where expectingKey:
            let index = frames.count - 1
            let key = try JSONKey(text, meter: &meter)
            guard try frames[index].keys.insert(key, position: Int(frames[index].count), meter: &meter) else {
                throw failure(token, .duplicateKey)
            }
            frames[index].count = try meter.adding(.objectMembers, frames[index].count, 1)
            frames[index].expectation = .colon
            return .init(kind: .key(text), start: token.start, end: token.end)
        case .leftObject, .leftArray:
            try beginValue(token, meter: &meter)
            try meter.require(.maxDepth, UInt64(frames.count) + 1)
            try meter.retain(JSONLogicalWeights.frame)
            let object: Bool
            if case .leftObject = token.kind { object = true } else { object = false }
            frames.append(Frame(expectation: object ? .objectFirstKey : .arrayFirstValue))
            state = .reading
            return .init(kind: object ? .startObject : .startArray, start: token.start, end: token.end)
        default:
            try beginValue(token, meter: &meter)
            let value: JSON
            switch token.kind {
            case .string(let text): value = .string(text)
            case .number(let number): value = .number(number)
            case .boolean(let boolean): value = .boolean(boolean)
            case .null: value = .null
            default: throw failure(token)
            }
            if frames.isEmpty { rootComplete = true; state = .complete }
            return .init(kind: .scalar(value), start: token.start, end: token.end)
        }
    }
    /// Returns at most one provisional event; caller owns the chunk and cursor.
    package mutating func next(in bytes: [UInt8], index: inout Int, through end: Int? = nil, meter: inout JSONWorkMeter) throws -> JSONMachineEvent? {
        guard state != .failed && state != .finished else { throw JSONFailure(.syntax, code: .invalidOperation) }
        do {
            while index < (end ?? bytes.count) {
                try meter.work()
                if !topLevelArrayStreaming { try meter.require(.inputBytes, try meter.adding(.inputBytes, meter.used(.inputBytes), 1)) }
                let (token, consumed) = try lexer.feed(bytes[index], offset: offset, isKey: expectingKey, meter: &meter)
                if consumed { if !topLevelArrayStreaming { try meter.charge(.inputBytes) }; index += 1; offset += 1 }
                if let token, let event = try accept(token, meter: &meter) { return event }
            }
            return nil
        } catch { state = .failed; throw error }
    }
    package mutating func finish(meter: inout JSONWorkMeter) throws -> JSONMachineEvent? {
        guard state != .failed else { throw JSONFailure(.syntax, code: .invalidOperation) }
        if state == .finished { return nil }
        do {
            try meter.checkpoint()
            if let token = try lexer.finish(offset: offset, meter: &meter) { return try accept(token, meter: &meter) }
            guard rootComplete && frames.isEmpty else { throw JSONFailure(.syntax, code: .unexpectedEOF, location: .init(byteOffset: offset)) }
            state = .finished; return nil
        } catch { state = .failed; throw error }
    }
}

package struct JSONValueAssembler {
    private struct Frame { var object: Bool; var key: JSONKey?; var members: [JSONMember] = []; var values: [JSON] = []; var index = JSONExactKeyIndex() }
    private var stack: [Frame] = []
    package init() {}
    package mutating func consume(_ event: JSONMachineEvent, meter: inout JSONWorkMeter) throws -> JSON? {
        try meter.work()
        switch event.kind {
        case .startObject, .startArray:
            try meter.retain(JSONLogicalWeights.node + JSONLogicalWeights.frame)
            let object: Bool
            if case .startObject = event.kind { object = true } else { object = false }
            stack.append(Frame(object: object)); return nil
        case .key(let key):
            let last = stack.count - 1
            let key = try JSONKey(key, meter: &meter)
            guard try stack[last].index.insert(key, position: stack[last].members.count, meter: &meter) else { throw JSONFailure(.syntax, code: .duplicateKey) }
            stack[last].key = key; return nil
        case .endObject, .endArray:
            let frame = stack.removeLast(); try meter.release(JSONLogicalWeights.frame)
            let value: JSON = frame.object ? .object(JSONObject(admitted: frame.members, index: frame.index)) : .array(frame.values)
            return try add(value, meter: &meter)
        case .scalar(let value):
            try meter.retain(JSONLogicalWeights.node)
            return try add(value, meter: &meter)
        }
    }
    private mutating func add(_ value: JSON, meter: inout JSONWorkMeter) throws -> JSON? {
        guard !stack.isEmpty else { return value }
        let index = stack.count - 1
        if stack[index].object {
            guard let key = stack[index].key else { throw JSONFailure(.syntax, code: .invalidOperation) }
            try meter.retain(JSONLogicalWeights.member)
            stack[index].members.append(JSONMember(key, value: value)); stack[index].key = nil
        } else { try meter.retain(JSONLogicalWeights.arraySlot); stack[index].values.append(value) }
        return nil
    }
}
