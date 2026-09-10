// ExposureContractTests.swift
// HanlinPlatformContractsTests

import Foundation
import HanlinPlatformContracts
import Testing

@Suite("Exposure catalog and composite discovery")
struct ExposureContractTests {
    @Test("Exposure catalog defines standard classifications for near-term surfaces")
    func standardClassifications() {
        let catalog = HanlinExposureCatalog.standardClassifications
        #expect(catalog.count >= 20)

        // 1. Foreground app
        let app = HanlinExposureCatalog.classification(for: .foregroundApp)
        #expect(app != nil)
        #expect(app?.isUserInterface == true)
        #expect(app?.supportsGenericHost == true)
        #expect(app?.implementationState == .implemented)

        // 2. Assistant tool
        let tool = HanlinExposureCatalog.classification(for: .assistantTool)
        #expect(tool != nil)
        #expect(tool?.isUserInterface == false)
        #expect(tool?.supportsGenericHost == true)
        #expect(tool?.implementationState == .implemented)

        // 3. Embedded result
        let result = HanlinExposureCatalog.classification(for: .embeddedResult)
        #expect(result != nil)
        #expect(result?.isUserInterface == true)
        #expect(result?.supportsGenericHost == true)
        #expect(result?.implementationState == .genericHosted)

        // 4. WidgetKit
        let widget = HanlinExposureCatalog.classification(for: .widget)
        #expect(widget != nil)
        #expect(widget?.requiresDedicatedExtensionTarget == true)
        #expect(widget?.eligibility == .hybrid)
        #expect(widget?.implementationState == .genericHosted)

        // 5. Live Activity
        let liveActivity = HanlinExposureCatalog.classification(for: .liveActivity)
        #expect(liveActivity != nil)
        #expect(liveActivity?.requiresDedicatedExtensionTarget == true)
        #expect(liveActivity?.eligibility == .hybrid)

        // 6. Controls
        let control = HanlinExposureCatalog.classification(for: .controlWidget)
        #expect(control != nil)
        #expect(control?.requiresDedicatedExtensionTarget == true)
        #expect(control?.eligibility == .hybrid)

        // 7. App Intents
        let appIntent = HanlinExposureCatalog.classification(for: .appIntent)
        #expect(appIntent != nil)
        #expect(appIntent?.isUserInterface == false)
        #expect(appIntent?.implementationState == .implemented)

        // 8. Translation UI Provider
        let translation = HanlinExposureCatalog.classification(for: .translationUI)
        #expect(translation != nil)
        #expect(translation?.requiresDedicatedExtensionTarget == true)
        #expect(translation?.requiredEntitlements.contains("com.apple.developer.translation") == true)
        #expect(translation?.implementationState == .genericHosted)

        // 9. Unsupported surfaces
        let netExt = HanlinExposureCatalog.classification(for: .networkExtension)
        #expect(netExt?.implementationState == .unsupported)
        let audioUnit = HanlinExposureCatalog.classification(for: .audioUnit)
        #expect(audioUnit?.implementationState == .unsupported)
    }

    @Test("Exposure classifications round-trip through JSON")
    func exposureClassificationCodec() throws {
        for classification in HanlinExposureCatalog.standardClassifications {
            let data = try JSONEncoder().encode(classification)
            let decoded = try JSONDecoder().decode(
                HanlinExposureClassification.self,
                from: data
            )
            #expect(decoded == classification)
        }
    }

    private struct MockMiniAppRegistration: HanlinMiniAppRegistration {
        let appID: HanlinAppID
        let descriptorProvider: () throws -> HanlinAppDescriptor

        func appDescriptor() throws -> HanlinAppDescriptor {
            try descriptorProvider()
        }
    }

    private struct MockMiniAppDiscovery: HanlinMiniAppDiscovery {
        let mockRegistrations: [any HanlinMiniAppRegistration]

        func registrations() async throws -> [any HanlinMiniAppRegistration] {
            mockRegistrations
        }

        func registration(for appID: HanlinAppID) async throws -> (any HanlinMiniAppRegistration)? {
            mockRegistrations.first { $0.appID == appID }
        }

        func catalogSnapshot(revision: HanlinCatalogRevision) async throws -> HanlinCatalogSnapshot {
            let descriptors = try mockRegistrations.map { try $0.appDescriptor() }
            return HanlinCatalogSnapshot(
                revision: revision,
                generatedAt: .now,
                apps: descriptors
            )
        }
    }

    @Test("Composite discovery aggregates and deduplicates across providers")
    func compositeDiscovery() async throws {
        let appID1 = try HanlinAppID(validating: "app.first")
        let appID2 = try HanlinAppID(validating: "app.second")

        let desc1 = try ContractFixtures.descriptor()
        let reg1 = MockMiniAppRegistration(appID: appID1, descriptorProvider: { desc1 })
        let reg2 = MockMiniAppRegistration(appID: appID2, descriptorProvider: { desc1 })
        let duplicateReg1 = MockMiniAppRegistration(appID: appID1, descriptorProvider: { desc1 })

        let providerA = MockMiniAppDiscovery(mockRegistrations: [reg1])
        let providerB = MockMiniAppDiscovery(mockRegistrations: [duplicateReg1, reg2])

        let composite = HanlinCompositeMiniAppDiscovery(providers: [providerA, providerB])
        let combined = try await composite.registrations()

        // Should deduplicate app.first
        #expect(combined.count == 2)
        let ids = Set(combined.map(\.appID.rawValue))
        #expect(ids == ["app.first", "app.second"])

        let found = try await composite.registration(for: appID2)
        #expect(found?.appID == appID2)

        let missing = try await composite.registration(for: try HanlinAppID(validating: "app.missing"))
        #expect(missing == nil)

        let snapshot = try await composite.catalogSnapshot(revision: .init(1))
        #expect(snapshot.apps.count == 2)
    }
}
