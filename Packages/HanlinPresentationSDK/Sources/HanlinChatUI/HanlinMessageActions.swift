#if canImport(UIKit)
import SwiftUI
import HanlinLocalization

/// The UI owns labels, ordering and presentation. A host supplies only actions
/// it can perform; omitted callbacks never become visible, inert menu entries.
@MainActor
public struct HanlinMessageAction: Identifiable {
    public let id: String
    public let title: String
    public let symbol: String
    public var role: ButtonRole?
    public var isEnabled: Bool
    public let perform: @MainActor () -> Void

    public init(id: String, title: String, symbol: String, role: ButtonRole? = nil,
                isEnabled: Bool = true, perform: @escaping @MainActor () -> Void) {
        self.id = id; self.title = title; self.symbol = symbol
        self.role = role; self.isEnabled = isEnabled; self.perform = perform
    }
}

public struct HanlinMessageActionState: Equatable, Sendable {
    public var isCopied: Bool
    public var copyFeedback: Bool
    public var isSpeechPreparing: Bool
    public var isSpeaking: Bool
    public var isTranslating: Bool
    public var isTranslated: Bool
    public var isPersonallySaved: Bool
    public var canSavePersonal: Bool
    public var isResponding: Bool

    public init(isCopied: Bool = false, copyFeedback: Bool = false,
                isSpeechPreparing: Bool = false, isSpeaking: Bool = false,
                isTranslating: Bool = false, isTranslated: Bool = false,
                isPersonallySaved: Bool = false, canSavePersonal: Bool = true,
                isResponding: Bool = false) {
        self.isCopied = isCopied; self.copyFeedback = copyFeedback
        self.isSpeechPreparing = isSpeechPreparing; self.isSpeaking = isSpeaking
        self.isTranslating = isTranslating; self.isTranslated = isTranslated
        self.isPersonallySaved = isPersonallySaved; self.canSavePersonal = canSavePersonal
        self.isResponding = isResponding
    }
}

@MainActor
public struct HanlinMessageActions {
    public var copy: (() -> Void)?
    public var select: (() -> Void)?
    public var speech: (() -> Void)?
    public var translate: (() -> Void)?
    public var savePersonal: (() -> Void)?
    public var saveKnowledge: (() -> Void)?
    public var delete: (() -> Void)?
    public var retry: (() -> Void)?
    public var continueResponse: (() -> Void)?

    public init(copy: (() -> Void)? = nil, select: (() -> Void)? = nil,
                speech: (() -> Void)? = nil, translate: (() -> Void)? = nil,
                savePersonal: (() -> Void)? = nil, saveKnowledge: (() -> Void)? = nil,
                delete: (() -> Void)? = nil, retry: (() -> Void)? = nil,
                continueResponse: (() -> Void)? = nil) {
        self.copy = copy; self.select = select; self.speech = speech
        self.translate = translate; self.savePersonal = savePersonal
        self.saveKnowledge = saveKnowledge; self.delete = delete
        self.retry = retry; self.continueResponse = continueResponse
    }

    public var userMenu: [HanlinMessageAction] {
        [
            action("copy", "复制内容", "square.on.square", copy),
            action("select", "选择文本", "text.redaction", select),
            action("knowledge", "存为知识", "backpack", saveKnowledge),
            action("delete", "删除消息", "trash", delete)
        ].compactMap { $0 }
    }

    public func assistantMenu(state: HanlinMessageActionState = .init()) -> [HanlinMessageAction] {
        [
            action("copy", "复制内容", "square.on.square", copy),
            action("select", "选择文本", "text.redaction", select),
            action("speech", "生成语音", "waveform", speech),
            action("translate", state.isTranslated ? "删除译文" : "翻译内容",
                   "character.bubble", translate, enabled: !state.isTranslating),
            action("save-personal", "Save for myself", "bookmark",
                   savePersonal, enabled: state.canSavePersonal),
            action("knowledge", "存为知识", "backpack", saveKnowledge),
            action("delete", "删除消息", "trash", delete, role: .destructive)
        ].compactMap { $0 }
    }

    private func action(_ id: String, _ key: String.LocalizationValue, _ symbol: String,
                        _ perform: (() -> Void)?, role: ButtonRole? = nil,
                        enabled: Bool = true) -> HanlinMessageAction? {
        guard let perform else { return nil }
        return .init(id: id, title: String(localized: key, bundle: HanlinLocalization.bundle),
                     symbol: symbol, role: role, isEnabled: enabled) { perform() }
    }
}

/// Original native menu labels and order, reusable by the user bubble and
/// attachment menus without a second host-specific SwiftUI implementation.
public struct HanlinMessageActionMenu: View {
    private let actions: [HanlinMessageAction]
    public init(actions: [HanlinMessageAction]) { self.actions = actions }
    public var body: some View {
        ForEach(actions) { action in
            Button(role: action.role, action: action.perform) {
                Label(action.title, systemImage: action.symbol)
            }
            .disabled(!action.isEnabled)
            .accessibilityIdentifier("hanlin-message-menu-" + action.id)
        }
    }
}
#endif
