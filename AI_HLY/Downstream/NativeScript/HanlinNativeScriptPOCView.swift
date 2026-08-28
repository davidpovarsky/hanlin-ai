import HanlinNativeScriptRuntime
import SwiftUI
import UIKit

/// Simulator-only diagnostic entrypoint selected by HANLIN_NATIVESCRIPT_POC=1.
struct HanlinNativeScriptPOCView: UIViewControllerRepresentable {
    final class Coordinator {
        var session: HanlinNativeScriptSession?
        var shutdownTask: Task<Void, Never>?

        @MainActor
        func shutdown() {
            guard let session else { return }
            session.shutdown()
            self.session = nil
            print("HANLIN_NS_SHUTDOWN_OK")
        }

        deinit {
            shutdownTask?.cancel()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    func makeUIViewController(context: Context) -> UIViewController {
        do {
            let applicationSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
            let fixtureRoot = applicationSupport
                .appending(path: "HanlinNativeScriptPOC/fixture-a/nativescript/app", directoryHint: .isDirectory)
            let session = try HanlinNativeScriptSession(applicationRoot: fixtureRoot)
            context.coordinator.session = session
            try session.start()
            print("HANLIN_NS_INITIALIZED_EXTERNAL_ROOT path=\(fixtureRoot.path(percentEncoded: false))")

            context.coordinator.shutdownTask = Task { @MainActor [weak coordinator = context.coordinator] in
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                coordinator?.shutdown()
            }
            return session.containerController
        } catch {
            print("HANLIN_NS_POC_FAILED error=\(error.localizedDescription)")
            return failureController(message: error.localizedDescription)
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    @MainActor
    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        coordinator.shutdownTask?.cancel()
        coordinator.shutdown()
    }

    @MainActor
    private func failureController(message: String) -> UIViewController {
        let controller = UIViewController()
        let label = UILabel()
        label.text = "NativeScript POC failed: \(message)"
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        controller.view.backgroundColor = .systemBackground
        controller.view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            label.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor),
        ])
        return controller
    }
}
