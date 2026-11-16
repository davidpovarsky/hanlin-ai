// SPDX-License-Identifier: Apache-2.0
import JSON

package struct JSONSchemaVocabulary: OptionSet, Sendable {
    package let rawValue: UInt16
    package init(rawValue: UInt16) { self.rawValue = rawValue }
    package static let core = Self(rawValue: 1 << 0)
    package static let applicator = Self(rawValue: 1 << 1)
    package static let validation = Self(rawValue: 1 << 2)
    package static let unevaluated = Self(rawValue: 1 << 3)
    package static let metadata = Self(rawValue: 1 << 4)
    package static let formatAnnotation = Self(rawValue: 1 << 5)
    package static let formatAssertion = Self(rawValue: 1 << 6)
    package static let content = Self(rawValue: 1 << 7)
    package static let standard: Self = [.core,.applicator,.validation,.unevaluated,.metadata,.formatAnnotation,.content]
    package func applies(_ keyword: JSONSchemaPlan.Keyword) -> Bool {
        switch keyword {
        case .id,.schema,.ref,.dynamicRef,.anchor,.dynamicAnchor,.vocabulary,.defs,.comment,.definitions,.dependencies: return contains(.core)
        case .allOf,.anyOf,.oneOf,.not,.if,.then,.else,.prefixItems,.items,.contains,.properties,.patternProperties,.additionalProperties,.propertyNames,.dependentSchemas: return contains(.applicator)
        case .unevaluatedProperties,.unevaluatedItems: return contains(.unevaluated)
        case .type,.enum,.const,.multipleOf,.minimum,.maximum,.exclusiveMinimum,.exclusiveMaximum,.minLength,.maxLength,.pattern,.minItems,.maxItems,.uniqueItems,.minContains,.maxContains,.minProperties,.maxProperties,.required,.dependentRequired: return contains(.validation)
        case .title,.description,.default,.examples,.deprecated,.readOnly,.writeOnly: return contains(.metadata)
        case .format: return contains(.formatAnnotation) || contains(.formatAssertion)
        case .contentEncoding,.contentMediaType,.contentSchema: return contains(.content)
        }
    }
}
