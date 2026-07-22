//
//  ImagePicker.swift
//  AI_HLY
//
//  Created by 哆啦好多梦 on 3/2/25.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// 输入框中的图片获取结构体
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImages: [UIImage] // 存储选定的图片
    var sourceType: UIImagePickerController.SourceType // 选择是相册还是相机
    var maxImageNumber: Int

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        if sourceType == .photoLibrary {
            var config = PHPickerConfiguration()
            config.selectionLimit = maxImageNumber
            config.filter = .images

            let picker = PHPickerViewController(configuration: config)
            picker.delegate = context.coordinator
            return picker
        } else {
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                print("相机不可用")
                return UIViewController()
            }
            
            let picker = UIImagePickerController()
            picker.delegate = context.coordinator
            picker.sourceType = .camera
            return picker
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate, PHPickerViewControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        // 处理相册多选
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            for result in results {
                if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                        guard let data else { return }
                        Task { @MainActor [weak self] in
                            if let image = UIImage(data: data) { self?.parent.selectedImages.append(image) }
                        }
                    }
                }
            }
        }

        // 处理拍照
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                DispatchQueue.main.async {
                    self.parent.selectedImages.append(image) // 添加拍摄的照片
                }
            }
            picker.dismiss(animated: true)
        }
    }
}

// OCR中的图片获取结构体
struct OCRImagePicker: UIViewControllerRepresentable {
    @Binding var ocrImage: UIImage?
    var sourceType: UIImagePickerController.SourceType

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        if sourceType == .photoLibrary {
            var config = PHPickerConfiguration()
            config.selectionLimit = 1
            config.filter = .images

            let picker = PHPickerViewController(configuration: config)
            picker.delegate = context.coordinator
            return picker
        } else {
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                print("相机不可用")
                return UIViewController()
            }
            
            let picker = UIImagePickerController()
            picker.delegate = context.coordinator
            picker.sourceType = .camera
            return picker
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate, PHPickerViewControllerDelegate {
        let parent: OCRImagePicker

        init(_ parent: OCRImagePicker) {
            self.parent = parent
        }

        // 处理相册选择
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            if let provider = results.first?.itemProvider,
               provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor [weak self] in
                        if let image = UIImage(data: data) { self?.parent.ocrImage = image }
                    }
                }
            }
        }

        // 处理拍照
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                DispatchQueue.main.async {
                    self.parent.ocrImage = image
                }
            }
            picker.dismiss(animated: true)
        }
    }
}
