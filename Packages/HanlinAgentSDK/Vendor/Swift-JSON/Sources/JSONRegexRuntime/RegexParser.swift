// SPDX-License-Identifier: Apache-2.0
import JSON

/// Explicit grammar stack, with indexed nodes rather than recursive owned trees.
package struct RegexParser {
    package struct Node {
        package enum Kind {
            case instruction(RegexProgram.Instruction), sequence([Int]), alternate([Int])
            case capture(Int, Int), repetition(Int, UInt64, UInt64, Bool)
            case assertion(Int, Bool, Bool), namedReference(JSONKey)
        }
        package let kind: Kind
        package let captures: Range<Int>
        package let quantifiable: Bool
    }
    private enum Group { case root, plain, capture(Int), assertion(backwards: Bool, negative: Bool) }
    private struct Frame {
        var sequence: [Int] = []
        var alternatives: [Int] = []
        let group: Group
        let firstCapture: Int
    }
    package var nodes: [Node] = []
    package var classes: [RegexProgram.CharacterClass] = []
    package var captureCount = 0
    package var temporaryBytes: UInt64 = 0
    private var names: [(JSONKey, Int)] = []
    private var input: [UInt32] = []
    private var index = 0
    private var frames: [Frame] = []

    private mutating func allocate(_ bytes: UInt64, meter: inout JSONWorkMeter) throws {
        try meter.retain(bytes); temporaryBytes += bytes
    }
    private mutating func node(_ kind: Node.Kind, captures: Range<Int>? = nil, quantifiable: Bool = true,
                               meter: inout JSONWorkMeter) throws -> Int {
        try RegexBudget.compileStep(meter: &meter); try allocate(32, meter: &meter)
        nodes.append(.init(kind: kind, captures: captures ?? captureCount..<captureCount, quantifiable: quantifiable))
        return nodes.count - 1
    }
    private mutating func append(_ id: Int, meter: inout JSONWorkMeter) throws {
        try allocate(8, meter: &meter); frames[frames.count - 1].sequence.append(id)
    }
    private mutating func sequence(meter: inout JSONWorkMeter) throws -> Int {
        let i = frames.count - 1
        let ids = frames[i].sequence; frames[i].sequence = []
        // Slots move from the frame into the indexed AST; no new logical ownership.
        let first = ids.first.map { nodes[$0].captures.lowerBound } ?? captureCount
        let last = ids.last.map { nodes[$0].captures.upperBound } ?? first
        return try node(.sequence(ids), captures: first..<last, meter: &meter)
    }
    private mutating func finish(meter: inout JSONWorkMeter) throws -> Int {
        let sequenceID = try sequence(meter: &meter)
        let i = frames.count - 1
        if frames[i].alternatives.isEmpty { return sequenceID }
        try allocate(8, meter: &meter); frames[i].alternatives.append(sequenceID)
        let ids = frames[i].alternatives; frames[i].alternatives = []
        return try node(.alternate(ids), captures: frames[i].firstCapture..<captureCount, meter: &meter)
    }
    private func peek(_ offset: Int = 0) -> UInt32? { index + offset < input.count ? input[index + offset] : nil }
    private mutating func take(meter: inout JSONWorkMeter) throws -> UInt32 {
        try RegexBudget.compileStep(meter: &meter)
        guard let value = peek() else { throw RegexFailure.invalidPattern }
        index += 1; return value
    }
    private static func hex(_ value: UInt32) -> UInt32? {
        switch value { case 48...57: value - 48; case 65...70: value - 55; case 97...102: value - 87; default: nil }
    }
    private mutating func hexDigits(_ count: Int, meter: inout JSONWorkMeter) throws -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<count {
            guard let digit = Self.hex(try take(meter: &meter)) else { throw RegexFailure.invalidPattern }
            value = value * 16 + digit
        }
        return value
    }
    private mutating func name(meter: inout JSONWorkMeter) throws -> JSONKey {
        var result = String.UnicodeScalarView(), first = true
        guard let startID = try RegexUnicodeTables.resolve("ID_Start", meter: &meter),
              let continueID = try RegexUnicodeTables.resolve("ID_Continue", meter: &meter) else { throw RegexFailure.invalidPattern }
        while let next = peek(), next != 62 {
            var value = try take(meter: &meter)
            if value == 92 {
                guard peek() == 117, case .scalar(let scalar) = try escape(inClass: false, meter: &meter) else { throw RegexFailure.invalidPattern }
                value = scalar
            }
            let special = value == 36 || value == 95 || (!first && (value == 0x200c || value == 0x200d))
            guard let scalar = Unicode.Scalar(value) else { throw RegexFailure.invalidPattern }
            if !special { if try !RegexUnicodeTables.contains(first ? startID : continueID, value, compiling: true, meter: &meter) { throw RegexFailure.invalidPattern } }
            try allocate(UInt64(scalar.utf8.count), meter: &meter)
            result.append(scalar); first = false
        }
        guard !first, try take(meter: &meter) == 62 else { throw RegexFailure.invalidPattern }
        return try JSONKey(String(result), meter: &meter, subsystem: .regexCompileWorkUnits)
    }
    private func namesEqual(_ lhs: JSONKey, _ rhs: JSONKey, meter: inout JSONWorkMeter) throws -> Bool {
        var a = lhs.string.utf8.makeIterator(), b = rhs.string.utf8.makeIterator()
        while true {
            try RegexBudget.compileStep(meter: &meter)
            let x = a.next(), y = b.next()
            if x != y { return false }; if x == nil { return true }
        }
    }
    private enum Escape { case scalar(UInt32), part(RegexProgram.CharacterClass.Part), boundary(Bool), reference(Int), named(JSONKey) }
    private mutating func escape(inClass: Bool, meter: inout JSONWorkMeter) throws -> Escape {
        let escaped = try take(meter: &meter)
        switch escaped {
        case 100: return .part(.digit(invert: false))
        case 68: return .part(.digit(invert: true))
        case 119: return .part(.word(invert: false))
        case 87: return .part(.word(invert: true))
        case 115: return .part(.space(invert: false))
        case 83: return .part(.space(invert: true))
        case 98: return inClass ? .scalar(8) : .boundary(false)
        case 66: guard !inClass else { throw RegexFailure.invalidPattern }; return .boundary(true)
        case 110: return .scalar(10)
        case 114: return .scalar(13)
        case 116: return .scalar(9)
        case 102: return .scalar(12)
        case 118: return .scalar(11)
        case 99:
            let letter = try take(meter: &meter)
            guard (65...90).contains(letter) || (97...122).contains(letter) else { throw RegexFailure.invalidPattern }
            return .scalar(letter % 32)
        case 120: return .scalar(try hexDigits(2, meter: &meter))
        case 117:
            var value: UInt32
            if peek() == 123 {
                index += 1; var digits = 0; value = 0
                while let next = peek(), next != 125 {
                    guard let h = Self.hex(try take(meter: &meter)), value <= 0x10ffff / 16 else { throw RegexFailure.invalidPattern }
                    value = value * 16 + h; digits += 1
                }
                guard digits > 0, value <= 0x10ffff, try take(meter: &meter) == 125 else { throw RegexFailure.invalidPattern }
            } else {
                value = try hexDigits(4, meter: &meter)
                if (0xd800...0xdbff).contains(value), peek() == 92, peek(1) == 117, peek(2) != 123, index + 6 <= input.count {
                    var low: UInt32 = 0, valid = true
                    for offset in 2..<6 {
                        try RegexBudget.compileStep(meter: &meter)
                        if let h = Self.hex(input[index + offset]) { low = low * 16 + h } else { valid = false }
                    }
                    if valid && (0xdc00...0xdfff).contains(low) { value = 0x10000 + (value - 0xd800) * 1024 + low - 0xdc00; index += 6 }
                }
            }
            return .scalar(value)
        case 48:
            guard !(peek().map { (48...57).contains($0) } ?? false) else { throw RegexFailure.invalidPattern }
            return .scalar(0)
        case 49...57:
            guard !inClass else { throw RegexFailure.invalidPattern }
            var number = Int(escaped - 48)
            while let digit = peek(), (48...57).contains(digit) {
                _ = try take(meter: &meter)
                let (product, a) = number.multipliedReportingOverflow(by: 10)
                let (next, b) = product.addingReportingOverflow(Int(digit - 48))
                guard !a && !b else { throw RegexFailure.invalidPattern }; number = next
            }
            return .reference(number - 1)
        case 107:
            guard !inClass, try take(meter: &meter) == 60 else { throw RegexFailure.invalidPattern }
            return .named(try name(meter: &meter))
        case 112, 80:
            guard try take(meter: &meter) == 123 else { throw RegexFailure.invalidPattern }
            var property = String.UnicodeScalarView()
            while let value = peek(), value != 125 {
                _ = try take(meter: &meter)
                guard value == 95 || value == 61 || (48...57).contains(value) || (65...90).contains(value) || (97...122).contains(value) else { throw RegexFailure.invalidPattern }
                try allocate(1, meter: &meter); property.append(Unicode.Scalar(value)!)
            }
            guard try take(meter: &meter) == 125, let id = try RegexUnicodeTables.resolve(String(property), meter: &meter) else { throw RegexFailure.invalidPattern }
            return .part(.property(id, invert: escaped == 80))
        case 94,36,92,46,42,43,63,40,41,91,93,123,125,124,47: return .scalar(escaped)
        case 45 where inClass: return .scalar(escaped)
        default: throw RegexFailure.invalidPattern
        }
    }
    private mutating func classAtom(meter: inout JSONWorkMeter) throws -> Escape {
        let scalar = try take(meter: &meter)
        if scalar == 92 { return try escape(inClass: true, meter: &meter) }
        return .scalar(scalar)
    }
    private mutating func characterClass(meter: inout JSONWorkMeter) throws -> Int {
        let inverted = peek() == 94
        if inverted { _ = try take(meter: &meter) }
        var parts: [RegexProgram.CharacterClass.Part] = []
        func part(_ escaped: Escape) throws -> RegexProgram.CharacterClass.Part {
            switch escaped { case .scalar(let c): return .range(c,c); case .part(let p): return p; default: throw RegexFailure.invalidPattern }
        }
        while let next = peek(), next != 93 {
            let left = try classAtom(meter: &meter)
            var item = try part(left)
            if peek() == 45, peek(1) != 93, peek(1) != nil {
                _ = try take(meter: &meter); let right = try classAtom(meter: &meter)
                guard case .scalar(let lo) = left, case .scalar(let hi) = right, lo <= hi else { throw RegexFailure.invalidPattern }
                item = .range(lo, hi)
            }
            try allocate(16, meter: &meter); parts.append(item)
        }
        guard try take(meter: &meter) == 93 else { throw RegexFailure.invalidPattern }
        // Class contents are retained by the final program, unlike the parser's AST.
        try allocate(16, meter: &meter); classes.append(.init(inverted: inverted, parts: parts))
        return classes.count - 1
    }
    /// Saturation preserves executable semantics: reaching 2^64 iterations is impossible within finite work.
    /// Exact lexical comparison below still rejects descending ranges of arbitrarily large counts.
    private mutating func count(meter: inout JSONWorkMeter) throws -> (UInt64, Range<Int>) {
        let start = index; var value: UInt64 = 0
        while let digit = peek(), (48...57).contains(digit) {
            _ = try take(meter: &meter)
            let (product, a) = value.multipliedReportingOverflow(by: 10)
            let (next, b) = product.addingReportingOverflow(UInt64(digit - 48))
            value = a || b ? .max : next
        }
        guard index > start else { throw RegexFailure.invalidPattern }
        return (value, start..<index)
    }
    private func greater(_ lhs: Range<Int>, _ rhs: Range<Int>, meter: inout JSONWorkMeter) throws -> Bool {
        var a = lhs.lowerBound, b = rhs.lowerBound
        while a + 1 < lhs.upperBound && input[a] == 48 { try RegexBudget.compileStep(meter: &meter); a += 1 }
        while b + 1 < rhs.upperBound && input[b] == 48 { try RegexBudget.compileStep(meter: &meter); b += 1 }
        let na = lhs.upperBound - a, nb = rhs.upperBound - b
        if na != nb { return na > nb }
        for offset in 0..<na { try RegexBudget.compileStep(meter: &meter); if input[a+offset] != input[b+offset] { return input[a+offset] > input[b+offset] } }
        return false
    }
    private mutating func quantify(_ id: Int, meter: inout JSONWorkMeter) throws -> Int {
        var minimum: UInt64, maximum: UInt64
        switch peek() {
        case 42: index += 1; minimum = 0; maximum = .max
        case 43: index += 1; minimum = 1; maximum = .max
        case 63: index += 1; minimum = 0; maximum = 1
        case 123:
            index += 1; let lower = try count(meter: &meter); minimum = lower.0
            if peek() == 44 {
                index += 1
                if peek() == 125 { maximum = .max }
                else { let upper = try count(meter: &meter); guard try !greater(lower.1, upper.1, meter: &meter) else { throw RegexFailure.invalidPattern }; maximum = upper.0 }
            } else { maximum = minimum }
            guard try take(meter: &meter) == 125 else { throw RegexFailure.invalidPattern }
        default: return id
        }
        guard nodes[id].quantifiable else { throw RegexFailure.invalidPattern }
        let greedy = peek() != 63
        if !greedy { _ = try take(meter: &meter) }
        return try node(.repetition(id, minimum, maximum, greedy), captures: nodes[id].captures, quantifiable: false, meter: &meter)
    }
    package mutating func parse(_ pattern: String, meter: inout JSONWorkMeter) throws -> Int {
        var bytes: UInt64 = 0
        for _ in pattern.utf8 { try RegexBudget.compileStep(meter: &meter); bytes += 1; try meter.require(.regexPatternBytes, bytes); try meter.charge(.aggregateRegexPatternBytes) }
        for scalar in pattern.unicodeScalars { try RegexBudget.compileStep(meter: &meter); try allocate(4, meter: &meter); input.append(scalar.value) }
        try meter.require(.maxDepth, 1); try allocate(16, meter: &meter); frames.append(.init(group: .root, firstCapture: 0))
        while let scalar = peek() {
            _ = try take(meter: &meter)
            if scalar == 124 {
                let id = try sequence(meter: &meter); try allocate(8, meter: &meter); frames[frames.count-1].alternatives.append(id); continue
            }
            if scalar == 40 {
                var group: Group = .plain; let first = captureCount
                if peek() == 63 {
                    _ = try take(meter: &meter)
                    switch try take(meter: &meter) {
                    case 58: group = .plain
                    case 61: group = .assertion(backwards: false, negative: false)
                    case 33: group = .assertion(backwards: false, negative: true)
                    case 60:
                        if peek() == 61 || peek() == 33 { group = .assertion(backwards: true, negative: try take(meter: &meter) == 33) }
                        else {
                            let key = try name(meter: &meter)
                            for (existing, _) in names { if try namesEqual(existing, key, meter: &meter) { throw RegexFailure.invalidPattern } }
                            try allocate(16, meter: &meter); names.append((key, captureCount)); group = .capture(captureCount); captureCount += 1
                        }
                    default: throw RegexFailure.invalidPattern
                    }
                } else { group = .capture(captureCount); captureCount += 1 }
                try meter.require(.regexCaptureGroups, UInt64(captureCount)); try meter.require(.maxDepth, UInt64(frames.count+1))
                try allocate(16, meter: &meter); frames.append(.init(group: group, firstCapture: first)); continue
            }
            var id: Int
            if scalar == 41 {
                guard frames.count > 1 else { throw RegexFailure.invalidPattern }
                let child = try finish(meter: &meter); let frame = frames.removeLast()
                try meter.release(16); temporaryBytes -= 16
                switch frame.group {
                case .plain: id = child
                case .capture(let group): id = try node(.capture(group, child), captures: frame.firstCapture..<captureCount, meter: &meter)
                case .assertion(let backwards, let negative): id = try node(.assertion(child, backwards, negative), captures: frame.firstCapture..<captureCount, quantifiable: false, meter: &meter)
                case .root: throw RegexFailure.invalidPattern
                }
            } else {
                switch scalar {
                case 94: id = try node(.instruction(.start), quantifiable: false, meter: &meter)
                case 36: id = try node(.instruction(.end), quantifiable: false, meter: &meter)
                case 46: id = try node(.instruction(.anyExceptLineTerminator), meter: &meter)
                case 91: id = try node(.instruction(.bracket(try characterClass(meter: &meter))), meter: &meter)
                case 92:
                    switch try escape(inClass: false, meter: &meter) {
                    case .scalar(let c): id = try node(.instruction(.character(c)), meter: &meter)
                    case .boundary(let invert): id = try node(.instruction(.wordBoundary(invert: invert)), quantifiable: false, meter: &meter)
                    case .reference(let group): id = try node(.instruction(.backreference(group)), meter: &meter)
                    case .named(let key): id = try node(.namedReference(key), meter: &meter)
                    case .part(let part):
                        try allocate(32, meter: &meter); classes.append(.init(inverted: false, parts: [part])); id = try node(.instruction(.bracket(classes.count - 1)), meter: &meter)
                    }
                case 42,43,63,123,125,93: throw RegexFailure.invalidPattern
                default: id = try node(.instruction(.character(scalar)), meter: &meter)
                }
            }
            id = try quantify(id, meter: &meter); try append(id, meter: &meter)
        }
        guard frames.count == 1 else { throw RegexFailure.invalidPattern }
        let root = try finish(meter: &meter)
        for i in nodes.indices {
            try RegexBudget.compileStep(meter: &meter)
            switch nodes[i].kind {
            case .instruction(.backreference(let id)):
                guard id < captureCount else { throw RegexFailure.invalidPattern }
            case .namedReference(let key):
                var group: Int?
                for (existing, id) in names { if try namesEqual(existing, key, meter: &meter) { group = id; break } }
                guard let group else { throw RegexFailure.invalidPattern }
                nodes[i] = .init(kind: .instruction(.backreference(group)), captures: nodes[i].captures, quantifiable: true)
            default: break
            }
        }
        return root
    }
}
