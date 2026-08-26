import QuickLook
@preconcurrency import PhotosUI
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
        case let .pickPhotos(limit):
            HanlinPhotoPickerController(limit: limit, completion: completion)
        case .takePhoto:
            HanlinCameraPickerController(completion: completion)
        }
    }
}

private struct HanlinPhotoPickerController: UIViewControllerRepresentable {
    let limit: Int
    let completion: (Result<HanlinScriptingSystemUIResult, any Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = limit
        configuration.selection = .ordered
        configuration.preferredAssetRepresentationMode = .compatible
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let completion: (Result<HanlinScriptingSystemUIResult, any Error>) -> Void
        private var completed = false

        init(completion: @escaping (Result<HanlinScriptingSystemUIResult, any Error>) -> Void) {
            self.completion = completion
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !completed else { return }
            if results.isEmpty {
                finish(.success(.images([])))
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    var images: [Data] = []
                    images.reserveCapacity(results.count)
                    for result in results {
                        images.append(try await Self.loadJPEGData(from: result.itemProvider))
                    }
                    finish(.success(.images(images)))
                } catch {
                    finish(.failure(error))
                }
            }
        }

        private static func loadJPEGData(from provider: NSItemProvider) async throws -> Data {
            let image = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<UIImage, any Error>) in
                provider.loadObject(ofClass: UIImage.self) { object, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let image = object as? UIImage {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(throwing: HanlinScriptingNativeError(
                            name: "Error", code: "photo_decode_failed",
                            message: "A selected photo could not be decoded."
                        ))
                    }
                }
            }
            guard let data = image.jpegData(compressionQuality: 1) else {
                throw HanlinScriptingNativeError(
                    name: "Error", code: "photo_encode_failed",
                    message: "A selected photo could not be encoded."
                )
            }
            return data
        }

        private func finish(_ result: Result<HanlinScriptingSystemUIResult, any Error>) {
            guard !completed else { return }
            completed = true
            completion(result)
        }
    }
}

private struct HanlinCameraPickerController: UIViewControllerRepresentable {
    let completion: (Result<HanlinScriptingSystemUIResult, any Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIViewController(context: Context) -> UIViewController {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            Task { @MainActor [weak coordinator = context.coordinator] in
                await Task.yield()
                coordinator?.finish(.failure(HanlinScriptingNativeError(
                    name: "Error", code: "camera_unavailable",
                    message: "A camera is not available on this device."
                )))
            }
            return UIViewController()
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.allowsEditing = false
        picker.modalPresentationStyle = .fullScreen
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let completion: (Result<HanlinScriptingSystemUIResult, any Error>) -> Void
        private var completed = false

        init(completion: @escaping (Result<HanlinScriptingSystemUIResult, any Error>) -> Void) {
            self.completion = completion
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 1) else {
                finish(.failure(HanlinScriptingNativeError(
                    name: "Error", code: "camera_encode_failed",
                    message: "The captured photo could not be encoded."
                )))
                return
            }
            finish(.success(.image(data)))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            finish(.success(.image(nil)))
        }

        func finish(_ result: Result<HanlinScriptingSystemUIResult, any Error>) {
            guard !completed else { return }
            completed = true
            completion(result)
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
