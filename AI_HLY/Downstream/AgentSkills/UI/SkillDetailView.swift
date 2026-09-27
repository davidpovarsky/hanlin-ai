import SwiftUI
import HanlinPlatformContracts

@MainActor
struct SkillDetailView: View {
    let skillID: HanlinSkillID

    @State private var descriptor: HanlinSkillDescriptor?
    @State private var record: StoredSkillRecord?
    @State private var instructionsText: String = ""
    @State private var isEnabled: Bool = true
    @State private var isOverride: Bool = false
    @State private var isCustomOrImported: Bool = false
    @State private var resources: [SkillResourceFile] = []

    @State private var showEditor: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var previewResource: SkillResourceFile?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            headerSection
            statusSection
            summarySection
            instructionsSection
            preferredToolsSection
            resourcesSection
            actionsSection
        }
        .navigationTitle(descriptor?.title.preferredValue() ?? skillID.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadSkillData()
        }
        .sheet(isPresented: $showEditor) {
            editorSheet
        }
        .sheet(item: $previewResource) { res in
            resourcePreviewSheet(res)
        }
        .confirmationDialog(
            SkillL10n.string("Delete Skill"),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(SkillL10n.string("Delete"), role: .destructive) {
                deleteSkill()
            }
            Button(SkillL10n.string("Cancel"), role: .cancel) {}
        } message: {
            Text(SkillL10n.string("Are you sure you want to delete this skill?"))
        }
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: iconName)
                        .font(.system(size: 32))
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(descriptor?.title.preferredValue() ?? skillID.rawValue)
                            .font(.headline)
                        Text(skillID.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    sourceBadge
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var statusSection: some View {
        Section {
            Toggle(SkillL10n.string("Enabled"), isOn: Binding(
                get: { isEnabled },
                set: { newValue in
                    isEnabled = newValue
                    SkillStore.shared.setSkillEnabled(id: skillID, enabled: newValue)
                    loadSkillData()
                }
            ))
            .accessibilityIdentifier("hanlin-skill-detail-enable-toggle")
        }
    }

    private var summarySection: some View {
        Section(header: Text(SkillL10n.string("Description"))) {
            Text(descriptor?.summary.preferredValue() ?? "")
                .font(.subheadline)
        }
    }

    private var instructionsSection: some View {
        Section(header: Text(SkillL10n.string("Instructions"))) {
            if instructionsText.isEmpty {
                Text("No instructions provided.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                Text(instructionsText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var preferredToolsSection: some View {
        Section(header: Text(SkillL10n.string("Preferred Tools"))) {
            let tools = descriptor?.preferredToolIDs ?? []
            if tools.isEmpty {
                Text("None specified.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(tools, id: \.self) { tool in
                    HStack {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(tool)
                            .font(.system(.subheadline, design: .monospaced))
                    }
                }
            }
        }
    }

    private var resourcesSection: some View {
        Section(header: Text(SkillL10n.string("Resources"))) {
            if resources.isEmpty {
                Text(SkillL10n.string("No resources"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(resources) { res in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(res.relativePath)
                                .font(.system(.subheadline, design: .monospaced))
                            Text(ByteCountFormatter.string(fromByteCount: res.byteCount, countStyle: .file))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if !res.isBinary {
                            Button("View") {
                                previewResource = res
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        } else {
                            Text("Binary")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
            }
        }
    }

    private var actionsSection: some View {
        Section {
            if isCustomOrImported {
                Button {
                    showEditor = true
                } label: {
                    Label(SkillL10n.string("Edit Skill"), systemImage: "pencil")
                }
                .accessibilityIdentifier("hanlin-skill-detail-edit-button")

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label(SkillL10n.string("Delete Skill"), systemImage: "trash")
                }
                .accessibilityIdentifier("hanlin-skill-detail-delete-button")

            } else if isOverride {
                Button {
                    showEditor = true
                } label: {
                    Label(SkillL10n.string("Edit Override"), systemImage: "pencil")
                }
                .accessibilityIdentifier("hanlin-skill-detail-edit-button")

                Button(role: .destructive) {
                    resetOverride()
                } label: {
                    Label(SkillL10n.string("Reset to Default"), systemImage: "arrow.uturn.backward")
                }
                .accessibilityIdentifier("hanlin-skill-detail-reset-button")

            } else {
                Button {
                    showEditor = true
                } label: {
                    Label(SkillL10n.string("Customize (Override)"), systemImage: "slider.horizontal.3")
                }
                .accessibilityIdentifier("hanlin-skill-detail-override-button")
            }
        }
    }

    private var sourceBadge: some View {
        let text: String
        let color: Color
        if isOverride {
            text = SkillL10n.string("Overrides")
            color = .orange
        } else if let rec = record {
            switch rec.sourceKind {
            case .custom:
                text = SkillL10n.string("Custom")
                color = .purple
            case .imported:
                text = "Imported"
                color = .blue
            case .system:
                text = SkillL10n.string("System")
                color = .secondary
            case .miniApp:
                text = "Mini App"
                color = .teal
            case .override:
                text = SkillL10n.string("Overrides")
                color = .orange
            }
        } else {
            text = SkillL10n.string("System")
            color = .secondary
        }

        return Text(text)
            .font(.caption2)
            .bold()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(6)
    }

    private var iconName: String {
        switch skillID.rawValue {
        case "code": return "apple.terminal"
        case "memory": return "archivebox"
        case "calendar": return "calendar"
        case "maps_location": return "map"
        case "web_research": return "magnifyingglass"
        case "knowledge": return "backpack"
        case "canvas": return "pencil.and.outline"
        case "weather": return "cloud.sun"
        case "health": return "heart"
        default: return "sparkles.rectangle.stack"
        }
    }

    @ViewBuilder
    private var editorSheet: some View {
        if let rec = record, !isOverride {
            SkillEditorView(mode: .editCustom(rec)) {
                loadSkillData()
            }
        } else if let desc = descriptor {
            SkillEditorView(mode: .editOverride(baseSkill: desc, existingOverride: record)) {
                loadSkillData()
            }
        }
    }

    private func resourcePreviewSheet(_ res: SkillResourceFile) -> some View {
        NavigationStack {
            ScrollView {
                if let url = SkillStore.shared.safeResourceURL(for: skillID, relativePath: res.relativePath),
                   let text = try? String(contentsOf: url, encoding: .utf8) {
                    Text(text)
                        .font(.system(.caption, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Unable to load resource.")
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .navigationTitle(res.relativePath)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(SkillL10n.string("Close")) {
                        previewResource = nil
                    }
                }
            }
        }
    }

    private func loadSkillData() {
        let store = SkillStore.shared
        isEnabled = store.isSkillEnabled(id: skillID)
        isOverride = store.hasOverride(for: skillID)

        let catalog = HanlinSkillCatalog.shared
        descriptor = catalog.resolve(id: skillID)

        let allRecords = store.allStoredRecords()
        record = allRecords.first(where: { $0.descriptor.id == skillID })
        isCustomOrImported = (record != nil && !record!.isOverride)

        resources = store.listResources(for: skillID)

        if let desc = descriptor {
            Task {
                instructionsText = await catalog.loadInstructions(for: desc)
            }
        }
    }

    private func resetOverride() {
        SkillStore.shared.resetOverride(skillID: skillID)
        loadSkillData()
    }

    private func deleteSkill() {
        SkillStore.shared.deleteCustomSkill(skillID: skillID)
        dismiss()
    }
}
