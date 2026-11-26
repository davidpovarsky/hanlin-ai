#if canImport(UIKit)
import SwiftUI
import UIKit
import HanlinLocalization
import HanlinPresentationKit

/// Original document attachment cards; the host owns access and opening.
public struct HanlinMessageDocumentAttachments: View {
    private let documents: [URL]?
    private let temporaryRecord: Bool
    private let onOpen: (() -> Void)?
    public init(documents: [URL], temporaryRecord: Bool = false, onOpen: (() -> Void)? = nil) {
        self.documents = documents; self.temporaryRecord = temporaryRecord; self.onOpen = onOpen
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let documents = documents, !documents.isEmpty {
                VStack(spacing: 6) {
                    ForEach(documents, id: \.self) { documentURL in
                        HStack(spacing: 6) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(fileColor(for: documentURL.pathExtension))
                                    .frame(width: 34, height: 34)

                                Image(systemName: fileIcon(for: documentURL.pathExtension))
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 24, height: 24)
                                    .foregroundColor(.white)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(documentURL.deletingPathExtension().lastPathComponent)
                                    .font(HanlinTypography.caption)
                                    .foregroundColor(.primary)
                                    .lineLimit(1) // 限制为 1 行
                                    .truncationMode(.tail) // 文字过长时显示省略号
                                Text(documentURL.pathExtension.uppercased())
                                    .font(HanlinTypography.caption2)
                                    .foregroundColor(.primary)
                                    .lineLimit(1) // 限制为 1 行
                                    .truncationMode(.tail) // 文字过长时显示省略号
                            }
                        }
                        .padding(8)
                        .frame(width: 180, alignment: .leading)
                        .background(Color(.systemBackground).opacity(0.9))
                        .cornerRadius(14)
                    }
                }
                .onTapGesture { onOpen?() }
                .contextMenu {
                    if let onOpen {
                        Button(action: onOpen) {
                            Label(hanlin: "文件文本", systemImage: "text.document")
                        }
                    }
                }
                .cornerRadius(14)
            }
        }
        .padding(6)
        .background(temporaryRecord ? .primary.opacity(0.8) : Color.hanlinHLBlue.opacity(0.8))
        .clipShape(HanlinMessageCorners(topLeft: 20, topRight: 20, bottomLeft: 20, bottomRight: 5))
    }

    private func fileColor(for fileExtension: String) -> Color {
        switch fileExtension.lowercased() {
        case "pdf":
            return Color.hanlinHLRed.opacity(0.9)
        case "doc", "docx":
            return Color.hanlinHLBluefont.opacity(0.9)
        case "ppt", "pptx":
            return Color.hanlinHLOrange.opacity(0.9)
        case "xls", "xlsx":
            return Color.hanlinHLGreen.opacity(0.9)
        case "txt", "md", "json":
            return Color.hanlinHLBrown.opacity(0.9)
        default:
            return Color.hanlinHLBluefont.opacity(0.9)
        }
    }

    // 文件图标
    private func fileIcon(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "pdf":
            return "text.rectangle.page"
        case "doc", "docx":
            return "doc.text"
        case "ppt", "pptx":
            return "richtext.page"
        case "xls", "xlsx":
            return "chart.bar.horizontal.page"
        case "txt", "md", "json":
            return "text.page"
        default:
            return "doc" // 其他默认文档
        }
    }

}
#endif
