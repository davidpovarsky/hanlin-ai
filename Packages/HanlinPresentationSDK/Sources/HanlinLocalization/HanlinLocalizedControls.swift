#if canImport(SwiftUI)
import SwiftUI

// These initializers forward to the same native controls and original Text labels.
// They only select the SDK table bundle; layout, styles, actions, binding behavior,
// formatting and the host's SwiftUI locale/environment remain with SwiftUI.

public extension Label where Title == Text, Icon == Image {
    @MainActor
    init(hanlin titleKey: LocalizedStringKey, systemImage: String) {
        self.init { Text(titleKey, bundle: HanlinLocalization.bundle) }
            icon: { Image(systemName: systemImage) }
    }
}

public extension Button where Label == Text {
    @MainActor
    init(hanlin titleKey: LocalizedStringKey, role: ButtonRole? = nil,
         action: @escaping @MainActor () -> Void) {
        self.init(role: role, action: action) {
            Text(titleKey, bundle: HanlinLocalization.bundle)
        }
    }
}

public extension Button where Label == SwiftUI.Label<Text, Image> {
    @MainActor
    init(hanlin titleKey: LocalizedStringKey, systemImage: String,
         role: ButtonRole? = nil, action: @escaping @MainActor () -> Void) {
        self.init(role: role, action: action) {
            SwiftUI.Label(hanlin: titleKey, systemImage: systemImage)
        }
    }
}

public extension Toggle where Label == Text {
    @MainActor
    init(hanlin titleKey: LocalizedStringKey, isOn: Binding<Bool>) {
        self.init(isOn: isOn) { Text(titleKey, bundle: HanlinLocalization.bundle) }
    }
}

public extension Picker where Label == Text {
    @MainActor
    init(hanlin titleKey: LocalizedStringKey, selection: Binding<SelectionValue>,
         @ViewBuilder content: () -> Content) {
        self.init(selection: selection, content: content) {
            Text(titleKey, bundle: HanlinLocalization.bundle)
        }
    }
}

public extension Menu where Label == Text {
    @MainActor
    init(hanlin titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(content: content) { Text(titleKey, bundle: HanlinLocalization.bundle) }
    }
}

public extension Menu where Label == SwiftUI.Label<Text, Image> {
    @MainActor
    init(hanlin titleKey: LocalizedStringKey, systemImage: String,
         @ViewBuilder content: () -> Content) {
        self.init(content: content) { SwiftUI.Label(hanlin: titleKey, systemImage: systemImage) }
    }
}

public extension Section where Parent == Text, Footer == EmptyView {
    @MainActor
    init(hanlin titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(content: content) { Text(titleKey, bundle: HanlinLocalization.bundle) }
    }
}

public extension LabeledContent where Label == Text, Content == Text {
    @MainActor
    init<S: StringProtocol>(hanlin titleKey: LocalizedStringKey, value: S) {
        self.init { Text(value) } label: { Text(titleKey, bundle: HanlinLocalization.bundle) }
    }
}

public extension Link where Label == Text {
    @MainActor
    init(hanlin titleKey: LocalizedStringKey, destination: URL) {
        self.init(destination: destination) { Text(titleKey, bundle: HanlinLocalization.bundle) }
    }
}

public extension ProgressView where Label == Text, CurrentValueLabel == EmptyView {
    @MainActor
    init(hanlin titleKey: LocalizedStringKey) {
        self.init { Text(titleKey, bundle: HanlinLocalization.bundle) }
    }
}

public extension TextField where Label == Text {
    @MainActor
    init(hanlin titleKey: LocalizedStringKey, text: Binding<String>) {
        self.init(text: text) { Text(titleKey, bundle: HanlinLocalization.bundle) }
    }
}

public extension DatePicker where Label == Text {
    @MainActor
    init(hanlin titleKey: LocalizedStringKey, selection: Binding<Date>,
         displayedComponents: DatePickerComponents = [.date, .hourAndMinute]) {
        self.init(selection: selection, displayedComponents: displayedComponents) {
            Text(titleKey, bundle: HanlinLocalization.bundle)
        }
    }

    @MainActor
    init(hanlin titleKey: LocalizedStringKey, selection: Binding<Date>,
         in range: PartialRangeFrom<Date>,
         displayedComponents: DatePickerComponents = [.date, .hourAndMinute]) {
        self.init(selection: selection, in: range, displayedComponents: displayedComponents) {
            Text(titleKey, bundle: HanlinLocalization.bundle)
        }
    }
}

public extension ContentUnavailableView where Label == SwiftUI.Label<Text, Image>,
    Description == Text?, Actions == EmptyView {
    @MainActor
    init(hanlin titleKey: LocalizedStringKey, systemImage: String, description: Text? = nil) {
        self.init {
            SwiftUI.Label(hanlin: titleKey, systemImage: systemImage)
        } description: {
            description
        } actions: {
            EmptyView()
        }
    }
}
#endif
