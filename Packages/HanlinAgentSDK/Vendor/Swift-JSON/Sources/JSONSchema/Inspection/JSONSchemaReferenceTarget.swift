// SPDX-License-Identifier: Apache-2.0
import JSON

/// An initial indexed reference target in an immutable compiled snapshot.
///
/// Dynamic scope may replace this target during evaluation.
public struct JSONSchemaReferenceTarget: Sendable {
    /// The exact keyword name associated with the issue, annotation or reference.
    public let keyword: JSONKey
    /// The normalized URI of the initial target resource.
    public let resourceURI: JSONSchemaURI
    /// The initial target Pointer relative to its resource.
    public let pointer: JSONPointer
    /// Whether evaluation may replace the initial target using dynamic scope.
    public let requiresDynamicScope: Bool
    package init(keyword: JSONKey, resourceURI: JSONSchemaURI, pointer: JSONPointer, requiresDynamicScope: Bool) {
        self.keyword = keyword; self.resourceURI = resourceURI; self.pointer = pointer; self.requiresDynamicScope = requiresDynamicScope
    }
}
