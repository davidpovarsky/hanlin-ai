import SwiftUI
import HanlinLocalization
import HanlinPlatformContracts

/// Configuration is edited in the host's existing composer surface. A custom
/// panel receives only a value binding; no tool is invoked by this view.
public struct HanlinCapabilityConfigurationView<CustomPanel: View>: View {
    public let capability: HanlinComposerCapabilityDescriptor
    @Binding private var attachment: HanlinCapabilityAttachment
    private let customPanel: (String, Binding<HanlinJSONValue>) -> CustomPanel
    private let supportsCustomPanel: (String) -> Bool
    private let onDone: () -> Void
    @State private var selectedPanelID: String

    public init(
        capability: HanlinComposerCapabilityDescriptor,
        attachment: Binding<HanlinCapabilityAttachment>,
        supportsCustomPanel: @escaping (String) -> Bool = { _ in true },
        onDone: @escaping () -> Void,
        @ViewBuilder customPanel: @escaping (String, Binding<HanlinJSONValue>) -> CustomPanel
    ) {
        self.capability = capability
        self._attachment = attachment
        self.supportsCustomPanel = supportsCustomPanel
        self.onDone = onDone
        self.customPanel = customPanel
        _selectedPanelID = State(initialValue: capability.configuration?.panels.first?.id ?? "")
    }

