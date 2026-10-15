import Foundation
import HanlinParityMiniApp
import HanlinPlatformContracts
import HanlinScriptUI
import Testing

@Test("SwiftPM Mini App exposes a valid canonical descriptor")
func descriptorIsCanonical() throws {
    let registration = SwiftParityMiniAppRegistration()
    let descriptor = try registration.appDescriptor()
    #expect(descriptor.id.rawValue == "hanlin.demo.swift-parity")
    #expect(descriptor.entryPoints.map(\.kind).contains(.app))
    #expect(descriptor.supportedExposures.contains(.widget))
    #expect(descriptor.supportedExposures.contains(.appIntentBridge))
}

@Test("SwiftPM Mini App exposures produce real declarative widget node and intent value from state")
func exposuresProduceRealNodesAndIntents() throws {
    // Initial state when persisted data is nil
    let defaultNode = try SwiftParityMiniAppExposures.widget(family: "systemSmall", persistedData: nil)
    #expect(defaultNode.kind == .vStack)
    #expect(defaultNode.children.contains { $0.properties["content"] == .string("Counter: 0") })

    // Decodes real state
    let stateData = Data(#"{"counter": 7, "name": "CustomParity"}"#.utf8)
    let node7 = try SwiftParityMiniAppExposures.widget(family: "systemMedium", persistedData: stateData)
    #expect(node7.children.contains { $0.properties["content"] == .string("Counter: 7") })
    #expect(node7.children.contains { $0.properties["content"] == .string("CustomParity") })

    // ReadSwiftParityState intent
    let intentResult = try SwiftParityMiniAppExposures.performIntent(
        name: "ReadSwiftParityState",
        parameters: .null,
        persistedData: stateData
    )
    if case .object(let dict) = intentResult {
        #expect(dict["counter"] == .integer(7))
        #expect(dict["name"] == .string("CustomParity"))
    } else {
        Issue.record("Expected object result from performIntent")
    }

    // Invalid intent throws
    #expect(throws: Error.self) {
        try SwiftParityMiniAppExposures.performIntent(name: "FakeIntent", parameters: .null, persistedData: stateData)
    }

    // Corrupted state throws
    let corruptData = Data("invalid json".utf8)
    #expect(throws: Error.self) {
        try SwiftParityMiniAppExposures.widget(family: "systemSmall", persistedData: corruptData)
    }
}
