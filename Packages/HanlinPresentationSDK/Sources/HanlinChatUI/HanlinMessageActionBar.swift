#if canImport(UIKit)
import SwiftUI
import UIKit
import HanlinLocalization
import HanlinPresentationKit

/// The original Hanlin action row, extracted without replacing its controls,
/// animations or identifiers. Services, persistence and errors stay with hosts.
public struct HanlinMessageActionBar: View {
    public let actions: HanlinMessageActions
    public let state: HanlinMessageActionState
    @ScaledMetric(relativeTo: .body) private var size_12: CGFloat = 12
    @ScaledMetric(relativeTo: .body) private var size_14: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var size_15: CGFloat = 15
    @ScaledMetric(relativeTo: .body) private var size_16: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var size_20: CGFloat = 20
    @ScaledMetric(relativeTo: .body) private var size_24: CGFloat = 24

    public init(actions: HanlinMessageActions, state: HanlinMessageActionState = .init()) {
        self.actions = actions; self.state = state
    }

    private var isCopy: Bool { state.isCopied }
    private var isSuccess: Bool { state.copyFeedback }
    private var isSpeechPreparing: Bool { state.isSpeechPreparing }
    private var isSpeaking: Bool { state.isSpeaking }
    private var isTranslating: Bool { state.isTranslating }
    private var translated: Bool { state.isTranslated }
    private var isPersonallySaved: Bool { state.isPersonallySaved }
    private var isResponding: Bool { state.isResponding }

    public var body: some View {
        HStack(spacing: 8) {
            // 复制按钮
            if let copy = actions.copy {
            Button(action: copy) {
                Image(systemName: isCopy ? "checkmark.circle" : "square.on.square")
                    .font(HanlinTypography.fixed(size: size_15, weight: .medium))
                    .foregroundColor(isCopy ? Color.hanlinHLGreen : .secondary)
                    .frame(width: size_24, height: size_24)
                    .clipShape(Circle())
                    .scaleEffect(isCopy ? 1.2 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCopy)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier("hanlin-action-copy")
            .hanlinFeedback(.success, trigger: isSuccess)

            if isCopy {
                Text("已复制", bundle: HanlinLocalization.bundle)
                    .font(HanlinTypography.fixed(size: size_12, weight: .medium))
                    .foregroundColor(.hanlinHLGreen)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }

            }

            // 选择文本
            if let select = actions.select {
            Button(action: select) {
                Image(systemName: "text.redaction")
                    .font(HanlinTypography.fixed(size: size_15, weight: .medium))
                    .frame(width: size_24, height: size_24)
                    .foregroundColor(.secondary)
                    .clipShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier("hanlin-action-select")

            }

            // 语音朗读
            if let speech = actions.speech {
            Button(action: speech) {
                if isSpeechPreparing {
                    ProgressView()
                        .scaledToFit()
                        .padding(2)
                        .frame(width: size_24, height: size_24)
                        .foregroundColor(.secondary)
                        .clipShape(Circle())
                        .tint(.hanlinHLBluefont)
                } else {
                    Image(systemName: isSpeaking ? "pause.circle" : "waveform")
                        .font(HanlinTypography.fixed(size: size_16, weight: .medium))
                        .frame(width: size_24, height: size_24)
                        .foregroundColor(isSpeaking ? Color(.systemRed) : .secondary)
                        .clipShape(Circle())
                        .scaleEffect(isSpeaking ? 1.2 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSpeaking)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier("hanlin-action-tts")

            if isSpeechPreparing {
                Text("正在请求", bundle: HanlinLocalization.bundle)
                    .font(HanlinTypography.fixed(size: size_12, weight: .medium))
                    .foregroundColor(.hanlinHLBluefont)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }

            }

            // 翻译按钮
            if let translate = actions.translate {
            Button(action: translate) {
                if isTranslating {
                    ProgressView()
                        .scaledToFit()
                        .padding(2)
                        .frame(width: size_24, height: size_24)
                        .foregroundColor(.secondary)
                        .clipShape(Circle())
                        .tint(.hanlinHLBluefont)
                } else if translated {
                    ZStack(alignment: .center) {
                        Image(hanlinAsset: "translate")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .padding(2)
                            .frame(width: size_20, height: size_20)
                            .foregroundColor(.secondary)
                            .clipShape(Circle())

                        Image(systemName: "line.diagonal")
                            .font(HanlinTypography.fixed(size: size_20))
                            .frame(width: size_24, height: size_24)
                            .foregroundColor(.hanlinHLRed)
                            .rotationEffect(.degrees(90))
                            .background(
                                Circle()
                                    .fill(Color(.systemBackground).opacity(0.5))
                                    .frame(width: size_24, height: size_24)
                            )
                    }
                } else {
                    Image(hanlinAsset: "translate")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .padding(2)
                        .frame(width: size_24, height: size_24)
                        .foregroundColor(.secondary)
                        .clipShape(Circle())
                }
            }
            .disabled(isTranslating)
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier("hanlin-action-translate")

            if isTranslating {
                Text("正在翻译", bundle: HanlinLocalization.bundle)
                    .font(HanlinTypography.fixed(size: size_12, weight: .medium))
                    .foregroundColor(.hanlinHLBluefont)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }

            }

            if let savePersonal = actions.savePersonal {
            Button(action: savePersonal) {
                Image(systemName: isPersonallySaved ? "bookmark.fill" : "bookmark")
                    .font(HanlinTypography.fixed(size: size_16, weight: .medium))
                    .frame(width: size_24, height: size_24)
                    .foregroundStyle(isPersonallySaved ? Color.hanlinHLBluefont : .secondary)
            }
            .disabled(!state.canSavePersonal)
            .accessibilityLabel(String(localized: "Save for myself", bundle: HanlinLocalization.bundle))
            .accessibilityIdentifier("hanlin-action-save-personal")

            }

            // 背包按钮
            if let saveKnowledge = actions.saveKnowledge {
            Button(action: saveKnowledge) {
                Image(systemName: "backpack")
                    .font(HanlinTypography.fixed(size: size_14, weight: .medium))
                    .frame(width: size_24, height: size_24)
                    .foregroundColor(.secondary)
                    .clipShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier("hanlin-action-knowledge")

            }

            if let onContinue = actions.continueResponse {
                Button(String(localized: "Continue", bundle: HanlinLocalization.bundle), systemImage: "arrow.right") { onContinue() }
                    .font(HanlinTypography.caption)
                    .disabled(isResponding)
                    .accessibilityIdentifier("hanlin-action-continue")
            }

            // 重新请求
            if let retryAction = actions.retry {
                Button(action: retryAction) {
                    Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                        .font(HanlinTypography.fixed(size: size_15, weight: .medium))
                        .frame(width: size_24, height: size_24)
                        .foregroundColor(.secondary)
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("hanlin-action-retry")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-action-buttons-row")
        .padding(.leading, 5)
        .animation(
            .spring(response: 0.8, dampingFraction: 0.9, blendDuration: 0.5),
            value: [isPersonallySaved, isTranslating, isCopy, isSpeechPreparing]
        )
    }
}
#endif
