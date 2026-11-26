#if canImport(UIKit)
import SwiftUI
import UIKit
import HanlinLocalization
import HanlinPresentationKit

/// The original message selection sheet and controls. A host injects its
/// source-aware Markdown document and real text services, never a new renderer.
public struct HanlinMessageSelectionView<Document: View>: View {
    private let text: String
    private let document: Document
    private let writingActions: [HanlinMessageAction]
    private let saveKnowledge: (() -> Void)?
    private let copy: (() -> Void)?
    private let isCopy: Bool
    private let isSaved: Bool
    @Binding private var shouldSelectAll: Bool
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var size_16: CGFloat = 16
    private let buttonSize: CGFloat = 36

    public init(text: String, shouldSelectAll: Binding<Bool>,
                isCopied: Bool = false, isSaved: Bool = false,
                writingActions: [HanlinMessageAction] = [],
                saveKnowledge: (() -> Void)? = nil, copy: (() -> Void)? = nil,
                @ViewBuilder document: () -> Document) {
        self.text = text; self._shouldSelectAll = shouldSelectAll
        self.isCopy = isCopied; self.isSaved = isSaved
        self.writingActions = writingActions; self.saveKnowledge = saveKnowledge
        self.copy = copy; self.document = document()
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            NavigationStack {
                document
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle(Text("选择文本", bundle: HanlinLocalization.bundle))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(hanlin: "Done") { dismiss() }
                                .accessibilityIdentifier("hanlin-text-selection-done")
                        }
                    }
            }

            // Text utilities belong to the selected message, not permanent Home buttons.
            HStack(spacing: 12) {
                if !writingActions.isEmpty {
                    Menu {
                        ForEach(writingActions) { action in
                            Button(action.title, action: action.perform)
                                .disabled(!action.isEnabled)
                                .accessibilityIdentifier("hanlin-text-action-" + action.id)
                        }
                    } label: {
                        Image(systemName: "wand.and.stars")
                            .font(HanlinTypography.fixed(size: size_16, weight: .medium))
                            .frame(width: buttonSize, height: buttonSize)
                    }
                    .accessibilityLabel(String(localized: "Text actions", bundle: HanlinLocalization.bundle))
                    .accessibilityIdentifier("hanlin-text-actions-menu")
                    .disabled(text.isEmpty)
                }
                // 全选按钮：点击后将 shouldSelectAll 置为 true
                Button(action: {
                    shouldSelectAll = true
                }) {
                    Image(systemName: "character.cursor.ibeam")
                        .font(HanlinTypography.fixed(size: size_16, weight: .medium))
                        .foregroundColor(.hanlinHLBluefont)
                        .frame(width: buttonSize, height: buttonSize)
                }
                .background(
                    HanlinVisualEffectBlur(style: .systemThinMaterial)
                        .clipShape(Circle())
                        .shadow(color: .hanlinHLBlue, radius: 1)
                )
                .hanlinFeedback(.success, trigger: shouldSelectAll)

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
