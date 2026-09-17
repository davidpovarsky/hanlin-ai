import HanlinMiniAppCore
import HanlinPlatformContracts
import HanlinTextStudioMiniApp
import Testing

@Test("Text Studio Mini App exposes a valid canonical descriptor and provider")
func textStudioDescriptorValid() throws {
    let provider = TextStudioMiniAppProvider()
    #expect(provider.appID.rawValue == "nativeapp.textstudio")
    #expect(provider.descriptor.category == .productivity)
    #expect(provider.descriptor.entryPoints.map(\.kind).contains(.app))
}
