#if canImport(UIKit)
import SwiftUI
import UIKit
import HanlinLocalization
import HanlinPresentationKit

/// Original user/assistant attachment strips and native image menus.
/// The host retains photo-library authority and document routing.
public struct HanlinMessageImageAttachments: View {
    private let images: [UIImage]?
    private let isAssistant: Bool
    private let temporaryRecord: Bool
    private let onOpen: ((UIImage) -> Void)?
    private let copyImage: ((UIImage) -> Void)?
    private let saveImage: ((UIImage) -> Void)?

    public init(images: [UIImage], isAssistant: Bool = false, temporaryRecord: Bool = false,
                onOpen: ((UIImage) -> Void)? = nil, copyImage: ((UIImage) -> Void)? = nil,
                saveImage: ((UIImage) -> Void)? = nil) {
        self.images = images; self.isAssistant = isAssistant
        self.temporaryRecord = temporaryRecord; self.onOpen = onOpen
        self.copyImage = copyImage; self.saveImage = saveImage
    }

    public var body: some View {
        if isAssistant { assistantBody } else { userBody }
    }

    private func imageActions(for image: UIImage) -> [HanlinMessageAction] {
        var actions: [HanlinMessageAction] = []
        if let copyImage {
            actions.append(.init(id: "copy-image",
                title: String(localized: "复制图片", bundle: HanlinLocalization.bundle),
                symbol: "square.on.square") { copyImage(image) })
        }
        if let saveImage {
            actions.append(.init(id: "save-image",
                title: String(localized: "保存图片", bundle: HanlinLocalization.bundle),
                symbol: "square.and.arrow.down") { saveImage(image) })
        }
        return actions
    }

    private var userBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 图片显示区域
            if let images = images, !images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(images.indices, id: \.self) { index in
                            Image(uiImage: images[index])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 120, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .contextMenu {
                                    HanlinMessageActionMenu(actions: imageActions(for: images[index]))
                                }
                                .onTapGesture { onOpen?(images[index]) }
                        }
                    }
                }
                .frame(
                    width: CGFloat(min(Double(images.count), 2.5) * 126 - 6),
                    height: 120
                )
                .cornerRadius(14)
            }
        }
        .padding(6)
        .background(temporaryRecord ? .primary.opacity(0.9) : Color.hanlinHLBlue.opacity(0.9))
        .clipShape(HanlinMessageCorners(topLeft: 20, topRight: 20, bottomLeft: 20, bottomRight: 5))
    }
    private var assistantBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 图片显示区域
            if let images = images, !images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(images.indices, id: \.self) { index in
                            Image(uiImage: images[index])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 200, height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .contextMenu {
                                    HanlinMessageActionMenu(actions: imageActions(for: images[index]))
                                }
                                .onTapGesture { onOpen?(images[index]) }
                        }
                    }
                }
                .frame(
                    width: CGFloat(min(Double(images.count), 2.5) * 206 - 6),
                    height: 200
                )
                .cornerRadius(14)
            }
        }
        .padding(6)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.hanlinHLBluefont.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(20)
    }
}
#endif
