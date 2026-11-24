import Foundation
import Testing
@testable import HanlinChatUI
import HanlinPlatformContracts

@Suite("Composer numeric input fidelity")
struct HanlinCapabilityNumberInputTests {
    @Test func decimalAndNegativeIntermediateEditsKeepTheirExactText() {
        var input = HanlinCapabilityNumberInputState(value: nil, locale: Locale(identifier: "en_US_POSIX"))
        for raw in ["0", "0.", "0.0", "0.05"] {
            input.edit(raw)
            let boundValue = input.value
            input.synchronize(with: boundValue)
            #expect(input.text == raw)
        }
        #expect(input.value == .number(0.05))

        for raw in ["-", "-0", "-0.", "-0.0", "-0.05"] {
            input.edit(raw)
            if raw == "-" { #expect(input.value == .string("-")) }
            let boundValue = input.value
            input.synchronize(with: boundValue)
            #expect(input.text == raw)
        }
        #expect(input.value == .number(-0.05))
    }

    @Test func invalidCoordinatesReachValidationAndExternalMapUpdatesResynchronize() {
        let schema = HanlinComposerConfiguration(panels: [
            .init(id: "region", title: "Region", fields: [
                .init(key: "location", title: "Area", kind: .location, required: true)
            ])
        ])
        func configuration(latitude: HanlinJSONValue?) -> HanlinJSONValue {
            .object(["location": .object([
                "latitude": latitude ?? .null,
                "longitude": .number(35.23),
                "radiusMeters": .number(1000)
            ])])
        }
        var input = HanlinCapabilityNumberInputState(value: .number(31.78), locale: Locale(identifier: "en_US_POSIX"))
        #expect(schema.validationIssues(for: configuration(latitude: input.value)).isEmpty)

        input.edit("-")
        #expect(input.value == .string("-"))
        #expect(!schema.validationIssues(for: configuration(latitude: input.value)).isEmpty)

        let mapLatitude = HanlinJSONValue.number(31.78005)
        input.synchronize(with: mapLatitude)
        #expect(input.value == mapLatitude)
        #expect(input.text != "-")
        #expect(schema.validationIssues(for: configuration(latitude: input.value)).isEmpty)

        input.edit("")
        #expect(input.value == nil)
        #expect(!schema.validationIssues(for: configuration(latitude: input.value)).isEmpty)
    }
}
