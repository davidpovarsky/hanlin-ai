// SPDX-License-Identifier: Apache-2.0
import JSON

/// A bounded assertion issue containing locations and a keyword, without instance payload.
public struct JSONValidationIssue: Sendable {
    /// The Pointer to the instance location that produced the issue or annotation.
    public let instanceLocation: JSONPointer
    /// The Pointer to the evaluated schema keyword.
    public let keywordLocation: JSONPointer
    /// The resolved keyword URI, when available.
    public let absoluteKeywordLocation: JSONSchemaURI?
    /// The exact keyword name associated with the issue, annotation or reference.
    public let keyword: JSONKey
    /// Creates a bounded structured issue from explicit locations and the failing keyword.
    ///
    /// - Parameters:
    ///   - instanceLocation: The instance Pointer.
    ///   - keywordLocation: The schema keyword Pointer.
    ///   - absoluteKeywordLocation: The optional absolute keyword URI.
    ///   - keyword: The exact keyword name.
    public init(instanceLocation: JSONPointer, keywordLocation: JSONPointer, absoluteKeywordLocation: JSONSchemaURI?, keyword: JSONKey) {
        self.instanceLocation = instanceLocation; self.keywordLocation = keywordLocation
        self.absoluteKeywordLocation = absoluteKeywordLocation; self.keyword = keyword
    }
}
