import Foundation
import HanlinPlatformContracts
import HanlinMiniAppCore

struct NativeAppNetworkBroker {
    let appID: String?
    let capabilityRegistry: NativeCapabilityRegistry

    func data(from url: URL) async throws -> (Data, URLResponse) {
        let validAppID = (try? HanlinAppID(validating: appID ?? "hanlin.swift.app"))
            ?? (try! HanlinAppID(validating: "hanlin.swift.app"))
        let context = HanlinHostCallContext.forMiniApp(
            appID: validAppID,
            installedPackageID: nil,
            origin: .system,
            capabilities: ["network"],
            canPresentUI: true
        )
        try await HanlinHostServicesBroker.shared.requireCapability("network", context: context)
        return try await URLSession.shared.data(from: url)
    }
}
