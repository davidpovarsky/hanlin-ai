// SPDX-License-Identifier: Apache-2.0
import JSON

/// Trusted bootstrap grammar for standard keyword shapes; never a replacement for meta-schema evaluation.
package enum JSONSchemaShape {
    package static func validate(_ keyword: JSONSchemaPlan.Keyword, value: JSON, location: JSONPointer,
                                 meter: inout JSONWorkMeter) throws {
        func fail() -> JSONSchemaCompilationFailure { .init(.schemaSyntax, location: location) }
        func schema(_ value: JSON) throws { switch value { case .boolean, .object: break; default: throw fail() } }
        func strings(_ value: JSON, types: Bool = false) throws {
            guard let array = value.arrayValue, !types || !array.isEmpty else { throw fail() }
            var previous: [String] = []
            for entry in array {
                try meter.work(); guard let text = entry.stringValue else { throw fail() }
                if types { try type(text) }
                for other in previous { if try JSONComparison.textEquals(other, text, meter: &meter) { throw fail() } }
                try meter.retain(JSONLogicalWeights.arraySlot); previous.append(text)
            }
            try meter.release(UInt64(previous.count) * JSONLogicalWeights.arraySlot)
        }
        func type(_ text: String) throws {
            let names = ["null", "boolean", "object", "array", "number", "string", "integer"]
            for name in names { if try JSONComparison.textEquals(name, text, meter: &meter) { return } }
            throw fail()
        }
        try meter.work()
        switch keyword {
        case .id, .schema, .ref, .dynamicRef, .anchor, .dynamicAnchor, .comment, .title, .description, .pattern, .format, .contentEncoding, .contentMediaType:
            guard value.stringValue != nil else { throw fail() }
        case .vocabulary:
            guard let object = value.objectValue else { throw fail() }
            for member in object { try meter.work(); guard member.value.booleanValue != nil else { throw fail() } }
        case .defs, .definitions, .properties, .patternProperties, .dependentSchemas:
            guard let object = value.objectValue else { throw fail() }
            for member in object { try meter.work(); try schema(member.value) }
        case .dependencies:
            guard let object = value.objectValue else { throw fail() }
            for member in object {
                try meter.work()
                if member.value.arrayValue != nil { try strings(member.value) } else { try schema(member.value) }
            }
        case .allOf, .anyOf, .oneOf, .prefixItems:
            guard let array = value.arrayValue, !array.isEmpty else { throw fail() }
            for child in array { try meter.work(); try schema(child) }
        case .not, .if, .then, .else, .items, .contains, .additionalProperties, .propertyNames, .unevaluatedProperties, .unevaluatedItems, .contentSchema: try schema(value)
        case .type:
            if let text = value.stringValue { try type(text) } else { try strings(value, types: true) }
        case .enum, .examples: guard value.arrayValue != nil else { throw fail() }
        case .required: try strings(value)
        case .dependentRequired:
            guard let object = value.objectValue else { throw fail() }
            for member in object { try meter.work(); try strings(member.value) }
        case .minLength, .maxLength, .minItems, .maxItems, .minContains, .maxContains, .minProperties, .maxProperties:
            guard let number = value.numberValue, number.isInteger, !number.isNegative else { throw fail() }
        case .minimum, .maximum, .exclusiveMinimum, .exclusiveMaximum: guard value.numberValue != nil else { throw fail() }
        case .multipleOf: guard let number = value.numberValue, !number.isNegative, !number.isZero else { throw fail() }
        case .uniqueItems, .deprecated, .readOnly, .writeOnly: guard value.booleanValue != nil else { throw fail() }
        case .const, .default: break
        }
    }
}
