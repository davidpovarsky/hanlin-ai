// SPDX-License-Identifier: Apache-2.0
import JSON

/// Stateless exact assertions. Compositions, applicability and evaluated locations belong to the frame engine.
package enum JSONSchemaAssertions {
    package typealias Keyword = JSONSchemaPlan.Keyword
    private static func type(_ text: String, instance: JSON, meter: inout JSONWorkMeter) throws -> Bool {
        for _ in text.utf8 { try meter.work() }
        switch text {
        case "null": return instance.isNull
        case "boolean": return instance.booleanValue != nil
        case "object": return instance.objectValue != nil
        case "array": return instance.arrayValue != nil
        case "string": return instance.stringValue != nil
        case "number": return instance.numberValue != nil
        case "integer": return instance.numberValue?.isInteger ?? false
        default: throw JSONSchemaEvaluationFailure(.backend)
        }
    }
    private static func count(_ count: Int, bound: JSONNumber, minimum: Bool, meter: inout JSONWorkMeter) throws -> Bool {
        // A native Int has at most 19 decimal digits. Charge the bounded conversion before calling it.
        try meter.work(20, subsystem: .numericWorkUnits)
        let comparison = try JSONNumber(integer: count).compare(to: bound, meter: &meter)
        return minimum ? comparison != .orderedAscending : comparison != .orderedDescending
    }
    package static func test(_ keyword: Keyword, declaration: JSON, instance: JSON, meter: inout JSONWorkMeter) throws -> Bool {
        try meter.work()
        switch keyword {
        case .type:
            if let text = declaration.stringValue { return try type(text, instance: instance, meter: &meter) }
            for item in declaration.arrayValue! { if try type(item.stringValue!, instance: instance, meter: &meter) { return true } }
            return false
        case .const: return try JSONComparison.equals(declaration, instance, meter: &meter)
        case .enum:
            for value in declaration.arrayValue! { try meter.work(); if try JSONComparison.equals(value, instance, meter: &meter) { return true } }
            return false
        case .minimum, .maximum, .exclusiveMinimum, .exclusiveMaximum:
            guard let number = instance.numberValue else { return true }
            let comparison = try number.compare(to: declaration.numberValue!, meter: &meter)
            switch keyword {
            case .minimum: return comparison != .orderedAscending
            case .maximum: return comparison != .orderedDescending
            case .exclusiveMinimum: return comparison == .orderedDescending
            default: return comparison == .orderedAscending
            }
        case .multipleOf:
            guard let number = instance.numberValue else { return true }
            return try number.isMultiple(of: declaration.numberValue!, meter: &meter)
        case .minLength, .maxLength:
            guard let text = instance.stringValue else { return true }
            var length = 0
            for _ in text.unicodeScalars { try meter.work(); length += 1 }
            return try count(length, bound: declaration.numberValue!, minimum: keyword == .minLength, meter: &meter)
        case .minItems, .maxItems:
            guard let array = instance.arrayValue else { return true }
            return try count(array.count, bound: declaration.numberValue!, minimum: keyword == .minItems, meter: &meter)
        case .minProperties, .maxProperties:
            guard let object = instance.objectValue else { return true }
            return try count(object.count, bound: declaration.numberValue!, minimum: keyword == .minProperties, meter: &meter)
        case .required:
            guard let object = instance.objectValue else { return true }
            for name in declaration.arrayValue! {
                try meter.work(); if try object.lookup(name.stringValue!, meter: &meter) == nil { return false }
            }
            return true
        case .dependentRequired:
            guard let object = instance.objectValue else { return true }
            for member in declaration.objectValue! {
                try meter.work()
                if try object.lookup(member.key.string, meter: &meter) != nil {
                    for name in member.value.arrayValue! {
                        try meter.work(); if try object.lookup(name.stringValue!, meter: &meter) == nil { return false }
                    }
                }
            }
            return true
        case .uniqueItems:
            guard declaration.booleanValue == true, let array = instance.arrayValue else { return true }
            for i in array.indices {
                for j in (i+1)..<array.count {
                    try meter.work(); if try JSONComparison.equals(array[i], array[j], meter: &meter) { return false }
                }
            }
            return true
        default: return true
        }
    }
}
