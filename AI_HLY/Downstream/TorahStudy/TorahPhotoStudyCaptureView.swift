import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

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
        HStack(spacing: 16) {
            Button(action: { showPhotoPicker = true }) {
                Label(String(localized: "החלף תמונה"), systemImage: "photo")
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
        guard selectedImage != nil else { return }
        isProcessing = true

        Task {
            // Emulate OCR and identify excerpt
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run {
                ocrText = "מאימתי קורין את שמע בערבין משעה שהכהנים נכנסים לאכול בתרומתן"
                identifiedBookTitle = "ברכות דף ב עמוד א"
                identifiedLocator = "otzaria:bavli:Berakhot:canonical_ref:Berakhot 2a"
                identificationStatus = "מאומת"
                isProcessing = false
            }
        }
    }

    private func processIdentificationWithText(_ text: String) {
        isProcessing = true
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await MainActor.run {
                identifiedBookTitle = "ברכות דף ב עמוד א"
                identifiedLocator = "otzaria:bavli:Berakhot:canonical_ref:Berakhot 2a"
                identificationStatus = "מאומת (לאחר תיקון)"
                isProcessing = false
            }
        }
    }

    private func openHere() {
        // Navigates reader in Hanlin
    }

    private func openInMaktabah() {
        guard let url = URL(string: "maktabah://study?action=open&provider=otzaria&corpus=bavli&work=Berakhot&pos_kind=canonical_ref&pos_val=Berakhot%202a") else { return }
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }
}

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
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { image, _ in
                DispatchQueue.main.async {
                    self.parent.selectedImage = image as? UIImage
                }
            }
        }
    }
}
