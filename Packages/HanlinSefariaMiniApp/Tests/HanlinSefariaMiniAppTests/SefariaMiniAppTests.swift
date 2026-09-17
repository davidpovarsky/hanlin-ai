import HanlinMiniAppCore
import HanlinPlatformContracts
import HanlinSefariaMiniApp
import Testing

@Test("Sefaria Mini App exposes a valid canonical descriptor and provider")
func sefariaDescriptorValid() throws {
    let provider = SefariaMiniAppProvider()
    #expect(provider.appID.rawValue == "nativeapp.sefaria")
    #expect(provider.descriptor.category == .knowledge)
    #expect(provider.descriptor.entryPoints.map(\.kind).contains(.app))
}
