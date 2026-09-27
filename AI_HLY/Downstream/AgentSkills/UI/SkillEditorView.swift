import SwiftUI
import HanlinPlatformContracts

enum SkillEditorMode: Identifiable {
    case create
    case editCustom(StoredSkillRecord)
    case editOverride(baseSkill: HanlinSkillDescriptor, existingOverride: StoredSkillRecord?)

    var id: String {
        switch self {
        case .create: return "create"
        case .editCustom(let record): return "editCustom:\(record.descriptor.id.rawValue)"
        case .editOverride(let base, _): return "editOverride:\(base.id.rawValue)"
        }
    }
}

@MainActor
struct SkillEditorView: View {
    let mode: SkillEditorMode
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var rawID: String = ""
    @State private var title: String = ""
    @State private var summary: String = ""
    @State private var instructions: String = ""
    @State private var preferredToolsText: String = ""
    @State private var triggerHintsText: String = ""
    @State private var keywordsText: String = ""
    @State private var errorMessage: String? = nil

    init(mode: SkillEditorMode, onSaved: @escaping () -> Void = {}) {
        self.mode = mode
        self.onSaved = onSaved
        switch mode {
        case .create:
            _rawID = State(initialValue: "")
            _title = State(initialValue: "")
            _summary = State(initialValue: "")
            _instructions = State(initialValue: "")
            _preferredToolsText = State(initialValue: "")
            _triggerHintsText = State(initialValue: "")
            _keywordsText = State(initialValue: "")

        case .editCustom(let record):
            _rawID = State(initialValue: record.descriptor.id.rawValue)
            _title = State(initialValue: record.descriptor.title.preferredValue())
            _summary = State(initialValue: record.descriptor.summary.preferredValue())
            let bodyText: String
            if case .inline(let t) = record.descriptor.instructions {
                bodyText = t
            } else {
                bodyText = ""
            }
            _instructions = State(initialValue: bodyText)
            _preferredToolsText = State(initialValue: record.descriptor.preferredToolIDs.joined(separator: ", "))
            _triggerHintsText = State(initialValue: record.descriptor.triggerHints.joined(separator: ", "))
            _keywordsText = State(initialValue: record.descriptor.keywords.joined(separator: ", "))

        case .editOverride(let baseSkill, let existingOverride):
            _rawID = State(initialValue: baseSkill.id.rawValue)
            if let existing = existingOverride {
                _title = State(initialValue: existing.descriptor.title.preferredValue())
                _summary = State(initialValue: existing.descriptor.summary.preferredValue())
                let bodyText: String
                if case .inline(let t) = existing.descriptor.instructions {
                    bodyText = t
                } else {
                    bodyText = ""
                }
                _instructions = State(initialValue: bodyText)
                _preferredToolsText = State(initialValue: existing.descriptor.preferredToolIDs.joined(separator: ", "))
                _triggerHintsText = State(initialValue: existing.descriptor.triggerHints.joined(separator: ", "))
                _keywordsText = State(initialValue: existing.descriptor.keywords.joined(separator: ", "))
            } else {
                _title = State(initialValue: baseSkill.title.preferredValue())
                _summary = State(initialValue: baseSkill.summary.preferredValue())
                let bodyText: String
                if case .inline(let t) = baseSkill.instructions {
                    bodyText = t
                } else {
                    bodyText = ""
                }
                _instructions = State(initialValue: bodyText)
                _preferredToolsText = State(initialValue: baseSkill.preferredToolIDs.joined(separator: ", "))
                _triggerHintsText = State(initialValue: baseSkill.triggerHints.joined(separator: ", "))
                _keywordsText = State(initialValue: baseSkill.keywords.joined(separator: ", "))
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }

                Section(header: Text(SkillL10n.string("Identifier"))) {
                    if case .create = mode {
                        TextField("my-skill-id", text: $rawID)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("hanlin-skill-editor-id-input")
                    } else {
                        Text(rawID)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text(SkillL10n.string("Title"))) {
                    TextField(SkillL10n.string("Title"), text: $title)
                        .accessibilityIdentifier("hanlin-skill-editor-name-input")
                }

                Section(header: Text(SkillL10n.string("Description"))) {
                    TextField(SkillL10n.string("Description"), text: $summary, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("hanlin-skill-editor-desc-input")
                }

                Section(header: Text(SkillL10n.string("Instructions"))) {
                    TextEditor(text: $instructions)
                        .frame(minHeight: 180)
                        .font(.body)
                        .accessibilityIdentifier("hanlin-skill-editor-body-input")
                }

                Section(header: Text(SkillL10n.string("Preferred Tool Aliases (comma-separated)"))) {
                    TextField("tool_a, tool_b", text: $preferredToolsText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("hanlin-skill-editor-tools-input")
                }

                Section(header: Text(SkillL10n.string("Trigger Hints (comma-separated)"))) {
                    TextField("hint1, hint2", text: $triggerHintsText)
                }

                Section(header: Text(SkillL10n.string("Keywords (comma-separated)"))) {
                    TextField("keyword1, keyword2", text: $keywordsText)
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(SkillL10n.string("Cancel")) {
                        dismiss()
                    }
                    .accessibilityIdentifier("hanlin-skill-editor-cancel-button")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(SkillL10n.string("Save")) {
                        save()
                    }
                    .bold()
                    .accessibilityIdentifier("hanlin-skill-editor-save-button")
                }
            }
        }
    }

    private var navTitle: String {
        switch mode {
        case .create: return SkillL10n.string("Create Skill")
        case .editCustom: return SkillL10n.string("Edit Skill")
        case .editOverride: return SkillL10n.string("Customize (Override)")
        }
    }

    private func save() {
        errorMessage = nil
        let trimmedID = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let skillID = try? HanlinSkillID(validating: trimmedID) else {
            errorMessage = "Invalid Skill ID '\(trimmedID)'. Use lowercase alphanumeric, dashes or underscores."
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            errorMessage = "Title cannot be empty."
            return
        }

        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)

        let tools = preferredToolsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let hints = triggerHintsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let keywords = keywordsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        do {
            switch mode {
            case .create, .editCustom:
                try SkillStore.shared.saveCustomSkill(
                    id: skillID,
                    title: trimmedTitle,
                    description: trimmedSummary,
                    instructions: trimmedInstructions,
                    preferredToolIDs: tools,
                    triggerHints: hints,
                    keywords: keywords
                )
            case .editOverride(let baseSkill, _):
                try SkillStore.shared.createOrUpdateOverride(
                    for: baseSkill,
                    newTitle: trimmedTitle,
                    newDescription: trimmedSummary,
                    newInstructions: trimmedInstructions,
                    preferredToolIDs: tools,
                    triggerHints: hints,
                    keywords: keywords
                )
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
