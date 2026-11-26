#if canImport(UIKit)
import SwiftUI
import UIKit
import HanlinLocalization
import HanlinPresentationKit

/// Original full document text and action controls. Persistence stays in the host.
public struct HanlinFileContentView: View {
    private let content: String
    private let isCopy: Bool
    private let isSaved: Bool
    private let saveKnowledge: (() -> Void)?
    private let copy: (() -> Void)?
    @ScaledMetric(relativeTo: .body) private var size_16: CGFloat = 16
    private let buttonSize: CGFloat = 36

    public init(content: String, isCopied: Bool = false, isSaved: Bool = false,
                saveKnowledge: (() -> Void)? = nil, copy: (() -> Void)? = nil) {
        self.content = content; self.isCopy = isCopied; self.isSaved = isSaved
        self.saveKnowledge = saveKnowledge; self.copy = copy
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            NavigationStack {
                ScrollView {
                    Text(content)
                        .frame(maxWidth: .infinity, alignment: .topLeading) // 左上角对齐
                        .padding()
                        .textSelection(.enabled)
                }
                .navigationTitle(Text("文件文本", bundle: HanlinLocalization.bundle))
                .navigationBarTitleDisplayMode(.inline)
            }

            // 右下角按钮区域
            HStack(spacing: 12) {
                // 存为知识按钮：点击后图标从“backpack.circle”切换到“checkmark.circle”
                if let saveKnowledge {
                Button(action: saveKnowledge) {
                    Image(systemName: isSaved ? "checkmark" : "backpack")
                        .font(HanlinTypography.fixed(size: size_16, weight: .medium))
                        .foregroundColor(isSaved ? .hanlinHLGreen : .hanlinHLBluefont)
                        .frame(width: buttonSize, height: buttonSize)
                }
                .background(
                    HanlinVisualEffectBlur(style: .systemUltraThinMaterial)
                        .clipShape(Circle())
                        .shadow(color: isSaved ? .hanlinHLGreen : .hanlinHLBlue, radius: 1)
                )
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isSaved)
                .hanlinFeedback(.success, trigger: isSaved)

                }

                // 复制按钮：点击后图标从“rectangle.on.rectangle.circle”切换到“checkmark.circle”
                if let copy {
                Button(action: copy) {
                    Image(systemName: isCopy ? "checkmark" : "square.on.square")
                        .font(HanlinTypography.fixed(size: size_16, weight: .medium))
                        .foregroundColor(isCopy ? .hanlinHLGreen : .hanlinHLBluefont)
                        .frame(width: buttonSize, height: buttonSize)
                }
                .background(
                    HanlinVisualEffectBlur(style: .systemUltraThinMaterial)
                        .clipShape(Circle())
                        .shadow(color: isCopy ? .hanlinHLGreen : .hanlinHLBlue, radius: 1)
                )
                .hanlinFeedback(.success, trigger: isCopy)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCopy)
                }
            }
            .padding()
            .padding(.horizontal)
        }
    }
}
#endif
