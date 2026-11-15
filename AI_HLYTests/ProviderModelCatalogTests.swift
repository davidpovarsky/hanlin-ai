import Foundation
import Testing
@testable import AI_Hanlin

@Suite("Provider catalog provenance")
struct ProviderModelCatalogTests {
    @Test func freePaidUnknownAndMalformedPricesNeverUseTheModelName() {
        func entry(_ rates: [String: String]?) -> ProviderModelCatalogMetadata {
            .init(modelID: "nvidia/test:free", source: "https://openrouter.ai/api/v1/models",
                pricing: rates, architecture: nil, parameters: nil)
        }
        #expect(entry(["prompt": "0", "completion": "0"]).priceStatus == .free)
        #expect(entry(["prompt": "0.000001", "completion": "0.000002"]).priceStatus == .paid)
        #expect(entry(nil).priceStatus == .unknown)
        #expect(entry(["prompt": "-1", "completion": "0"]).priceStatus == .unknown)
        #expect(entry(["prompt": "0junk", "completion": "0"]).priceStatus == .unknown)
    }

    @Test func imageInputDoesNotClaimImageOutputAndExpiredDataIsNotFresh() {
        let metadata = ProviderModelCatalogMetadata(modelID: "vision", source: "https://openrouter.ai/api/v1/models",
            verifiedAt: Date(timeIntervalSinceNow: -90_000), pricing: ["prompt": "0", "completion": "0"],
            architecture: .init(input_modalities: ["text", "image"], output_modalities: ["text"]), parameters: ["tools"])
        #expect(!metadata.hasImageOutput)
        #expect(!metadata.isFresh)
    }
}
