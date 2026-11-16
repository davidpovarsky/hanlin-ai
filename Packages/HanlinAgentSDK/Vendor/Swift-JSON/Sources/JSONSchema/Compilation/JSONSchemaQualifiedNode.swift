// SPDX-License-Identifier: Apache-2.0
import JSON

/// Read-only construction access to compiler-qualified declarations. Handles and
/// targets can only originate in the same immutable plan; no URI is reparsed here.
package struct JSONSchemaQualifiedNode: Sendable {
    private let plan: JSONSchemaPlan
    private let index: Int
    fileprivate init(plan: JSONSchemaPlan, index: Int) { self.plan = plan; self.index = index }

    /// Plan-local identity, not a stable/public schema identifier.
    package var identity: Int { index }
    package var childCount: Int { plan.nodes[index].children.count }
    package var referenceCount: Int { plan.nodes[index].references.count }

    package struct Declaration: Sendable {
        package let raw: JSON
        package let documentPointer: JSONPointer
        package let resourceURI: JSONSchemaURI
        package let vocabulary: JSONSchemaVocabulary
        package let formatAssertion: Bool
    }
    package struct Child: Sendable {
        package let keyword: JSONSchemaPlan.Keyword
        package let token: JSONKey?
        package let target: JSONSchemaQualifiedNode
    }
    package struct Reference: Sendable {
        package let keyword: JSONSchemaPlan.Keyword
        package let requiresDynamicScope: Bool
        package let target: JSONSchemaQualifiedNode
    }
    package func declaration(meter: inout JSONWorkMeter) throws -> Declaration {
        try meter.work()
        let node = plan.nodes[index]
        return .init(raw: node.raw, documentPointer: node.pointer,
                     resourceURI: plan.resources[node.resource].uri,
                     vocabulary: node.vocabulary, formatAssertion: node.formatAssertion)
    }
    package func child(at offset: Int, meter: inout JSONWorkMeter) throws -> Child {
        try meter.work()
        guard plan.nodes[index].children.indices.contains(offset) else {
            throw JSONFailure(.configuration, code: .invalidOperation)
        }
        let edge = plan.nodes[index].children[offset]
        return .init(keyword: edge.keyword, token: edge.token,
                     target: .init(plan: plan, index: edge.target))
    }
    package func reference(at offset: Int, meter: inout JSONWorkMeter) throws -> Reference {
        try meter.work()
        guard plan.nodes[index].references.indices.contains(offset) else {
            throw JSONFailure(.configuration, code: .invalidOperation)
        }
        let edge = plan.nodes[index].references[offset]
        return .init(keyword: edge.keyword, requiresDynamicScope: edge.dynamicAnchor != nil,
                     target: .init(plan: plan, index: edge.target))
    }
}

extension CompiledJSONSchema {
    package var exampleRoot: JSONSchemaQualifiedNode { .init(plan: plan, index: plan.root) }
}
