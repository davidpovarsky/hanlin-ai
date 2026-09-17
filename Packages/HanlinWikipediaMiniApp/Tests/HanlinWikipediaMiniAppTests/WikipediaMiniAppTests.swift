import HanlinMiniAppCore
import HanlinPlatformContracts
import HanlinWikipediaMiniApp
import Testing

@Test("Wikipedia Mini App exposes a valid canonical descriptor and provider")
func wikipediaDescriptorValid() throws {
    let provider = WikipediaMiniAppProvider()
    #expect(provider.appID.rawValue == "nativeapp.wikipedia")
    #expect(provider.descriptor.category == .knowledge)
    #expect(provider.descriptor.entryPoints.map(\.kind).contains(.app))
}
