import Foundation
import Testing
@testable import AI_Hanlin

@Suite("Human-readable model labels")
struct HanlinModelDisplayNameTests {
    @Test func removesOnlyTheGeneratedLegacyDisplaySuffix() {
        let suffix = "_repeat_3ADDD55C-F338-42B4-B363-3E306E5C70EF"
        #expect(HanlinModelDisplayName.clean("אנבידיה" + suffix) == "אנבידיה")
        #expect(HanlinModelDisplayName.clean("NVIDIA Nemotron" + suffix) == "NVIDIA Nemotron")
        #expect(HanlinModelDisplayName.clean("My_repeat_model") == "My_repeat_model")
        #expect(HanlinModelDisplayName.clean("My_repeat_1234") == "My_repeat_1234")
        #expect(HanlinModelDisplayName.clean("  My own model  ") == "My own model")
    }

    @Test func keepsUserLabelsAndUsesTheRoutingNameOnlyAsFallback() {
        #expect(HanlinModelDisplayName.resolve(displayName: "My assistant", modelName: "nvidia/model_repeat_custom") == "My assistant")
        #expect(HanlinModelDisplayName.resolve(displayName: " ", modelName: "nvidia/model_repeat_custom") == "nvidia/model_repeat_custom")
        #expect(HanlinModelDisplayName.resolve(displayName: nil, modelName: "nvidia/model_repeat_custom_repeat_3ADDD55C-F338-42B4-B363-3E306E5C70EF") == "nvidia/model_repeat_custom")
        #expect(HanlinModelDisplayName.resolve(displayName: nil, modelName: nil, fallback: "Choose a model") == "Choose a model")
        #expect(HanlinModelDisplayName.resolve(displayName: nil, modelName: "_repeat_3ADDD55C-F338-42B4-B363-3E306E5C70EF", fallback: "Choose a model") == "Choose a model")
    }
}
