import Foundation
import Security
import SwiftData
import Testing
@testable import AI_Hanlin

@MainActor
@Suite("Original application embedding")
struct HanlinApplicationEmbeddingTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: APIKeys.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    @Test
    func providerCredentialLookupUsesTheRecordsContainer() throws {
        let app = "hanlin.embedding.tests." + UUID().uuidString.lowercased()
        let firstPolicy = HanlinApplicationConfiguration(
            appIdentifier: app, accountIdentifier: "first").credentials
        let secondPolicy = HanlinApplicationConfiguration(
            appIdentifier: app, accountIdentifier: "second").credentials
        let first = try container()
        let second = try container()
        HanlinApplicationCredentialRegistry.shared.register(first, credentials: firstPolicy)
        HanlinApplicationCredentialRegistry.shared.register(second, credentials: secondPolicy)
        defer {
            for policy in [firstPolicy, secondPolicy] {
                SecItemDelete([
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: policy.service
                ] as CFDictionary)
            }
        }

        let reference = try firstPolicy.store.stage("synthetic-host-credential",
            kind: .model, previousStoredValue: nil)
        let firstRecord = APIKeys(company: "fixture", key: reference)
        let secondRecord = APIKeys(company: "fixture", key: reference)
        first.mainContext.insert(firstRecord)
        second.mainContext.insert(secondRecord)
        try first.mainContext.save()
        try second.mainContext.save()

        #expect(try HanlinAppProviderCredentials.shared.resolve(firstRecord) == "synthetic-host-credential")
        #expect(throws: (any Error).self) {
            try HanlinAppProviderCredentials.shared.resolve(secondRecord)
        }
        // Opening/reading the second container must not change the first one.
        #expect(try HanlinAppProviderCredentials.shared.resolve(firstRecord) == "synthetic-host-credential")
    }

    @Test
    func originalRuntimeCannotBeRedirectedToAnotherContainer() throws {
        let runtime = HanlinApplicationProcessRuntime()
        let first = try container()
        let second = try container()
        let configuration = HanlinApplicationRuntimeConfiguration(
            directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString),
            mcpSecretService: "fixture.mcp", environmentSecretService: "fixture.environment")
        try runtime.install(configuration, modelContainer: first)
        try runtime.install(configuration, modelContainer: first)
        #expect(throws: HanlinApplicationError.self) {
            try runtime.install(configuration, modelContainer: second)
        }
        #expect(runtime.configuration == configuration)
    }
}
