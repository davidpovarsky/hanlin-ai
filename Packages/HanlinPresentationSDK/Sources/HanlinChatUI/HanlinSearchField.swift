#if canImport(UIKit)
import SwiftUI
import UIKit
import HanlinPresentationKit

/// A real system search field for inline surfaces which intentionally have no
/// navigation bar (the Morph page and its anchored model popover). Screens in
/// a NavigationStack use SwiftUI.searchable instead.
@MainActor
public struct HanlinSearchField: UIViewRepresentable {
    @Binding private var text: String
    private let prompt: String
    private let identifier: String
    private let tint: Color

    public init(text: Binding<String>, prompt: String,
                accessibilityIdentifier: String, tint: Color = .accentColor) {
        self._text = text
        self.prompt = prompt
        self.identifier = accessibilityIdentifier
        self.tint = tint
    }

    public func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    public func makeUIView(context: Context) -> UISearchTextField {
        let field = UISearchTextField(frame: .zero)
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.returnKeyType = .search
        field.clearButtonMode = .whileEditing
        field.adjustsFontForContentSizeCategory = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        configure(field)
        field.text = text
        return field
    }

    public func updateUIView(_ field: UISearchTextField, context: Context) {
        context.coordinator.text = $text
        configure(field)
        // Never replace marked text while a multi-stage input method composes.
        if field.markedTextRange == nil, (field.text ?? "") != text {
            field.text = text
        }
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: UISearchTextField,
                             context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return nil }
        return CGSize(width: max(0, width), height: max(HanlinControlMetrics.minimumHitTarget, uiView.intrinsicContentSize.height))
    }

    public static func dismantleUIView(_ field: UISearchTextField, coordinator: Coordinator) {
        field.removeTarget(coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.delegate = nil
    }

    private func configure(_ field: UISearchTextField) {
        field.placeholder = prompt
        field.accessibilityLabel = prompt
        field.accessibilityIdentifier = identifier
        field.font = HanlinTypography.uiFont(.body)
        field.tintColor = UIColor(tint)
    }

    @MainActor
    public final class Coordinator: NSObject, UITextFieldDelegate {
        fileprivate var text: Binding<String>
        fileprivate init(text: Binding<String>) { self.text = text }

        @objc fileprivate func changed(_ sender: UITextField) {
            let value = sender.text ?? ""
            if text.wrappedValue != value { text.wrappedValue = value }
        }

        public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}
#endif
