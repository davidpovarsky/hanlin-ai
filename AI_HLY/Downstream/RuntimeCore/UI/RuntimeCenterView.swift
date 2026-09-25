import Observation
import SwiftUI

@MainActor
@Observable
final class RuntimeCenterModel {
    var snapshots: [RuntimeKind: RuntimeSnapshot] = [:]
    var optimisticStates: [RuntimeKind: RuntimeOperationalState] = [:]
    var isBusy = false
    var lastMessage: String?

    private let core = AppRuntimeCore.shared

    func isStarted(for kind: RuntimeKind) -> Bool {
        if let optimistic = optimisticStates[kind] {
            return optimistic == .ready || optimistic == .executing || optimistic == .preparing
        }
        guard let snapshot = snapshots[kind] else { return false }
        return snapshot.state == .ready || snapshot.state == .executing || snapshot.state == .preparing
    }

    func toggleLifecycle(for kind: RuntimeKind) async {
        if isStarted(for: kind) {
            await stop(kind)
        } else {
            await start(kind)
        }
    }

    func start(_ kind: RuntimeKind) async {
        optimisticStates[kind] = .preparing
        if kind == .typeScript && !isStarted(for: .node) {
            optimisticStates[.node] = .preparing
        }
        await perform {
            _ = try await self.core.start(kind)
        }
    }

    func stop(_ kind: RuntimeKind) async {
        optimisticStates[kind] = .stopped
        await perform {
            let snapshot = try await self.core.stop(kind)
            if snapshot.state == .appRestartRequired {
                self.lastMessage = RuntimeL10n.string("Node.js cannot be unloaded from process memory without restarting the app.")
            }
        }
    }

    func load() async {
        let values = await core.snapshots()
        snapshots = Dictionary(uniqueKeysWithValues: values.map { ($0.kind, $0) })
    }

    func smokeTest(_ kind: RuntimeKind) async {
        await perform {
            _ = try await self.core.ensureStarted(kind)
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
                let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                self.lastMessage = output.isEmpty ? "Completed (exit \(result.exitCode))" : output
            }
        }
    }

    func clearCaches() async {
        await perform { try await self.core.clearReproducibleCaches() }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) async {
        isBusy = true
        lastMessage = nil
        defer {
            isBusy = false
            optimisticStates.removeAll()
        }
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
                Section {
                    Text(message)
                        .font(.callout)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("hanlin-runtime-last-message")
                }
            }

            Section(RuntimeL10n.string("On-device runtimes")) {
                ForEach(localRuntimes, id: \.0) { kind, title, image in
                    RuntimeCard(
                        kind: kind,
                        title: RuntimeL10n.string(title),
                        image: image,
                        snapshot: snapshot(for: kind),
                        isBusy: model.isBusy,
                        isStarted: model.isStarted(for: kind),
                        onToggle: {
                            Task { await model.toggleLifecycle(for: kind) }
                        },
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
        .task {
            await model.load()
            for await _ in NotificationCenter.default.notifications(named: RuntimeAvailabilityStore.didChangeNotification) {
                await model.load()
            }
        }
        .refreshable { await model.load() }
    }

    private func snapshot(for kind: RuntimeKind) -> RuntimeSnapshot {
        var snap = model.snapshots[kind] ?? .stopped(kind)
        if let optimistic = model.optimisticStates[kind] {
            snap.state = optimistic
            return snap
        }
        if kind == .typeScript {
            let isTSStarted = model.isStarted(for: .typeScript)
            let nodeSnap = model.snapshots[.node] ?? .stopped(.node)
            let state: RuntimeOperationalState = isTSStarted ? nodeSnap.state : .stopped
            return RuntimeSnapshot(
                kind: .typeScript,
                state: state,
                version: "6.0.3",
                source: "typescript npm package",
                lastHealthCheck: nodeSnap.lastHealthCheck,
                lastErrorCode: nodeSnap.lastErrorCode,
                storageBytes: nil,
                cacheBytes: nil,
                activeExecutionCount: nodeSnap.activeExecutionCount,
                packageCount: nil
            )
        }
        return snap
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
    let kind: RuntimeKind
    let title: String
    let image: String
    let snapshot: RuntimeSnapshot
    let isBusy: Bool
    let isStarted: Bool
    let onToggle: () -> Void
    let smoke: () -> Void
    let destination: () -> Destination

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: image)
                    .font(.headline)
                    .accessibilityIdentifier("hanlin-runtime-card-\(kind.rawValue)")
                Spacer()
                Toggle("", isOn: Binding(get: { isStarted }, set: { _ in onToggle() }))
                    .labelsHidden()
                    .accessibilityIdentifier("hanlin-runtime-availability-\(kind.rawValue)")
                Text(RuntimeL10n.string(snapshot.state.localizationKey)).font(.caption).foregroundStyle(snapshot.state.tint)
            }
            if snapshot.state == .stopped {
                Text(RuntimeL10n.string("Starts on demand")).font(.caption).foregroundStyle(.secondary)
            }
            if let version = snapshot.version { LabeledContent(RuntimeL10n.string("Version"), value: version) }
            if let source = snapshot.source { LabeledContent(RuntimeL10n.string("Source"), value: source) }
            if let date = snapshot.lastHealthCheck { LabeledContent(RuntimeL10n.string("Last health check"), value: date.formatted(date: .abbreviated, time: .standard)) }
            if let error = snapshot.lastErrorCode { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            if let diagnostic = snapshot.lastDiagnostic {
                Text(diagnostic).font(.caption).foregroundStyle(snapshot.state == .failed || snapshot.state == .appRestartRequired ? .red : .secondary).textSelection(.enabled)
            }
            if let missingCommands = snapshot.missingCommands, !missingCommands.isEmpty {
                Text(missingCommands.joined(separator: ", ")).font(.caption2.monospaced()).foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Button(RuntimeL10n.string("Smoke Test"), action: smoke)
                    .accessibilityIdentifier("hanlin-runtime-smoke-\(kind.rawValue)")
                NavigationLink(RuntimeL10n.string("Open Details")) { destination() }
                    .accessibilityIdentifier("hanlin-runtime-details-\(kind.rawValue)")
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
            .accessibilityIdentifier("hanlin-tool-permission-\(entry.name)")
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
