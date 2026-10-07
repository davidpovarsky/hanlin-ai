import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import TorahLibraryKit

public struct TorahPhotoStudyCaptureView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedImage: UIImage?
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var cropRect = CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.6)

    @State private var isProcessing = false
    @State private var ocrText: String = ""
    @State private var identificationStatus: String?
    @State private var identifiedBookTitle: String?
    @State private var identifiedLocator: String?
    @State private var statusMessage: String?
    @State private var isEditingTranscription = false
    @State private var editedText: String = ""

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let image = selectedImage {
                    imagePreviewWithOverlay(image: image)
                } else {
                    placeholderView
                }

                if isProcessing {
                    ProgressView(String(localized: "מזהה קטע ומאתר מקור בספריה..."))
                        .padding()
                }

                if let bookTitle = identifiedBookTitle {
                    resultCardView(title: bookTitle)
                }

                Spacer()

                bottomActionToolbar
            }
            .padding()
            .navigationTitle(String(localized: "צילום ולימוד ספר"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "סגור")) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showPhotoPicker) {
                PhotoPicker(selectedImage: $selectedImage)
            }
            .sheet(isPresented: $showCamera) {
                #if canImport(UIKit)
                CameraPicker(selectedImage: $selectedImage)
                #endif
            }
            .sheet(isPresented: $isEditingTranscription) {
                transcriptionEditorSheet
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var placeholderView: some View {
        VStack(spacing: 20) {
            Image(systemName: "book.pages")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundColor(.secondary)

            Text(String(localized: "צלם קטע מתוך ספר פיזי או בחר תמונה מגלריה"))
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)

            HStack(spacing: 16) {
                Button(action: { showPhotoPicker = true }) {
                    Label(String(localized: "בחר תמונה"), systemImage: "photo.on.rectangle")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func imagePreviewWithOverlay(image: UIImage) -> some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            // Crop Region Overlay
            GeometryReader { geo in
                Rectangle()
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                    .background(Color.accentColor.opacity(0.15))
                    .frame(
                        width: geo.size.width * cropRect.width,
                        height: geo.size.height * cropRect.height
                    )
                    .position(
                        x: geo.size.width * (cropRect.origin.x + cropRect.width / 2),
                        y: geo.size.height * (cropRect.origin.y + cropRect.height / 2)
                    )
            }
        }
        .frame(maxHeight: 280)
    }

    private func resultCardView(title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.green)
                Text(title)
                    .font(.headline)
                Spacer()
                Text(identificationStatus ?? "מאומת")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(6)
            }

            if !ocrText.isEmpty {
                Text(ocrText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            Divider()

            HStack(spacing: 12) {
                Button(action: openHere) {
                    Label(String(localized: "פתח כאן"), systemImage: "book")
                        .font(.subheadline)
                }

                Button(action: openInMaktabah) {
                    Label(String(localized: "פתח ב-Maktabah"), systemImage: "arrow.up.forward.app")
                        .font(.subheadline)
                }

                Spacer()

                Button(action: {
                    editedText = ocrText
                    isEditingTranscription = true
                }) {
                    Image(systemName: "pencil")
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }

    private var bottomActionToolbar: some View {
        HStack(spacing: 12) {
            Button(action: { showPhotoPicker = true }) {
                Label(String(localized: "גלריה"), systemImage: "photo")
            }
            .buttonStyle(.bordered)

            Button(action: { showCamera = true }) {
                Label(String(localized: "צלם"), systemImage: "camera")
            }
            .buttonStyle(.bordered)

            Button(action: processIdentification) {
                Label(String(localized: "זהה מקור"), systemImage: "sparkle.magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedImage == nil || isProcessing)
        }
    }

    private var transcriptionEditorSheet: some View {
        NavigationStack {
            VStack {
                TextEditor(text: $editedText)
                    .padding()
                    .navigationTitle(String(localized: "תיקון תמלול"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(String(localized: "זהה מחדש")) {
                                ocrText = editedText
                                isEditingTranscription = false
                                processIdentificationWithText(editedText)
                            }
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button(String(localized: "ביטול")) {
                                isEditingTranscription = false
                            }
                        }
                    }
            }
        }
    }

    private func processIdentification() {
        #if canImport(UIKit)
        guard let image = selectedImage else { return }
        guard let imageData = image.jpegData(compressionQuality: 0.9) ?? image.pngData() else { return }
        isProcessing = true
        identificationStatus = nil
        identifiedBookTitle = nil
        identifiedLocator = nil

        Task {
            do {
                let region = (
                    x: Double(cropRect.origin.x),
                    y: Double(cropRect.origin.y),
                    width: Double(cropRect.size.width),
                    height: Double(cropRect.size.height)
                )
                let ocrResult = try await TorahOCRService.performLocalOCR(imageData: imageData, region: region)
                let lines = ocrResult.lines.enumerated().map { (idx, item) in
                    OCRLine(
                        lineID: "l\(idx + 1)",
                        rawText: item.text,
                        boundingBox: OCRBoundingBox(x: item.box.x, y: item.box.y, width: item.box.width, height: item.box.height)
                    )
                }

                let evidence = OCREvidence(
                    imageHash: "img_\(UUID().uuidString.prefix(8))",
                    imageWidth: Double(image.size.width),
                    imageHeight: Double(image.size.height),
                    providerID: "apple_vision_local",
                    modelRevision: "v3",
                    rawText: ocrResult.rawText,
                    lines: lines
                )

                let result = await TorahLibraryCoordinator.shared.identifyExcerpt(evidence: evidence)
                await MainActor.run {
                    ocrText = ocrResult.rawText
                    if let top = result.selectedCandidate {
                        identifiedBookTitle = top.workTitle
                        identifiedLocator = top.locator.persistenceKey
                        identificationStatus = result.status == .verified ? "מאומת" : "זוהה (סבירות נמוכה/חלופית)"
                    } else {
                        identificationStatus = "לא נמצא מקור מתאים בספריה"
                    }
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    identificationStatus = "שגיאה בפענוח: \(error.localizedDescription)"
                    isProcessing = false
                }
            }
        }
        #endif
    }

    private func processIdentificationWithText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isProcessing = true

        Task {
            let lines = trimmed.components(separatedBy: "\n").filter { !$0.isEmpty }.enumerated().map { (idx, line) in
                OCRLine(lineID: "l\(idx + 1)", rawText: line, boundingBox: .full)
            }
            let evidence = OCREvidence(
                imageHash: "img_user_edited_\(UUID().uuidString.prefix(8))",
                imageWidth: 1024,
                imageHeight: 1400,
                providerID: "user_corrected",
                modelRevision: "v1",
                rawText: trimmed,
                lines: lines
            )
            let result = await TorahLibraryCoordinator.shared.identifyExcerpt(evidence: evidence)
            await MainActor.run {
                if let top = result.selectedCandidate {
                    identifiedBookTitle = top.workTitle
                    identifiedLocator = top.locator.persistenceKey
                    identificationStatus = result.status == .verified ? "מאומת (לאחר תיקון)" : "זוהה (לאחר תיקון)"
                } else {
                    identificationStatus = "לא נמצא מקור מתאים עבור הטקסט המתוקן"
                }
                isProcessing = false
            }
        }
    }

    private func openHere() {
        guard let locStr = identifiedLocator,
              let locator = SourceLocator.parse(persistenceKey: locStr) else { return }
        let link = TorahStudyDeepLink(action: .open, locator: locator, workTitle: identifiedBookTitle, highlightText: ocrText)
        guard let url = link.url(scheme: "hanlin") else { return }
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }

    private func openInMaktabah() {
        guard let locStr = identifiedLocator,
              let locator = SourceLocator.parse(persistenceKey: locStr) else { return }
        let link = TorahStudyDeepLink(action: .open, locator: locator, workTitle: identifiedBookTitle, highlightText: ocrText)
        guard let url = link.url(scheme: "maktabah") else { return }
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }
}

#if canImport(UIKit)
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            picker.dismiss(animated: true)
            if let image = info[.originalImage] as? UIImage {
                self.parent.selectedImage = image
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
#endif

struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker

        init(_ parent: PhotoPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else { return }
            if provider.hasItemConformingToTypeIdentifier("public.image") {
                provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, _ in
                    guard let data else { return }
                    DispatchQueue.main.async {
                        self.parent.selectedImage = UIImage(data: data)
                    }
                }
            } else if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    guard let image = object as? UIImage,
                          let data = image.jpegData(compressionQuality: 0.95) else { return }
                    DispatchQueue.main.async {
                        self.parent.selectedImage = UIImage(data: data)
                    }
                }
            }
        }
    }
}
