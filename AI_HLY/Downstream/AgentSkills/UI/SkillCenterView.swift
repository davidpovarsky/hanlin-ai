import SwiftUI
import HanlinPlatformContracts

enum SkillFilterSegment: Int, CaseIterable, Identifiable {
    case all = 0
    case custom = 1
    case system = 2
    case overrides = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .all: return SkillL10n.string("All")
        case .custom: return SkillL10n.string("Custom")
        case .system: return SkillL10n.string("System")
        case .overrides: return SkillL10n.string("Overrides")
        }
    }
}

@MainActor
struct SkillCenterView: View {
    @State private var filterSegment: SkillFilterSegment = .all
    @State private var searchQuery: String = ""
    @State private var customRecords: [StoredSkillRecord] = []
    @State private var allSkills: [HanlinSkillDescriptor] = []
    @State private var disabledIDs: Set<String> = []

    @State private var showImporter: Bool = false
    @State private var showCreator: Bool = false
    @State private var importInitialTab: Int = 0

    var body: some View {
        List {
            filterPickerSection

            if filteredCustomSkills.isEmpty && filteredSystemSkills.isEmpty {
                Section {
                    Text(SkillL10n.string("No skills found"))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
            } else {
                if !filteredCustomSkills.isEmpty && (filterSegment == .all || filterSegment == .custom) {
                    Section(header: Text(SkillL10n.string("Custom & Imported Skills"))) {
                        ForEach(filteredCustomSkills) { record in
                            skillRow(descriptor: record.descriptor, isStored: true)
                        }
                    }
                }

                if !filteredSystemSkills.isEmpty && (filterSegment == .all || filterSegment == .system || filterSegment == .overrides) {
                    Section(header: Text(SkillL10n.string("System & Mini App Skills"))) {
                        ForEach(filteredSystemSkills) { skill in
                            skillRow(descriptor: skill, isStored: false)
                        }
                    }
                }
            }
        }
        .navigationTitle(SkillL10n.string("Skill Center"))
        .searchable(text: $searchQuery, prompt: SkillL10n.string("Search skills..."))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        importInitialTab = 0
                        showImporter = true
                    } label: {
                        Label(SkillL10n.string("Import"), systemImage: "square.and.arrow.down")
                    }
                    .accessibilityIdentifier("hanlin-skill-center-import-button")

                    Menu {
                        Button {
                            showCreator = true
                        } label: {
                            Label(SkillL10n.string("New Skill"), systemImage: "plus")
                        }
                        .accessibilityIdentifier("hanlin-skill-center-menu-new-skill")

                        Button {
                            importInitialTab = 0
                            showImporter = true
                        } label: {
                            Label(SkillL10n.string("Import Skill"), systemImage: "doc.zipper")
                        }
                        .accessibilityIdentifier("hanlin-skill-center-menu-import-skill")

                        Button {
                            importInitialTab = 1
                            showImporter = true
                        } label: {
                            Label(SkillL10n.string("Install from URL"), systemImage: "link")
                        }
                        .accessibilityIdentifier("hanlin-skill-center-menu-install-url")
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("hanlin-skill-center-create-button")
                }
            }
        }
        .sheet(isPresented: $showImporter) {
            SkillImportView(initialTab: importInitialTab) {
                reloadData()
            }
        }
        .sheet(isPresented: $showCreator) {
            SkillEditorView(mode: .create) {
                reloadData()
            }
        }
        .onAppear {
            reloadData()
        }
    }

    private var filterPickerSection: some View {
        Section {
            Picker("", selection: $filterSegment) {
                ForEach(SkillFilterSegment.allCases) { seg in
                    Text(seg.title).tag(seg)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("hanlin-skill-center-filter-picker")
        }
    }

    private func skillRow(descriptor: HanlinSkillDescriptor, isStored: Bool) -> some View {
        let skillID = descriptor.id
        let isEnabled = !disabledIDs.contains(skillID.rawValue)
        let isOverride = SkillStore.shared.hasOverride(for: skillID)

        return HStack(spacing: 12) {
            Image(systemName: iconName(for: skillID.rawValue))
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32)

            NavigationLink(destination: SkillDetailView(skillID: skillID)) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(descriptor.title.preferredValue())
                            .font(.headline)
                        if isOverride {
                            Text(SkillL10n.string("Overrides"))
                                .font(.caption2)
                                .bold()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .foregroundColor(.orange)
                                .cornerRadius(4)
                        }
                    }

                    Text(descriptor.summary.preferredValue())
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .accessibilityIdentifier("hanlin-skill-center-skill-row-\(skillID.rawValue)")

            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { newValue in
                    SkillStore.shared.setSkillEnabled(id: skillID, enabled: newValue)
                    reloadData()
                }
            ))
            .labelsHidden()
            .accessibilityIdentifier("hanlin-skill-center-toggle-\(skillID.rawValue)")
        }
        .padding(.vertical, 2)
    }

    private var filteredCustomSkills: [StoredSkillRecord] {
        customRecords.filter { rec in
            let desc = rec.descriptor
            let matchesQuery = searchQuery.isEmpty
                || desc.title.preferredValue().localizedCaseInsensitiveContains(searchQuery)
                || desc.id.rawValue.localizedCaseInsensitiveContains(searchQuery)
                || desc.summary.preferredValue().localizedCaseInsensitiveContains(searchQuery)

            switch filterSegment {
            case .all, .custom:
                return matchesQuery
            case .overrides:
                return matchesQuery && rec.isOverride
            case .system:
                return false
            }
        }
    }

    private var filteredSystemSkills: [HanlinSkillDescriptor] {
        let store = SkillStore.shared
        let customIDs = Set(customRecords.map { $0.descriptor.id.rawValue })

        return allSkills.filter { skill in
            guard !customIDs.contains(skill.id.rawValue) else { return false }
            let isOverride = store.hasOverride(for: skill.id)

            let matchesQuery = searchQuery.isEmpty
                || skill.title.preferredValue().localizedCaseInsensitiveContains(searchQuery)
                || skill.id.rawValue.localizedCaseInsensitiveContains(searchQuery)
                || skill.summary.preferredValue().localizedCaseInsensitiveContains(searchQuery)

            guard matchesQuery else { return false }

            switch filterSegment {
            case .all, .system:
                return true
            case .overrides:
                return isOverride
            case .custom:
                return false
            }
        }
    }

    private func iconName(for id: String) -> String {
        switch id {
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

    private func reloadData() {
        let store = SkillStore.shared
        customRecords = store.allStoredRecords()
        allSkills = HanlinSkillCatalog.shared.allSkills()
        disabledIDs = store.disabledSkillIDs().reduce(into: Set<String>()) { $0.insert($1.rawValue) }
    }
}
