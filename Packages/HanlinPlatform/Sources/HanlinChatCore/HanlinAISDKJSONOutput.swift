import AISDKProvider
import AISDKProviderUtils
import Foundation
import SwiftAISDK

/// Uses the SDK's original Output.object contract and JSON Schema validator.
/// Host operations additionally validate the retained original bytes with
/// HanlinHostSchemaValidation before exposing structured results to JavaScript.
enum HanlinAISDKJSONOutput {
    static func specification(schemaData: Data) throws -> Output.Specification<JSONValue, JSONValue> {
        guard schemaData.count <= 1_048_576 else {
            throw HanlinAISDKError.invalidConversation("Response schema exceeds the supported parsing budget.")
        }
        let schema = try JSONDecoder().decode(JSONValue.self, from: schemaData)
        guard case .object = schema else {
            throw HanlinAISDKError.invalidConversation("Response schema must be a JSON Schema object.")
        }
        return Output.object(schema: jsonSchema(schema), name: "hanlin_miniapp_response")
    }
}
