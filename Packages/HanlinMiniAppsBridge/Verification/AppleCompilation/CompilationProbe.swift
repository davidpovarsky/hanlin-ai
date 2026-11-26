import Foundation
import SwiftUI
import HanlinMiniAppsBridge
import HanlinMiniAppsPicker

/// Compile-only integration surface. This target never boots an app or engines.
@MainActor
public struct MiniAppClientCompilationProbe: View {
    private let store: MiniAppBridgeStore
    public init(containerURL: URL) throws {
        store = try MiniAppBridgeStore(containerURL: containerURL)
    }

    public var body: some View {
        NavigationStack {
            MiniAppPreferencesView(store: store)
        }
        .sheet(isPresented: .constant(false)) {
            MiniAppPicker(store: store,
                source: .init(appID: "com.hanlin.validation", displayName: "Validation"),
                inputs: [.init(kind: .text, text: "שלום 🙂")],
                callbacks: .init(success: URL(string: "validation://miniapps-result")),
                onOpen: { _ in })
        }
    }
}
