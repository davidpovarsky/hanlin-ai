import Foundation

@MainActor
struct NativeAppOpenURLBroker {
    let appID: String?
    let openURL: NativeOpenURLAction?
    let capabilityRegistry: NativeCapabilityRegistry

    func open(_ url: URL) { openURL?(url) }
    func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        open(url)
    }
}
