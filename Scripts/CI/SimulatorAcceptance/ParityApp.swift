import Foundation
import HanlinMiniAppCore
import HanlinParityMiniApp
import HanlinPlatformContracts
import SwiftUI

/// Executes the complete existing compiled Mini App. This fixture never counts
/// as acceptance of AI_Hanlin, its provider, scripting engines or chat UI.
@main
struct HanlinParityUIApp: App {
    private let storage: HanlinMiniAppStorageContext?
    private let broker = HanlinMiniAppRequestBroker()

    init() {
        do {
            let root = try HanlinMiniAppDataStore.applicationSupportRoot()
            let store = try HanlinMiniAppDataStore(root: root)
            storage = HanlinMiniAppStorageContext(
                appID: SwiftParityMiniAppRegistration().appID, store: store
            )
        } catch {
            storage = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if let storage {
                    SwiftParityMiniAppView(storage: storage, requestBroker: broker) { url in
                        let (data, response) = try await URLSession.shared.data(from: url)
                        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                            throw URLError(.badServerResponse)
                        }
                        return String(decoding: data, as: UTF8.self)
                    }
                } else {
                    ContentUnavailableView("Storage unavailable", systemImage: "externaldrive.badge.exclamationmark")
                }
            }
        }
    }
}
