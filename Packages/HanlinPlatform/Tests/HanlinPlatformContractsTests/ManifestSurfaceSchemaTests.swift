import Foundation
import Testing
@testable import HanlinPlatformContracts

@Test("Exported entrypoint schema accepts every current runtime and exposure")
func manifestSurfaceSchemaMatchesRuntimeContracts() throws {
    let schema = try #require(try JSONSerialization.jsonObject(with: HanlinManifestSchema.data()) as? [String: Any])
    let definitions = try #require(schema["$defs"] as? [String: Any])
    let entrypoint = try #require(definitions["entryPoint"] as? [String: Any])
    let properties = try #require(entrypoint["properties"] as? [String: Any])
    let runtime = try #require(properties["runtimeProfile"] as? [String: Any])
    let runtimeNames = try #require(runtime["enum"] as? [String])
    #expect(Set(runtimeNames) == Set(HanlinRuntimeProfile.allCases.map(\.rawValue)))
    #expect(runtimeNames.count == Set(runtimeNames).count)

    let kinds = try #require(definitions["entryPointKind"] as? [String: Any])
    let kindNames = try #require(kinds["enum"] as? [String])
    #expect(Set(kindNames) == Set(HanlinEntryPointKind.allCases.map(\.rawValue)))
    #expect(kindNames.count == Set(kindNames).count)
}