    private var panels: [HanlinComposerPanel] { capability.configuration?.panels ?? [] }
    private var selectedPanel: HanlinComposerPanel? {
        panels.first { $0.id == selectedPanelID } ?? panels.first
    }
    private var issues: [HanlinComposerValidationIssue] {
        capability.validationIssues(for: attachment)
    }
    private var hasUnsupportedPanel: Bool {
        panels.contains { panel in
            if let id = panel.customViewID { return !supportsCustomPanel(id) }
            return false
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(capability.title, systemImage: capability.systemImage).font(.headline)
            if !capability.summary.isEmpty {
                Text(capability.summary).font(.subheadline).foregroundStyle(.secondary)
            }
            if !capability.actions.isEmpty {
                Picker(String(localized: "hanlin.composer.capabilities.action", bundle: HanlinLocalization.bundle),
                       selection: $attachment.actionID) {
                    Text("hanlin.composer.capabilities.chooseActionAutomatically", bundle: HanlinLocalization.bundle)
                        .tag(nil as String?)
                    ForEach(capability.actions) { action in
                        Text(action.title).tag(Optional(action.id))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("hanlin-capability-action")
            }
            if panels.count > 1 {
                Picker(String(localized: "hanlin.composer.capabilities.options", bundle: HanlinLocalization.bundle),
                       selection: $selectedPanelID) {
                    ForEach(panels) { panel in Text(panel.title).tag(panel.id) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("hanlin-capability-panel")
            }
            if let panel = selectedPanel {
                if panels.count == 1 { Text(panel.title).font(.subheadline.weight(.semibold)) }
                if let customViewID = panel.customViewID {
                    customPanel(customViewID, $attachment.configuration)
                        .accessibilityIdentifier("hanlin-capability-custom-panel")
                }
                ForEach(panel.fields) { field in
                    HanlinCapabilityFieldView(field: field, configuration: $attachment.configuration)
                }
            }
            if panels.isEmpty && capability.actions.isEmpty {
                Text("hanlin.composer.capabilities.attachedExplanation", bundle: HanlinLocalization.bundle)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(issues) { issue in
                Label(issue.message, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.red)
            }
            Button(action: onDone) {
                Text("hanlin.composer.capabilities.done", bundle: HanlinLocalization.bundle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!issues.isEmpty || hasUnsupportedPanel)
            .accessibilityIdentifier("hanlin-capability-configuration-done")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-capability-configuration")
    }
}

extension HanlinCapabilityConfigurationView where CustomPanel == Text {
    public init(capability: HanlinComposerCapabilityDescriptor,
                attachment: Binding<HanlinCapabilityAttachment>,
                onDone: @escaping () -> Void) {
        self.init(capability: capability, attachment: attachment,
                  supportsCustomPanel: { _ in false }, onDone: onDone) { _, _ in
            Text("hanlin.composer.capabilities.customUnavailable", bundle: HanlinLocalization.bundle)
        }
    }
}

private struct HanlinCapabilityFieldView: View {
    let field: HanlinComposerField
    @Binding var configuration: HanlinJSONValue

    private var value: HanlinJSONValue? {
        guard case let .object(values) = configuration else { return nil }
        return values[field.key]
    }

    private func setValue(_ value: HanlinJSONValue?) {
        var values: HanlinObject<HanlinJSONValue>
        if case let .object(existing) = configuration { values = existing } else { values = [:] }
        values[field.key] = value
        configuration = .object(values)
    }

    private var stringValue: Binding<String> {
        Binding(get: { if case let .string(text)? = value { text } else { "" } },
                set: { setValue($0.isEmpty && !field.required ? nil : .string($0)) })
    }

    private var numericValue: Binding<HanlinJSONValue?> {
        Binding(get: { value }, set: setValue)
    }

    var body: some View {
        Group {
            switch field.kind {
            case .text:
                LabeledContent(field.title) {
                    TextField(field.placeholder ?? field.title, text: stringValue, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("hanlin-capability-input-\(field.key)")
                }
            case .toggle:
                Toggle(field.title, isOn: Binding(
                    get: { if case let .bool(flag)? = value { flag } else { false } },
                    set: { setValue(.bool($0)) }))
            case .number:
                HanlinCapabilityNumberField(title: field.title, value: numericValue,
                                            accessibilityID: "hanlin-capability-input-\(field.key)")
            case .choice:
                Picker(field.title, selection: stringValue) {
                    Text("hanlin.composer.capabilities.noSelection", bundle: HanlinLocalization.bundle).tag("")
                    ForEach(field.options) { option in Text(option.title).tag(option.id) }
                }
                .pickerStyle(.menu)
            case .multiChoice:
                GroupBox(field.title) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(field.options) { option in selectionToggle(option) }
                    }
                }
            case .catalog:
                GroupBox(field.title) {
                    VStack(alignment: .leading, spacing: 8) {
                        OutlineGroup(field.options, children: \.composerChildren) { option in
                            selectionToggle(option)
                        }
                    }
                }
            case .location:
                HanlinCapabilityLocationField(title: field.title, fieldKey: field.key, value: numericValue,
                                              minimumRadius: field.minimum, maximumRadius: field.maximum)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-capability-field-\(field.key)")
    }

    private func selectionToggle(_ option: HanlinComposerOption) -> some View {
        Toggle(option.title, isOn: Binding(
            get: {
                guard case let .array(items)? = value else { return false }
                return items.contains(.string(option.id))
            },
            set: { selected in
                var items: [HanlinJSONValue]
                if case let .array(existing)? = value { items = existing } else { items = [] }
                items.removeAll { $0 == .string(option.id) }
                if selected { items.append(.string(option.id)) }
                setValue(.array(items))
            }
        ))
        .toggleStyle(.switch)
        .accessibilityIdentifier("hanlin-capability-option-\(field.key)-\(option.id)")
    }
}

private extension HanlinComposerOption {
    var composerChildren: [HanlinComposerOption]? { children.isEmpty ? nil : children }
}

/// Retains invalid intermediate text as a string value so schema validation
/// cannot silently send an older number while the field shows invalid input.
struct HanlinCapabilityNumberField: View {
    let title: String
    @Binding var value: HanlinJSONValue?
    var accessibilityID: String = ""

    private var text: Binding<String> {
        Binding(get: {
            if case let .string(raw)? = value { return raw }
            if let number = value?.composerNumber { return number.formatted(.number.grouping(.never)) }
            return ""
        }, set: { raw in
            if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                value = nil
            } else {
                // Parsing validates the entire string and respects the user's locale.
                if let number = try? Double(raw, format: .number.locale(.current), lenient: false), number.isFinite {
                    value = .number(number)
                } else {
                    value = .string(raw)
                }
            }
        })
    }

    var body: some View {
        LabeledContent(title) {
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(accessibilityID)
                #if canImport(UIKit)
                .keyboardType(.numbersAndPunctuation)
                #endif
        }
    }
}
