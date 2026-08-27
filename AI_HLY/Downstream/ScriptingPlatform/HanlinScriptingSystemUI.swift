import QuickLook
@preconcurrency import PhotosUI
import SafariServices
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
        case let .pickFiles(allowsMultipleSelection, shouldShowFileExtensions, contentTypeIdentifiers, initialDirectory):
            HanlinDocumentPickerController(
                contentTypes: contentTypeIdentifiers.compactMap(UTType.init),
                allowsMultipleSelection: allowsMultipleSelection,
                shouldShowFileExtensions: shouldShowFileExtensions,
                initialDirectory: initialDirectory,
                completion: completion
            )
        case let .pickDirectory(initialDirectory):
            HanlinDocumentPickerController(
                contentTypes: [.folder],
                allowsMultipleSelection: false,
                shouldShowFileExtensions: true,
                initialDirectory: initialDirectory,
                completion: completion
            )
        case let .exportFiles(urls, initialDirectory):
            HanlinDocumentExportController(
                urls: urls,
                initialDirectory: initialDirectory,
                completion: completion
            )
        case let .previewURLs(urls):
            HanlinQuickLookController(urls: urls, completion: completion)
        case let .previewText(text):
            HanlinQuickLookTextPreview(text: text, completion: completion)
        case let .previewImage(data):
            if let image = UIImage(data: data) {
                HanlinQuickLookImagePreview(image: image, completion: completion)
            } else {
                ContentUnavailableView("Image Unavailable", systemImage: "photo.badge.exclamationmark")
            }
        case let .pickPhotos(limit):
            HanlinPhotoPickerController(limit: limit, completion: completion)
        case .takePhoto:
            HanlinCameraPickerController(completion: completion)
        case let .dialog(request):
            HanlinDialogController(request: request, completion: completion)
        case let .editor(request):
            HanlinEditorView(request: request, completion: completion)
        case let .safari(url, _):
            HanlinSafariController(url: url, completion: completion)
        }
    }
}

private struct HanlinSafariController: UIViewControllerRepresentable {
    let url: URL
    let completion: (Result<HanlinScriptingSystemUIResult, any Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.delegate = context.coordinator
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        private let completion: (Result<HanlinScriptingSystemUIResult, any Error>) -> Void
        private var completed = false

        init(completion: @escaping (Result<HanlinScriptingSystemUIResult, any Error>) -> Void) {
            self.completion = completion
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            guard !completed else { return }
            completed = true
            completion(.success(.completed))
        }
    }
}

private struct HanlinEditorView: View {
    let request: HanlinScriptingEditorRequest
    let completion: (Result<HanlinScriptingSystemUIResult, any Error>) -> Void
    @State private var content: String

    init(
        request: HanlinScriptingEditorRequest,
        completion: @escaping (Result<HanlinScriptingSystemUIResult, any Error>) -> Void
    ) {
        self.request = request
        self.completion = completion
        _content = State(initialValue: request.content)
    }

    var body: some View {
        NavigationStack {
            Group {
                if request.readOnly {
                    ScrollView {
                        Text(content)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                } else {
                    TextEditor(text: $content)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 8)
                }
            }
            .navigationTitle(request.navigationTitle ?? "Editor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { completion(.success(.text(content))) }
                }
            }
        }
    }
}

private struct HanlinDialogController: UIViewControllerRepresentable {
    let request: HanlinScriptingDialogRequest
    let completion: (Result<HanlinScriptingSystemUIResult, any Error>) -> Void

    func makeUIViewController(context: Context) -> HanlinDialogPresenterViewController {
        HanlinDialogPresenterViewController(request: request, completion: completion)
    }

    func updateUIViewController(
        _ controller: HanlinDialogPresenterViewController,
        context: Context
    ) {}
}

@MainActor
private final class HanlinDialogPresenterViewController: UIViewController {
    private let request: HanlinScriptingDialogRequest
    private let completion: (Result<HanlinScriptingSystemUIResult, any Error>) -> Void
    private var didPresentDialog = false

