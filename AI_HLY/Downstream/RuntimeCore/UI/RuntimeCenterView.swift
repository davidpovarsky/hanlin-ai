import Observation
import SwiftUI

@MainActor
@Observable
final class RuntimeCenterModel {
    var snapshots: [RuntimeKind: RuntimeSnapshot] = [:]
    var isBusy = false
    var lastMessage: String?

    private let core = AppRuntimeCore.shared

    func load() async {
        let values = await core.snapshots()
        snapshots = Dictionary(uniqueKeysWithValues: values.map { ($0.kind, $0) })
    }

    func prepare(_ kind: RuntimeKind) async {
        await perform {
            switch kind {
            case .node:
                _ = try await self.core.node.healthCheck()
            case .typeScript:
                let result = try await self.core.typeScript.compile(source: "const answer: number = 42")
                guard result.succeeded else { throw RuntimeCoreError.runtimeFailure("TypeScript compiler health check failed.") }
            case .localPython:
                _ = try await self.core.python.prepare()
            case .javaScriptCore:
                _ = try await self.core.javaScriptCore.healthCheck()
            case .shell:
                _ = try await self.core.shell.healthCheck()
            }
        }
    }

    func smokeTest(_ kind: RuntimeKind) async {
        await perform {
            let layout = RuntimeFileLayout.default
            let workspace = try layout.workspace(client: .tools, identifier: "runtime-smoke")
            switch kind {
            case .node:
                let result = try await self.core.node.executeJavaScript(.init(source: "console.log(process.version)", workspace: workspace))
                self.lastMessage = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            case .typeScript:
                let request = RuntimeExecutionRequest(source: "", workspace: workspace)
                let result = try await self.core.typeScript.compileAndExecute(source: "const greeting: string = 'שלום'; console.log(greeting)", request: request)
                guard result.compilation.succeeded else { throw RuntimeCoreError.runtimeFailure(result.compilation.diagnostics.map(\.message).joined(separator: "\n")) }
                self.lastMessage = result.execution?.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            case .localPython:
                let result = try await self.core.python.execute(.init(source: "print('שלום')", workspace: workspace))
                self.lastMessage = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            case .javaScriptCore:
                let result = try await self.core.javaScriptCore.execute(.init(source: "1 + 2", workspace: workspace))
                self.lastMessage = result.value.map(String.init(describing:))
            case .shell:
                let result = try await self.core.shell.execute(command: "ls", workspace: workspace, environment: [:], allowNetwork: false)
                self.lastMessage = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    func clearCaches() async {
        await perform { try await self.core.clearReproducibleCaches() }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) async {
        isBusy = true
        lastMessage = nil
        defer { isBusy = false }
        do {
            try await operation()
            if lastMessage == nil { lastMessage = RuntimeL10n.string("Completed") }
        } catch {
            lastMessage = error.localizedDescription
        }
        await load()
    }
}

struct RuntimeCenterView: View {
    @State private var model = RuntimeCenterModel()

    private let localRuntimes: [(RuntimeKind, String, String)] = [
        (.node, "Node.js", "point.3.connected.trianglepath.dotted"),
        (.typeScript, "TypeScript", "chevron.left.forwardslash.chevron.right"),
        (.localPython, "Local Python", "shippingbox"),
        (.javaScriptCore, "JavaScriptCore", "safari"),
        (.shell, "Shell / ios_system", "terminal")
    ]

    var body: some View {
        List {
            if let message = model.lastMessage {
                Section { Text(message).font(.callout).textSelection(.enabled) }
            }

            Section(RuntimeL10n.string("On-device runtimes")) {
                ForEach(localRuntimes, id: \.0) { kind, title, image in
                    RuntimeCard(
                        title: RuntimeL10n.string(title),
                        image: image,
                        snapshot: snapshot(for: kind),
                        isBusy: model.isBusy,
                        prepare: { Task { await model.prepare(kind) } },
                        smoke: { Task { await model.smokeTest(kind) } },
                        destination: { destination(for: kind) }
                    )
                }
            }

            Section(RuntimeL10n.string("Additional execution environments")) {
                ExternalRuntimeRow(title: RuntimeL10n.string("Piston Remote Python"), detail: RuntimeL10n.string("Remote service · Python 3.10 · network required"), image: "network")
                ExternalRuntimeRow(title: RuntimeL10n.string("Browser JavaScript / WebKit"), detail: RuntimeL10n.string("Available inside the existing browser and canvas flows"), image: "globe")
            }

            Section(RuntimeL10n.string("Management")) {
                NavigationLink(RuntimeL10n.string("Environment")) { RuntimeEnvironmentView() }
                NavigationLink(RuntimeL10n.string("Runtime logs")) { RuntimeLogsView() }
                Button(RuntimeL10n.string("Clear reproducible caches"), role: .destructive) { Task { await model.clearCaches() } }
                    .disabled(model.isBusy)
            }

            Section(RuntimeL10n.string("Runtime tools")) { RuntimeToolsSettingsView() }
        }
        .navigationTitle(RuntimeL10n.string("Runtimes & Packages"))
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    private func snapshot(for kind: RuntimeKind) -> RuntimeSnapshot {
        if kind == .typeScript {
            var value = model.snapshots[.node] ?? .stopped(.typeScript)
            value = RuntimeSnapshot(kind: .typeScript, state: value.state, version: "6.0.3", source: "typescript npm package", lastHealthCheck: value.lastHealthCheck, lastErrorCode: value.lastErrorCode, storageBytes: nil, cacheBytes: nil, activeExecutionCount: value.activeExecutionCount, packageCount: nil)
            return value
        }
        return model.snapshots[kind] ?? .stopped(kind)
    }

    @ViewBuilder
    private func destination(for kind: RuntimeKind) -> some View {
        switch kind {
        case .node, .typeScript: NodePackagesView()
        case .localPython: PythonPackagesView()
        case .shell: ShellCapabilitiesView()
        case .javaScriptCore: RuntimeLogsView()
        }
    }
}

private struct RuntimeCard<Destination: View>: View {
    let title: String
    let image: String
    let snapshot: RuntimeSnapshot
    let isBusy: Bool
    let prepare: () -> Void
    let smoke: () -> Void
    let destination: () -> Destination

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: image).font(.headline)
                Spacer()
                Text(RuntimeL10n.string(snapshot.state.localizationKey)).font(.caption).foregroundStyle(snapshot.state.tint)
            }
            if let version = snapshot.version { LabeledContent(RuntimeL10n.string("Version"), value: version) }
            if let source = snapshot.source { LabeledContent(RuntimeL10n.string("Source"), value: source) }
            if let date = snapshot.lastHealthCheck { LabeledContent(RuntimeL10n.string("Last health check"), value: date.formatted(date: .abbreviated, time: .standard)) }
            if let error = snapshot.lastErrorCode { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            if let diagnostic = snapshot.lastDiagnostic {
                Text(diagnostic).font(.caption).foregroundStyle(snapshot.state == .failed ? .red : .secondary).textSelection(.enabled)
            }
            if let missingCommands = snapshot.missingCommands, !missingCommands.isEmpty {
                Text(missingCommands.joined(separator: ", ")).font(.caption2.monospaced()).foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Button(RuntimeL10n.string(snapshot.state == .stopped ? "Prepare" : "Health Check"), action: prepare)
                Button(RuntimeL10n.string("Smoke Test"), action: smoke)
                NavigationLink(RuntimeL10n.string("Open Details")) { destination() }
            }
            .buttonStyle(.borderless)
            .disabled(isBusy)
        }
        .padding(.vertical, 4)
    }
}

private struct ExternalRuntimeRow: View {
    let title: String
    let detail: String
    let image: String

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        } icon: { Image(systemName: image) }
    }
}

