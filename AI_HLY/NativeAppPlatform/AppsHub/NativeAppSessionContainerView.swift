import SwiftData
import SwiftUI

struct NativeAppSessionContainerView: View {
    let request: NativeAppLaunchRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @StateObject private var session: NativeAppSession

    init(request: NativeAppLaunchRequest) {
        self.request = request
        _session = StateObject(
            wrappedValue: NativeAppSession(
                id: request.id,
                appID: request.appID,
                presentationStyle: request.presentationStyle
            )
        )
    }

    private var context: NativeAppContext {
        NativeAppContext(
            localeIdentifier: Locale.current.identifier,
            modelContext: modelContext,
            openURL: { url in openURL(url) },
            session: session
        )
    }

    var body: some View {
        Group {
            if let module = NativeAppRegistry.shared.module(id: request.appID) {
                NavigationStack {
                    module.makeRootView(context: context)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Close") {
                                    session.close()
                                    dismiss()
                                }
                            }
                        }
                }
                .environment(\.nativeAppSession, session)
            } else {
                NavigationStack {
                    ContentUnavailableView(
                        "App Not Found",
                        systemImage: "questionmark.app",
                        description: Text(request.appID)
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Close") {
                                session.close()
                                dismiss()
                            }
                        }
                    }
                }
            }
        }
        .onDisappear {
            session.close()
        }
    }
}
