import Observation
import SwiftUI

@MainActor
@Observable
private final class RuntimeEnvironmentModel {
    var items: [RuntimeEnvironmentItem] = []
    var message: String?

    func load() async {
        do { items = try await AppRuntimeCore.shared.environment.items() }
        catch { message = error.localizedDescription }
    }

    func save(_ draft: RuntimeEnvironmentDraft) async -> Bool {
        do {
            _ = try await AppRuntimeCore.shared.environment.save(name: draft.name, value: draft.value, scope: draft.scope, isEnabled: draft.isEnabled, isSecret: draft.isSecret, replacing: draft.id)
            await load()
            return true
        } catch { message = error.localizedDescription; return false }
    }

    func setEnabled(_ enabled: Bool, item: RuntimeEnvironmentItem) {
        Task {
            _ = await save(RuntimeEnvironmentDraft(item: item, isEnabled: enabled))
        }
    }

    func delete(_ item: RuntimeEnvironmentItem) {
        Task {
            do { try await AppRuntimeCore.shared.environment.delete(id: item.id); await load() }
            catch { message = error.localizedDescription }
        }
    }
}

private struct RuntimeEnvironmentDraft: Identifiable {
    var id: UUID?
    var name = ""
    var value = ""
    var scope: RuntimeEnvironmentScope = .shared
    var isEnabled = true
    var isSecret = false

    init() {}
    init(item: RuntimeEnvironmentItem, isEnabled: Bool? = nil) {
        id = item.id
        name = item.name
        value = item.isSecret ? "" : (item.value ?? "")
        scope = item.scope
        self.isEnabled = isEnabled ?? item.isEnabled
        isSecret = item.isSecret
    }
}

struct RuntimeEnvironmentView: View {
    @State private var model = RuntimeEnvironmentModel()
    @State private var draft: RuntimeEnvironmentDraft?

    var body: some View {
        List {
            if let message = model.message { Section { Text(message).font(.caption).foregroundStyle(.red) } }
            ForEach(RuntimeEditableScope.allCases) { scope in
                let entries = model.items.filter { $0.scope == scope.value }
                Section(RuntimeL10n.string(scope.title)) {
                    if entries.isEmpty { Text(RuntimeL10n.string("No variables in this scope")).foregroundStyle(.secondary) }
                    ForEach(entries) { item in
                        Toggle(isOn: Binding(get: { item.isEnabled }, set: { model.setEnabled($0, item: item) })) {
                            VStack(alignment: .leading) {
                                HStack {
                                    Text(item.name).font(.system(.body, design: .monospaced))
                                    if item.isSecret { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
                                }
                                Text(item.isSecret ? RuntimeL10n.string("Saved in Keychain · value hidden") : (item.value ?? ""))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { draft = RuntimeEnvironmentDraft(item: item) }
                        .swipeActions { Button(RuntimeL10n.string("Delete"), role: .destructive) { model.delete(item) } }
                    }
                }
            }
            Section { Text(RuntimeL10n.string("Runtime-managed names such as HOME, PATH, TMPDIR, NODE_PATH, npm cache paths, PYTHONHOME and PYTHONPATH cannot be overridden.")) .font(.caption).foregroundStyle(.secondary) }
        }
        .navigationTitle(RuntimeL10n.string("Environment"))
        .toolbar { Button(RuntimeL10n.string("Add"), systemImage: "plus") { draft = RuntimeEnvironmentDraft() } }
        .sheet(item: $draft) { value in RuntimeEnvironmentEditor(draft: value) { await model.save($0) } }
        .task { await model.load() }
    }
}

private struct RuntimeEnvironmentEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: RuntimeEnvironmentDraft
    let save: (RuntimeEnvironmentDraft) async -> Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField(RuntimeL10n.string("Name"), text: $draft.name).textInputAutocapitalization(.characters).autocorrectionDisabled()
                if draft.isSecret { SecureField(draft.id == nil ? RuntimeL10n.string("Secret value") : RuntimeL10n.string("New value (leave blank to keep saved secret)"), text: $draft.value) }
                else { TextField(RuntimeL10n.string("Value"), text: $draft.value) }
                Picker(RuntimeL10n.string("Scope"), selection: $draft.scope) {
                    ForEach(RuntimeEditableScope.allCases) { scope in Text(RuntimeL10n.string(scope.title)).tag(scope.value) }
                }
                Toggle(RuntimeL10n.string("Enabled"), isOn: $draft.isEnabled)
                Toggle(RuntimeL10n.string("Treat as secret"), isOn: $draft.isSecret)
                if draft.isSecret { Text(RuntimeL10n.string("Secrets are saved in Keychain and are never displayed again, logged, or included in diagnostics.")) .font(.caption).foregroundStyle(.secondary) }
            }
            .navigationTitle(draft.id == nil ? RuntimeL10n.string("Add Variable") : RuntimeL10n.string("Edit Variable"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(RuntimeL10n.string("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(RuntimeL10n.string("Save")) { Task { if await save(draft) { dismiss() } } } }
            }
        }
    }
}

private enum RuntimeEditableScope: String, CaseIterable, Identifiable {
    case shared, node, python, javaScriptCore, shell
    var id: String { rawValue }
    var value: RuntimeEnvironmentScope {
        switch self {
        case .shared: .shared
        case .node: .node
        case .python: .python
        case .javaScriptCore: .javaScriptCore
        case .shell: .shell
        }
    }
    var title: String {
        switch self {
        case .shared: "Shared"
        case .node: "Node.js"
        case .python: "Local Python"
        case .javaScriptCore: "JavaScriptCore"
        case .shell: "Shell / ios_system"
        }
    }
}