private struct RuntimeToolsSettingsView: View {
    @State private var entries: [NativeToolCatalogEntry] = []

    var body: some View {
        ForEach(entries) { entry in
            Toggle(isOn: Binding(
                get: { NativeToolCatalog.shared.isEnabled(entry) },
                set: { NativeToolCatalog.shared.setEnabled($0, for: entry) }
            )) {
                Label {
                    VStack(alignment: .leading) {
                        Text(entry.title)
                        Text(entry.summary).font(.caption).foregroundStyle(.secondary)
                        if entry.isSensitive { Text(RuntimeL10n.string("Sensitive capability — review every command")) .font(.caption2).foregroundStyle(.orange) }
                    }
                } icon: { Image(systemName: entry.systemImage) }
            }
        }
        .task {
            let names = Set(["execute_local_python_code", "execute_javascript_code", "execute_typescript_code", "execute_shell_command"])
            entries = NativeToolCatalog.shared.allEntries().filter { names.contains($0.name) }
        }
    }
}

private extension RuntimeOperationalState {
    var localizationKey: String {
        switch self {
        case .unavailable: "Unavailable"
        case .stopped: "Not prepared"
        case .preparing: "Preparing"
        case .ready: "Ready"
        case .executing: "Executing"
        case .failed: "Failed"
        case .appRestartRequired: "App restart required"
        }
    }

    var tint: Color {
        switch self {
        case .ready: .green
        case .executing, .preparing: .orange
        case .failed, .appRestartRequired: .red
        case .unavailable, .stopped: .secondary
        }
    }
}
