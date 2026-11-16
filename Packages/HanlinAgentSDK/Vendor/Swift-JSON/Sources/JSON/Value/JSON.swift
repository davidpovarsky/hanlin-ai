// SPDX-License-Identifier: Apache-2.0
// Value cases selectively adapted from RhoeJSON Core/JSONValue.swift.
// Copyright 2024-2026 Thor Fuchs. Licensed under Apache-2.0.
/// An exact JSON value with scalar text identity and mathematical decimal equality.
///
/// Object equality ignores insertion order. Direct cases admit trusted caller values;
/// bounded operations charge and validate them on entry. Ordinary equality and hashing
/// are unmetered; use `JSONComparison` for bounded comparison of untrusted values.
public indirect enum JSON: Sendable, Hashable {
    /// An ordered exact-key object.
    case object(JSONObject)
    /// An ordered array of JSON values.
    case array([JSON])
    /// Text whose equality uses decoded Unicode scalar spelling.
    case string(String)
    /// An exact bounded decimal value.
    case number(JSONNumber)
    /// A Boolean value.
    case boolean(Bool)
    /// The JSON null value.
    case null

    /// Compares semantic identity without a throwing work budget.
    ///
    /// - Parameters:
    ///   - lhs: The left value.
    ///   - rhs: The right value.
    public static func == (lhs: JSON, rhs: JSON) -> Bool {
        var pending = [(lhs, rhs)]
        while let (a, b) = pending.popLast() {
            switch (a, b) {
            case (.null, .null): break
            case (.boolean(let l), .boolean(let r)): if l != r { return false }
            case (.number(let l), .number(let r)): if l != r { return false }
            case (.string(let l), .string(let r)): if !l.utf8.elementsEqual(r.utf8) { return false }
            case (.array(let l), .array(let r)):
                if l.count != r.count { return false }
                for index in l.indices { pending.append((l[index], r[index])) }
            case (.object(let l), .object(let r)):
                if l.count != r.count { return false }
                for member in l {
                    guard let other = r[member.key] else { return false }
                    pending.append((member.value, other))
                }
            default: return false
            }
        }
        return true
    }
    /// Hashes semantic identity; the randomized result is not a persistent digest.
    ///
    /// This protocol operation has no throwing work budget.
    ///
    /// - Parameters:
    ///   - hasher: The caller's randomized Swift hasher.
    public func hash(into hasher: inout Hasher) {
        enum Step { case value(JSON), key(JSONKey) }
        var pending: [Step] = [.value(self)]
        while let step = pending.popLast() {
            switch step {
            case .key(let key): hasher.combine(key)
            case .value(let value):
                switch value {
                case .null: hasher.combine(0)
                case .boolean(let boolean): hasher.combine(1); hasher.combine(boolean)
                case .number(let number): hasher.combine(2); hasher.combine(number)
                case .string(let text):
                    hasher.combine(3); hasher.combine(text.utf8.count)
                    for byte in text.utf8 { hasher.combine(byte) }
                case .array(let values):
                    hasher.combine(4); hasher.combine(values.count)
                    for value in values.reversed() { pending.append(.value(value)) }
                case .object(let object):
                    hasher.combine(5); hasher.combine(object.count)
                    let sorted = object.members.sorted { $0.key.string.utf8.lexicographicallyPrecedes($1.key.string.utf8) }
                    for member in sorted.reversed() { pending.append(.value(member.value)); pending.append(.key(member.key)) }
                }
            }
        }
    }
}
