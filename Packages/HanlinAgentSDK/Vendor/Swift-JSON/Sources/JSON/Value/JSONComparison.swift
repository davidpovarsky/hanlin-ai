// SPDX-License-Identifier: Apache-2.0
package enum JSONAdmission {
    package static func text(_ text: String, key: Bool = false, meter: inout JSONWorkMeter, owned: Bool = false) throws {
        var count: UInt64 = 0
        for _ in text.utf8 {
            try meter.work(); count += 1
            try meter.require(key ? .keyBytes : .stringBytes, count)
            try meter.charge(.aggregateTextBytes)
            if owned { try meter.retain(1) }
        }
    }
    package static func value(_ value: JSON, meter: inout JSONWorkMeter, owned: Bool = false, depth: UInt64 = 0) throws {
        var stack: [(JSON, UInt64)] = []
        try meter.retain(JSONLogicalWeights.frame); stack.append((value, depth))
        while let (value, parentDepth) = stack.popLast() {
            try meter.release(JSONLogicalWeights.frame)
            try meter.work(); try meter.charge(.nodes)
            if owned { try meter.retain(JSONLogicalWeights.node) }
            switch value {
            case .null, .boolean: break
            case .string(let string): try text(string, meter: &meter, owned: owned)
            case .number(let number):
                let c = number.components
                try meter.require(.numberDigits, UInt64(c.digits.count))
                try meter.require(.absoluteExponent, c.exponent.magnitude)
                for _ in c.digits { try meter.work(subsystem: .numericWorkUnits); if owned { try meter.retain(1) } }
                if let lexeme = number.originalLexeme {
                    var bytes: UInt64 = 0
                    for _ in lexeme.utf8 {
                        try meter.work(subsystem: .numericWorkUnits); bytes += 1
                        try meter.require(.numberTokenBytes, bytes)
                        if owned { try meter.retain(1) }
                    }
                }
            case .array(let values):
                let containerDepth = try meter.adding(.maxDepth, parentDepth, 1)
                try meter.require(.arrayItems, UInt64(values.count))
                for value in values.reversed() {
                    try meter.work(); try meter.retain(JSONLogicalWeights.frame)
                    if owned { try meter.retain(JSONLogicalWeights.arraySlot) }
                    stack.append((value, containerDepth))
                }
            case .object(let object):
                let containerDepth = try meter.adding(.maxDepth, parentDepth, 1)
                try meter.require(.objectMembers, UInt64(object.count))
                if owned { try meter.retain(object.exactIndex.retainedBytes) }
                for member in object.reversed() {
                    try text(member.key.string, key: true, meter: &meter, owned: owned)
                    try meter.work(); try meter.retain(JSONLogicalWeights.frame)
                    if owned { try meter.retain(JSONLogicalWeights.member) }
                    stack.append((member.value, containerDepth))
                }
            }
        }
    }
}

/// Explicitly budgeted deep equality for untrusted exact JSON values.
public enum JSONComparison {
    /// Compares admitted values with cumulative traversal, text and numeric budgets.
    ///
    /// Object order is ignored; string/key scalars and decimal mathematics are exact.
    /// - Returns: Semantic equality.
    /// - Throws: Resource or configuration failure, or cancellation.
    ///
    /// - Parameters:
    ///   - lhs: The left value.
    ///   - rhs: The right value.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public static func equals(_ lhs: JSON, _ rhs: JSON, limits: JSONLimits = .balanced) throws -> Bool {
        var meter = try JSONWorkMeter(limits: limits, domain: .core)
        try JSONAdmission.value(lhs, meter: &meter)
        try JSONAdmission.value(rhs, meter: &meter)
        return try equals(lhs, rhs, meter: &meter)
    }
    package static func textEquals(_ lhs: String, _ rhs: String, meter: inout JSONWorkMeter) throws -> Bool {
        var l = lhs.utf8.makeIterator(), r = rhs.utf8.makeIterator()
        while true {
            try meter.work()
            let a = l.next(), b = r.next()
            if a != b { return false }
            if a == nil { return true }
        }
    }
    package static func equals(_ lhs: JSON, _ rhs: JSON, meter: inout JSONWorkMeter) throws -> Bool {
        var stack: [(JSON, JSON)] = []
        try meter.retain(JSONLogicalWeights.frame); stack.append((lhs, rhs))
        func run(meter: inout JSONWorkMeter) throws -> Bool {
        while let (a, b) = stack.popLast() {
            try meter.release(JSONLogicalWeights.frame); try meter.work()
            switch (a, b) {
            case (.null, .null): break
            case (.boolean(let l), .boolean(let r)): if l != r { return false }
            case (.number(let l), .number(let r)):
                if try l.compare(to: r, meter: &meter) != .orderedSame { return false }
            case (.string(let l), .string(let r)):
                if try !textEquals(l, r, meter: &meter) { return false }
            case (.array(let l), .array(let r)):
                if l.count != r.count { return false }
                for index in l.indices {
                    try meter.work(); try meter.retain(JSONLogicalWeights.frame); stack.append((l[index], r[index]))
                }
            case (.object(let l), .object(let r)):
                if l.count != r.count { return false }
                for member in l {
                    guard let other = try r.lookup(member.key.string, meter: &meter) else { return false }
                    try meter.work(); try meter.retain(JSONLogicalWeights.frame); stack.append((member.value, other))
                }
            default: return false
            }
        }
        return true
        }
        let result = try run(meter: &meter)
        while stack.popLast() != nil { try meter.release(JSONLogicalWeights.frame); try meter.checkpoint() }
        return result
    }
}