    init(
        request: HanlinScriptingDialogRequest,
        completion: @escaping (Result<HanlinScriptingSystemUIResult, any Error>) -> Void
    ) {
        self.request = request
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didPresentDialog else { return }
        didPresentDialog = true
        presentDialog()
    }

    private func presentDialog() {
        let style: UIAlertController.Style = request.kind == .actionSheet ? .actionSheet : .alert
        let alert = UIAlertController(title: request.title, message: request.message, preferredStyle: style)
        switch request.kind {
        case .alert:
            alert.addAction(UIAlertAction(title: request.confirmLabel ?? "OK", style: .default) {
                [completion] _ in completion(.success(.completed))
            })
        case .confirm:
            alert.addAction(UIAlertAction(title: request.cancelLabel ?? "Cancel", style: .cancel) {
                [completion] _ in completion(.success(.boolean(false)))
            })
            alert.addAction(UIAlertAction(title: request.confirmLabel ?? "OK", style: .default) {
                [completion] _ in completion(.success(.boolean(true)))
            })
        case .prompt:
            alert.addTextField { [request] textField in
                textField.text = request.defaultValue
                textField.placeholder = request.placeholder
                textField.isSecureTextEntry = request.obscureText
                textField.keyboardType = Self.keyboardType(request.keyboardType)
            }
            alert.addAction(UIAlertAction(title: request.cancelLabel ?? "Cancel", style: .cancel) {
                [completion] _ in completion(.success(.text(nil)))
            })
            alert.addAction(UIAlertAction(title: request.confirmLabel ?? "OK", style: .default) {
                [weak alert, completion] _ in completion(.success(.text(alert?.textFields?.first?.text)))
            })
        case .actionSheet:
            for (index, action) in request.actions.enumerated() {
                alert.addAction(UIAlertAction(
                    title: action.label,
                    style: action.destructive ? .destructive : .default
                ) { [completion] _ in completion(.success(.index(index))) })
            }
            if request.cancelButton {
                alert.addAction(UIAlertAction(title: request.cancelLabel ?? "Cancel", style: .cancel) {
                    [completion] _ in completion(.success(.index(nil)))
                })
            }
            alert.popoverPresentationController?.sourceView = view
            alert.popoverPresentationController?.sourceRect = CGRect(
                x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1
            )
        }
        present(alert, animated: true) { [request, weak alert] in
            guard request.kind == .prompt, request.selectAll else { return }
            alert?.textFields?.first?.selectAll(nil)
        }
    }

    private static func keyboardType(_ value: String?) -> UIKeyboardType {
        switch value {
        case "asciiCapable": .asciiCapable
        case "numbersAndPunctuation": .numbersAndPunctuation
        case "URL": .URL
        case "numberPad": .numberPad
        case "phonePad": .phonePad
        case "namePhonePad": .namePhonePad
        case "emailAddress": .emailAddress
        case "decimalPad": .decimalPad
        case "twitter": .twitter
        case "webSearch": .webSearch
        case "asciiCapableNumberPad": .asciiCapableNumberPad
        default: .default
        }
    }
}

private struct HanlinQuickLookTextPreview: View {
    let text: String
    let completion: (Result<HanlinScriptingSystemUIResult, any Error>) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { doneButton }
        }
    }

    private var doneButton: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { completion(.success(.completed)) }
        }
    }
}

private struct HanlinQuickLookImagePreview: View {
    let image: UIImage
    let completion: (Result<HanlinScriptingSystemUIResult, any Error>) -> Void

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(.black)
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { completion(.success(.completed)) }
                }
            }
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
    let initialDirectory: URL?
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
        picker.directoryURL = initialDirectory
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

private struct HanlinDocumentExportController: UIViewControllerRepresentable {
    let urls: [URL]
    let initialDirectory: URL?
    let completion: (Result<HanlinScriptingSystemUIResult, any Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        picker.delegate = context.coordinator
        picker.directoryURL = initialDirectory
        picker.shouldShowFileExtensions = true
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
