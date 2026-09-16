import HanlinParityMiniApp
import Testing

@Test("SwiftPM Mini App exposes a valid canonical descriptor")
func descriptorIsCanonical() throws {
    let registration = SwiftParityMiniAppRegistration()
    let descriptor = try registration.appDescriptor()
    #expect(descriptor.id.rawValue == "hanlin.demo.swift-parity")
    #expect(descriptor.entryPoints.map(\.kind).contains(.app))
    #expect(descriptor.supportedExposures.contains(.widget))
    #expect(descriptor.supportedExposures.contains(.appIntent))
}
