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
    @State private var selectedTools: Set<String> = []
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
            _selectedTools = State(initialValue: [])
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
            _selectedTools = State(initialValue: Set(record.descriptor.preferredToolIDs))
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
                _selectedTools = State(initialValue: Set(existing.descriptor.preferredToolIDs))
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
                _selectedTools = State(initialValue: Set(baseSkill.preferredToolIDs))
                _preferredToolsText = State(initialValue: baseSkill.preferredToolIDs.joined(separator: ", "))
                _triggerHintsText = State(initialValue: baseSkill.triggerHints.joined(separator: ", "))
                _keywordsText = State(initialValue: baseSkill.keywords.joined(separator: ", "))
            }
        }
    }

    private var availableCanonicalTools: [NativeToolCatalogEntry] {
        NativeToolCatalog.shared.ensureBuiltinsRegistered()
        return NativeToolCatalog.shared.allEntries().sorted(by: { $0.name < $1.name })
    }

    private var idValidationError: String? {
        let trimmed = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Identifier is required." }
        guard (try? HanlinSkillID(validating: trimmed)) != nil else {
            return "Invalid Skill ID: use lowercase letters, numbers, hyphens, and underscores."
        }
        if case .create = mode {
            if HanlinSkillCatalog.shared.resolve(rawID: trimmed) != nil {
                return "Skill '\(trimmed)' already exists. Edit or override it instead."
            }
        }
        return nil
    }

    private var titleValidationError: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Title is required."
        }
        return nil
    }

    static let knownSystemToolNames: Set<String> = [
        "save_memory", "retrieve_memory", "update_memory",
        "search_calendar_and_reminders", "write_system_event",
        "query_location", "get_current_location", "search_nearby_locations", "get_route",
        "query_weather",
        "search_online", "read_web_page", "search_arxiv_papers", "extract_remote_file_content",
        "search_knowledge_bag", "create_knowledge_document",
        "create_canvas", "edit_canvas",
        "create_web_view", "execute_remote_python_code", "execute_python_code",
        "fetch_step_details", "fetch_energy_details", "fetch_nutrition_details", "make_nutrition_data"
    ]

    private var allAvailableToolNames: Set<String> {
        var names = Set(availableCanonicalTools.map(\.name))
        names.formUnion(Self.knownSystemToolNames)
        return names
    }

    static func validatePreferredToolAliases(_ aliasesString: String, against availableAliases: Set<String>) -> [String] {
        let tools = aliasesString
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return tools.filter { !availableAliases.contains($0) }
    }

    private var unknownToolAliases: [String] {
        Self.validatePreferredToolAliases(preferredToolsText, against: allAvailableToolNames)
    }

    private var toolValidationError: String? {
        let unknown = unknownToolAliases
        if !unknown.isEmpty {
            return "Unknown canonical tool(s): \(unknown.joined(separator: ", ")). Please select or enter valid canonical tools."
        }
        return nil
    }

    private var isFormValid: Bool {
        idValidationError == nil && titleValidationError == nil && toolValidationError == nil
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
                        if let err = idValidationError {
                            Text(err)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    } else {
                        Text(rawID)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text(SkillL10n.string("Title"))) {
                    TextField(SkillL10n.string("Title"), text: $title)
                        .accessibilityIdentifier("hanlin-skill-editor-name-input")
                    if let err = titleValidationError {
                        Text(err)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
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
                        .accessibilityIdentifier("hanlin-skill-editor-instructions-input")
                }

                Section(header: Text(SkillL10n.string("Preferred Canonical Tools"))) {
                    let entries = availableCanonicalTools
                    if entries.isEmpty {
                        Text("No canonical tools registered.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(entries) { entry in
                            Button {
                                toggleTool(entry.name)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.name)
                                            .font(.system(.subheadline, design: .monospaced))
                                            .foregroundColor(.primary)
                                        Text(entry.title)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if selectedTools.contains(entry.name) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                            .bold()
                                    }
                                }
                            }
                            .accessibilityIdentifier("hanlin-skill-editor-tool-\(entry.name)")
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tool Aliases (comma-separated)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("tool_a, tool_b", text: $preferredToolsText)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("hanlin-skill-editor-tools-input")
                            .onChange(of: preferredToolsText) { _, newText in
                                syncToolsFromText(newText)
                            }
                        if let err = toolValidationError {
                            Text(err)
                                .foregroundColor(.red)
                                .font(.caption)
                                .accessibilityIdentifier("hanlin-skill-editor-tools-error")
                        }
                    }
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
                    .disabled(!isFormValid)
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

    private func toggleTool(_ name: String) {
        if selectedTools.contains(name) {
            selectedTools.remove(name)
        } else {
            selectedTools.insert(name)
        }
        preferredToolsText = selectedTools.sorted().joined(separator: ", ")
    }

    private func syncToolsFromText(_ text: String) {
        let tools = text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        selectedTools = Set(tools)
    }

    private func save() {
        errorMessage = nil
        if let err = toolValidationError {
            errorMessage = err
            return
        }
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

        if case .create = mode, HanlinSkillCatalog.shared.resolve(rawID: trimmedID) != nil {
            errorMessage = "Skill '\(trimmedID)' already exists. Edit or override it instead."
            return
        }

        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveSummary = trimmedSummary.isEmpty ? trimmedTitle : trimmedSummary
        let trimmedInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)

        let tools = Array(selectedTools).sorted()

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
                    description: effectiveSummary,
                    instructions: trimmedInstructions,
                    preferredToolIDs: tools,
                    triggerHints: hints,
                    keywords: keywords
                )
            case .editOverride(let baseSkill, _):
                try SkillStore.shared.createOrUpdateOverride(
                    for: baseSkill,
                    newTitle: trimmedTitle,
                    newDescription: effectiveSummary,
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
