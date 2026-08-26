import QuickLook
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct HanlinScriptingSystemUIPresentation: Identifiable {
    let id: UUID
    let request: HanlinScriptingSystemUIRequest
}

struct HanlinScriptingSystemUIPresentationView: View {
    let presentation: HanlinScriptingSystemUIPresentation
    let completion: (Result<HanlinScriptingSystemUIResult, any Error>) -> Void

    @ViewBuilder
    var body: some View {
        switch presentation.request {
        case let .pickFiles(allowsMultipleSelection, shouldShowFileExtensions, contentTypeIdentifiers):
            HanlinDocumentPickerController(
                contentTypes: contentTypeIdentifiers.compactMap(UTType.init),
                allowsMultipleSelection: allowsMultipleSelection,
                shouldShowFileExtensions: shouldShowFileExtensions,
                completion: completion
            )
        case .pickDirectory:
            HanlinDocumentPickerController(
                contentTypes: [.folder],
                allowsMultipleSelection: false,
                shouldShowFileExtensions: true,
                completion: completion
            )
        case let .previewURLs(urls):
            HanlinQuickLookController(urls: urls, completion: completion)
        }
    }
}

private struct HanlinDocumentPickerController: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let allowsMultipleSelection: Bool
    let shouldShowFileExtensions: Bool
    let completion: (Result<HanlinScriptingSystemUIResult, any Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: contentTypes.isEmpty ? [.item] : contentTypes,
            asCopy: false
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.shouldShowFileExtensions = shouldShowFileExtensions
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let completion: (Result<HanlinScriptingSystemUIResult, any Error>) -> Void
        private var completed = false

        init(completion: @escaping (Result<HanlinScriptingSystemUIResult, any Error>) -> Void) {
            self.completion = completion
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            finish(.success(.urls(urls)))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            finish(.success(.urls([])))
        }

        private func finish(_ result: Result<HanlinScriptingSystemUIResult, any Error>) {
            guard !completed else { return }
            completed = true
            completion(result)
        }
    }
}

private struct HanlinQuickLookController: UIViewControllerRepresentable {
    let urls: [URL]
    let completion: (Result<HanlinScriptingSystemUIResult, any Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(urls: urls, completion: completion) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        preview.navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [weak coordinator = context.coordinator] _ in
                coordinator?.finish()
            }
        )
        return UINavigationController(rootViewController: preview)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        private let urls: [URL]
        private let completion: (Result<HanlinScriptingSystemUIResult, any Error>) -> Void
        private var completed = false

        init(urls: [URL], completion: @escaping (Result<HanlinScriptingSystemUIResult, any Error>) -> Void) {
            self.urls = urls
            self.completion = completion
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { urls.count }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
            urls[index] as NSURL
        }

        func finish() {
            guard !completed else { return }
            completed = true
            completion(.success(.completed))
        }
    }
}
