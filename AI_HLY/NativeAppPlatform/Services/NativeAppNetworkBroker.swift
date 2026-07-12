import Foundation

struct NativeAppNetworkBroker {
    let appID: String?
    let capabilityRegistry: NativeCapabilityRegistry

    // Future policy enforcement belongs here: declared capability, allowed domain,
    // origin, user initiation, and runtime-script restrictions.
    func data(from url: URL) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(from: url)
    }
}
