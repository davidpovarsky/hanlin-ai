// SPDX-License-Identifier: Apache-2.0
extension JSON {
    /// Encodes a Swift model directly through the existing native value coder.
    /// No Foundation serialization intermediate or persistence envelope is introduced.
    /// - Parameters:
    ///   - value: The Encodable model; caller callback errors propagate.
    ///   - coding: Native Date/Data strategies, Sendable context and finite limits.
    /// - Throws: Native/caller coding errors, resource/configuration failure or cancellation.
    public init<T: Encodable>(encoding value: T, coding: JSONCodingOptions = .init()) throws {
        self = try JSONValueEncoder(options: coding).encode(value)
    }
    /// Decodes a Swift model with the existing native strategies and exact integers.
    /// - Parameters:
    ///   - type: The target Decodable model.
    ///   - coding: Native strategies, Sendable context and finite limits.
    /// - Throws: Native/caller coding errors, resource/configuration failure or cancellation.
    public func decode<T: Decodable>(_ type: T.Type, coding: JSONCodingOptions = .init()) throws -> T {
        try JSONValueDecoder(options: coding).decode(type, from: self)
    }
    /// Decodes a Swift model and reports successful owned native coding work.
    /// - Parameters:
    ///   - type: The target Decodable model.
    ///   - coding: Native strategies, Sendable context and finite limits.
    /// - Throws: Native/caller coding errors, resource/configuration failure or cancellation.
    public func decodeWithReport<T: Decodable>(_ type: T.Type, coding: JSONCodingOptions = .init()) throws -> JSONOperationReport<T> {
        try JSONValueDecoder(options: coding).decodeWithReport(type, from: self)
    }
}
