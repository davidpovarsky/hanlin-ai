// SPDX-License-Identifier: Apache-2.0
import JSON
import JSONRegexRuntime

/// Package-private indexed graph. Evaluation never reparses a URI or exposes engine types.
package struct JSONSchemaPlan: Sendable {
    package enum Keyword: String, Sendable, CaseIterable {
        case id = "$id", schema = "$schema", ref = "$ref", dynamicRef = "$dynamicRef"
        case anchor = "$anchor", dynamicAnchor = "$dynamicAnchor", vocabulary = "$vocabulary", defs = "$defs", comment = "$comment"
        case allOf, anyOf, oneOf, not, `if`, then, `else`
        case prefixItems, items, contains, properties, patternProperties, additionalProperties, propertyNames, dependentSchemas
        case unevaluatedProperties, unevaluatedItems
        case type, `enum`, const, multipleOf, minimum, maximum, exclusiveMinimum, exclusiveMaximum
        case minLength, maxLength, pattern, format
        case minItems, maxItems, uniqueItems, minContains, maxContains, minProperties, maxProperties, required, dependentRequired
        case title, description, `default`, examples, deprecated, readOnly, writeOnly
        case contentEncoding, contentMediaType, contentSchema
        // Legacy containers remain non-applicative declarations, but referenced subschemas have locations.
        case definitions, dependencies
        package static func classify(_ key: JSONKey, meter: inout JSONWorkMeter) throws -> Self? {
            for byte in key.string.utf8 { try meter.work(); if byte > 127 { return nil } }
            return Self(rawValue: key.string)
        }
    }
    package struct Child: Sendable { let keyword: Keyword; let token: JSONKey?; let target: Int }
    package struct Reference: Sendable { let keyword: Keyword; let target: Int; let dynamicAnchor: JSONKey? }
    package struct Pattern: Sendable { let keyword: Keyword; let key: JSONKey?; let program: RegexProgram }
    package struct Anchor: Sendable { let name: JSONKey; let node: Int; let dynamic: Bool }
    package struct Resource: Sendable { let uri: JSONSchemaURI; let root: Int; var anchors: [Anchor] = [] }
    package struct Node: Sendable {
        let raw: JSON
        let document: Int
        let pointer: JSONPointer
        var base: JSONSchemaURI
        var resource: Int
        var children: [Child] = []
        var references: [Reference] = []
        var patterns: [Pattern] = []
        var vocabulary: JSONSchemaVocabulary = .standard
        var metaSchema: Int?
        var formatAssertion: Bool = false
    }
    package let documents: [JSONSchemaDocument]
    package let nodes: [Node]
    package let resources: [Resource]
    package let root: Int
}
