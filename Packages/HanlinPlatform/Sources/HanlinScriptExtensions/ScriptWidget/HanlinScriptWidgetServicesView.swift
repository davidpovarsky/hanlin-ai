import Foundation
import SwiftUI
import JavaScriptCore
@preconcurrency import HanlinScriptWidgetOriginal

/// Native original service setup for the exact installed widget instance.
@MainActor
public struct HanlinScriptWidgetServicesView: View {
    private let store: HanlinScriptExtensionStore
    private let entityID: String
    @State private var configuration: HanlinOriginalScriptWidgetConfiguration?
    @State private var failure: String?

    public init(store: HanlinScriptExtensionStore, entityID: String) {
        self.store = store
        self.entityID = entityID
    }

    public var body: some View {
        Group {
            if let configuration { configuration }
            else if let failure {
                ContentUnavailableView("Widget Services", systemImage: "exclamationmark.triangle",
                                       description: Text(failure))
            } else { ProgressView("Loading widget services") }
        }
        .task { load() }
    }

    private func load() {
        do {
            guard let snapshot = try store.load(),
                  let widget = snapshot.widgets.first(where: {
                      $0.engine == .scriptwidget
                        && HanlinWidgetInstance(identity: $0.identity, engine: $0.engine, displayName: $0.displayName).entityID == entityID
                  }),
                  !snapshot.inactiveWidgetInstallations.contains(widget.identity.installedPackageID.rawValue),
                  let context = JSContext() else {
                throw HanlinScriptWidgetError("This installed ScriptWidget is unavailable.")
            }
            let (program, digest) = try store.loadProgram(for: widget)
            let state = snapshot.widgetStates.first { $0.identity == widget.identity && $0.engine == .scriptwidget }
            let session = try HanlinOriginalScriptWidgetSession(context: context,
                root: store.root.appendingPathComponent("ScriptWidgetOriginal/v1", isDirectory: true),
                identity: try HanlinScriptWidgetRuntime.nativeIdentity(widget.identity, artifactSHA256: digest),
                preparedJavaScript: program.javaScript, files: program.resources,
                values: (state?.values ?? [:]).mapValues { $0.toAny() }, environment: [:],
                isUserInitiatedAction: false)
            configuration = session.configurationView
            session.finish()
        } catch { failure = error.localizedDescription }
    }
}
