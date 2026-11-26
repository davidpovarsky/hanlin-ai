import HanlinPresentationKit
import HanlinLocalization
import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinScriptExtensions
import HanlinScriptStore
import HanlinScriptUI
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let hanlinScriptingPackage = UTType(importedAs: "com.hanlin.scripting-package")
}

struct ScriptingPackageImportView: View {
    let platform: HanlinScriptingPlatform
    @Environment(\.dismiss) private var dismiss
    @State private var showsImporter = false
    @State private var diagnosticsSelection: MiniAppImportDiagnosticsSelection?
    @State private var importPresentationID = UUID()
    private var stagedDocumentPackages: [URL] {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let contents = try? FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil) else {
            return []
        }
        let supported = Set(["scripting", "hanlinnativescript", "hanlinexpo", "zip"])
        return contents.filter { supported.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    var body: some View {
        @Bindable var platform = platform
        List {
            Section {
                NavigationLink { ChavrusaShareInboxView(platform: platform) } label: {
                    Label(hanlin: "Shared Items", systemImage: "tray.and.arrow.down")
                }
                .accessibilityIdentifier("hanlin-share-inbox-link")
            }
            if !platform.resumeCommandRejections.isEmpty {
                Section(hanlin: "Queued Actions") {
                    Label(hanlin: "Some saved actions couldn’t be read.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("hanlin-pending-action-warning")
                    Text("Other actions can still run. The unreadable items were kept for recovery.", bundle: HanlinLocalization.bundle)
                        .font(HanlinTypography.footnote).foregroundStyle(.secondary)
                }
            }
            if case let .failed(message) = platform.activity {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("hanlin-import-error-message")
                } header: {
                    Text("Import Error", bundle: HanlinLocalization.bundle)
                        .accessibilityIdentifier("hanlin-import-error")
                }
            }

            if !platform.importDiagnostics.isEmpty {
                Section {
                    Button {
                        diagnosticsSelection = .init(id: platform.importAttemptID)
                    } label: {
                        Label(hanlin: "Review package diagnostics", systemImage: "list.bullet.rectangle")
                    }
                    .accessibilityIdentifier("hanlin-import-diagnostics-open")
                }
            }
            if let preview = platform.preview {
                Section {
                    Button(hanlin: "Install") { Task { await platform.installPreview() } }
                        .accessibilityIdentifier("hanlin-package-install")
                        .disabled(
                            !platform.canInstallPreview
                                || platform.activity == .installing
                        )
                    Button(hanlin: "Discard", role: .destructive) { platform.discardPreview() }
                }
                ScriptingImportPreviewSections(preview: preview, platform: platform)
            } else {
                Section {
                    Button {
                        showsImporter = true
                    } label: {
                        Label(hanlin: "Import Script Package", systemImage: "doc.badge.plus")
                    }
                    .accessibilityIdentifier("hanlin-file-importer")
                    Text("Choose a .scripting, .hanlinNativeScript, .hanlinExpo, or .zip package. Hanlin copies it into private staging and performs Import Preview without executing package code.", bundle: HanlinLocalization.bundle)
                        .font(HanlinTypography.footnote)
                        .foregroundStyle(.secondary)
                }
                let stagedFiles = stagedDocumentPackages
                if !stagedFiles.isEmpty {
                    Section(hanlin: "Shared Packages") {
                        ForEach(stagedFiles, id: \.self) { fileURL in
                            Button {
                                print("HANLIN_IMPORT_PACKAGE_TAPPED url=\(fileURL.lastPathComponent)")
                                Task { await platform.importPackage(from: fileURL) }
                            } label: {
                                HStack {
                                    Label(fileURL.deletingPathExtension().lastPathComponent, systemImage: "shippingbox")
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier(fileURL.deletingPathExtension().lastPathComponent)
                            .accessibilityLabel(fileURL.deletingPathExtension().lastPathComponent)
                        }
                    }
                }

            }
        }
        // Only the list contents change identity between browse and preview.
        // Keep this screen's presentation registration and diagnostics sheet
        // outside that identity so replacing content cannot release its owner.
        .id(platform.preview == nil ? "browse" : "preview")
        .onAppear {
            platform.setImportPresentation(importPresentationID, visible: true)
            if platform.activity == .idle && platform.preview != nil {
                platform.discardPreview()
            }
        }
        .onDisappear { platform.setImportPresentation(importPresentationID, visible: false) }
        .onChange(of: platform.importAttemptID) { diagnosticsSelection = nil }
        .onChange(of: platform.activity, initial: true) {
            if platform.activity == .idle { diagnosticsSelection = nil }
            else if platform.activity != .importing && platform.activity != .installing,
               platform.importDiagnostics.contains(where: { $0.category == "error" }) {
                diagnosticsSelection = .init(id: platform.importAttemptID)
            }
        }
        .sheet(item: $diagnosticsSelection) { _ in
            NavigationStack { MiniAppImportDiagnosticsView(platform: platform) }
        }
        .accessibilityIdentifier("hanlin-package-import-list")
        .navigationTitle(Text("Script Package", bundle: HanlinLocalization.bundle))
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if platform.activity == .importing || platform.activity == .installing {
                ProgressView(platform.activity == .importing ? "Inspecting…" : "Installing…")
            }
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.hanlinScriptingPackage, .zip],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first { Task { await platform.importPackage(from: url) } }
            case let .failure(error):
                Task { @MainActor in
                    platform.reportImportFailure(error)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(hanlin: "Done") { dismiss() }
                    .accessibilityIdentifier("hanlin-package-import-done")
            }
        }
    }
}

private struct ScriptingImportPreviewSections: View {
    let preview: HanlinImportPreview
    let platform: HanlinScriptingPlatform

    var body: some View {
        Section(hanlin: "Package") {
            LabeledContent(hanlin: "Name", value: preview.manifest?.name ?? preview.source.originalFileName)
            if let version = preview.manifest?.version { LabeledContent(hanlin: "Version", value: version) }
            LabeledContent(hanlin: "Trust", value: preview.source.trust.rawValue)
            LabeledContent(hanlin: "SHA-256", value: String(preview.source.contentSHA256.prefix(16)) + "…")
        }
        Section(hanlin: "Entry Points") {
            ForEach(preview.entrypoints, id: \.id) { entrypoint in
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent(entrypoint.kind.rawValue, value: entrypoint.sourcePath)
                    LabeledContent(hanlin: "Runtime", value: entrypoint.runtimeProfile.rawValue)
                        .font(HanlinTypography.caption)
                        .foregroundStyle(.secondary)
                    Text(runtimeReason(entrypoint.runtimeProfile))
                        .font(HanlinTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        if !preview.findings.isEmpty {
            Section(hanlin: "Compatibility") {
                ForEach(Array(preview.findings.enumerated()), id: \.offset) { _, finding in
                    Label(
                        finding.message,
                        systemImage: finding.severity == .error ? "xmark.octagon" : "info.circle"
                    )
                    .foregroundStyle(finding.severity == .error ? Color.red : Color.secondary)
                }
            }
        }
    }

    private func runtimeReason(_ profile: HanlinRuntimeProfile) -> String {
        switch profile {
        case .scriptingJSC: return "Original Scripting JavaScript and TypeScript use the compatibility runtime."
        case .hanlinQuickJS: return "Hanlin manifest selected constrained JavaScript."
        case .hanlinNode: return "Hanlin manifest selected a trusted Node worker."
        case .hanlinPython: return "Python entrypoint requires trusted local execution."
        case .hanlinNativeScript: return "NativeScript provides original native iOS APIs and Core UI."
        case .hanlinExpo: return "Expo renders React Native and original Expo UI components."
        }
    }
}

struct ScriptingInstalledPackageDetailView: View {
    let packageID: HanlinInstalledPackageID
    let platform: HanlinScriptingPlatform
    @Environment(\.dismiss) private var dismiss
    @State private var widgetInstances: [HanlinWidgetInstance] = []
    @State private var sourceInstanceID = ""
    @State private var newInstanceName = ""
    @State private var widgetInstanceError: String?
    @State private var storageDiagnostic: HanlinWidgetStorageDiagnostic?
    @State private var isRetryingPublication = false
    @State private var didAttemptAutoRepublish = false
    @State private var showsWidgetStatus = false
    @State private var widgetStatusText = ""

    var body: some View {
        Group {
            if let package {
                installedPackageList(package)
            } else {
                ContentUnavailableView(hanlin: "Package Not Installed", systemImage: "shippingbox")
            }
        }
        .navigationTitle(package?.manifest?.name ?? "Script Package")
        .task(id: packageID) {
            loadWidgetInstances()
            if let package,
               package.enabled,
               hasNativeWidget(package),
               widgetInstances.isEmpty,
               !didAttemptAutoRepublish {
                didAttemptAutoRepublish = true
                _ = await platform.republishWidgets(for: packageID)
                loadWidgetInstances()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if let package, hasNativeWidget(package) {
                    Button {
                        let report = platform.storageConsistencyReport()?.redactedReportString ?? ""
                        let diagnostic = (storageDiagnostic ?? platform.widgetPublicationDiagnostic(for: packageID))?.redactedReportString ?? ""
                        widgetStatusText = [report, diagnostic].filter { !$0.isEmpty }.joined(separator: "\n\n")
                        showsWidgetStatus = true
                    } label: {
                        Label(String(localized: "Widget status", bundle: HanlinLocalization.bundle), systemImage: "waveform.path.ecg")
                    }
                    .accessibilityIdentifier("hanlin-widget-status")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(hanlin: "Done") {
                    dismiss()
                }
                .accessibilityIdentifier("hanlin-package-details-done")
            }
        }
        .alert(String(localized: "Widget status", bundle: HanlinLocalization.bundle), isPresented: $showsWidgetStatus) {
            Button(String(localized: "Copy Diagnostic", bundle: HanlinLocalization.bundle)) { UIPasteboard.general.string = widgetStatusText }
                .accessibilityIdentifier("hanlin-widget-status-copy")
            Button(String(localized: "Done", bundle: HanlinLocalization.bundle), role: .cancel) {}
        } message: {
            Text(widgetStatusText)
        }
    }

    private var package: HanlinStoredPackageSnapshot? {
        platform.installedPackages.first { $0.record.installedPackageID == packageID }
    }

    private func hasNativeWidget(_ package: HanlinStoredPackageSnapshot) -> Bool {
        package.entrypoints.contains { $0.kind == .widget && $0.widgetEngine != nil && $0.widgetEngine != .legacy }
    }

    private func installedPackageList(_ package: HanlinStoredPackageSnapshot) -> some View {
        List {
            Section(hanlin: "Package") {
                LabeledContent(hanlin: "Name", value: package.manifest?.name ?? package.record.packageID.rawValue)
                LabeledContent(hanlin: "Version", value: package.record.version.rawValue)
                LabeledContent(hanlin: "Generation", value: String(package.record.activeGeneration))
                Toggle(hanlin: "Enabled", isOn: enabledBinding(for: package))
            }
            if HanlinMiniAppSystemEntrypoints.isAvailableForCurrentProduct {
                HanlinMiniAppCaptureSection(package: package, platform: platform)
            }
            Section(hanlin: "Entry Points") {
                ForEach(package.entrypoints, id: \.id) { entrypoint in
                    VStack(alignment: .leading) {
                        LabeledContent(entrypoint.kind.rawValue, value: entrypoint.sourcePath)
                        LabeledContent(hanlin: "Runtime", value: entrypoint.runtimeProfile.rawValue)
                            .font(HanlinTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if package.enabled, hasNativeWidget(package) {
                Section(hanlin: "Widget instances") {
                    ForEach(widgetInstances, id: \.entityID) { instance in
                        LabeledContent(instance.displayName, value: instance.engine.rawValue)
                        if instance.engine == .scriptwidget {
                            NavigationLink {
                                platform.scriptWidgetServicesView(for: instance.entityID)
                            } label: {
                                Label(hanlin: "Services and Data", systemImage: "slider.horizontal.3")
                            }
                            .accessibilityIdentifier("hanlin-widget-services-\(instance.entityID)")
                            MiniAppScriptWidgetActivityControls(platform: platform, entityID: instance.entityID)
                        }
                    }
                    Picker(hanlin: "Copy from", selection: $sourceInstanceID) {
                        ForEach(widgetInstances, id: \.entityID) { instance in
                            Text(instance.displayName).tag(instance.entityID)
                        }
                    }
                    TextField(hanlin: "Instance name", text: $newInstanceName)
                        .accessibilityIdentifier("hanlin-widget-instance-name")
                    Button(hanlin: "Create independent instance") {
                        do {
                            try platform.createWidgetInstance(from: sourceInstanceID, name: newInstanceName)
                            newInstanceName = ""
                            loadWidgetInstances()
                        } catch {
                            storageDiagnostic = HanlinScriptingPlatform.makePublicationDiagnostic(
                                for: packageID,
                                phase: .packageDetailsLoadInstances,
                                error: error,
                                storeDiagnostic: HanlinScriptExtensionStore.latestDiagnostic
                            )
                        }
                    }
                    .disabled(sourceInstanceID.isEmpty || newInstanceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("hanlin-widget-create-instance")
                    Text("Choose these names in the Home Screen widget configuration. Two placements selecting the same instance share state; separate instances keep independent state.", bundle: HanlinLocalization.bundle)
                        .font(HanlinTypography.caption).foregroundStyle(.secondary)

                    if let diag = storageDiagnostic ?? platform.widgetPublicationDiagnostic(for: packageID) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(diag.userFacingHeadline)
                                .font(HanlinTypography.subheadline.weight(.semibold))
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("hanlin-widget-storage-error-headline")
                            Text("Diagnostic ID: \(diag.correlationID) • \(diag.phase.rawValue) (\(diag.decisionPoint.rawValue))", bundle: HanlinLocalization.bundle)
                                .font(HanlinTypography.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("hanlin-widget-storage-diagnostic-id")
                            Text(diag.summary)
                                .font(HanlinTypography.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                Button {
                                    Task {
                                        isRetryingPublication = true
                                        defer { isRetryingPublication = false }
                                        _ = await platform.republishWidgets(for: packageID)
                                        loadWidgetInstances()
                                    }
                                } label: {
                                    Label(hanlin: "Retry Widget Publication", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(isRetryingPublication)
                                .accessibilityIdentifier("hanlin-widget-republish-retry")

                                Button {
                                    let report = platform.storageConsistencyReport()?.redactedReportString ?? diag.redactedReportString
                                    UIPasteboard.general.string = report
                                } label: {
                                    Label(hanlin: "Copy Diagnostic", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityIdentifier("hanlin-widget-copy-diagnostic")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    if let widgetInstanceError {
                        Text(widgetInstanceError)
                            .font(HanlinTypography.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            if package.availableGenerations.count > 1 {
                Section(hanlin: "Versions") {
                    ForEach(package.availableGenerations.reversed(), id: \.self) { generation in
                        Button {
                            Task { await platform.rollback(packageID, to: generation) }
                        } label: {
                            HStack {
                                Text("Generation \(generation)", bundle: HanlinLocalization.bundle)
                                Spacer()
                                if generation == package.record.activeGeneration {
                                    Label(hanlin: "Active", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(generation == package.record.activeGeneration)
                    }
                }
            }
            Section {
                Button(hanlin: "Uninstall", role: .destructive) {
                    Task {
                        await platform.uninstall(packageID)
                        dismiss()
                    }
                }
                .accessibilityIdentifier("hanlin-package-uninstall")
            }
        }
    }

    private func enabledBinding(for package: HanlinStoredPackageSnapshot) -> Binding<Bool> {
        Binding(
            get: { package.enabled },
            set: { value in
                Task { await platform.setEnabled(value, for: packageID) }
            }
        )
    }

    private func loadWidgetInstances() {
        do {
            widgetInstances = try platform.widgetInstances(for: packageID).filter { $0.engine != .legacy }
            if !widgetInstances.contains(where: { $0.entityID == sourceInstanceID }) {
                sourceInstanceID = widgetInstances.first(where: \.isDefault)?.entityID ?? widgetInstances.first?.entityID ?? ""
            }
            widgetInstanceError = nil
            storageDiagnostic = platform.widgetPublicationDiagnostic(for: packageID)
        } catch {
            widgetInstances = []
            sourceInstanceID = ""
            widgetInstanceError = nil
            storageDiagnostic = HanlinScriptingPlatform.makePublicationDiagnostic(
                for: packageID,
                phase: .packageDetailsLoadInstances,
                error: error,
                storeDiagnostic: HanlinScriptExtensionStore.latestDiagnostic
            )
        }
    }
}

private struct MiniAppScriptWidgetActivityControls: View {
    let platform: HanlinScriptingPlatform
    let entityID: String
    @State private var isRunning = false
    @State private var status: String?
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { run(starting: true) } label: {
                    Label(hanlin: "Start Live Activity", systemImage: "waveform.path")
                }
                .accessibilityIdentifier("hanlin-widget-live-activity-start-" + entityID)
                Spacer()
                Menu {
                    Button(hanlin: "End Live Activities") { run(starting: false) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel(Text("Live Activities", bundle: HanlinLocalization.bundle))
                }
                .accessibilityIdentifier("hanlin-widget-live-activity-menu-" + entityID)
            }
            .buttonStyle(.borderless)
            .disabled(isRunning)
            if isRunning { ProgressView() }
            if let status { Text(status).font(HanlinTypography.footnote).foregroundStyle(.secondary) }
            if let failure { Text(failure).font(HanlinTypography.footnote).foregroundStyle(.red) }
        }
    }

    private func run(starting: Bool) {
        guard !isRunning else { return }
        isRunning = true
        failure = nil
        status = nil
        Task {
            defer { isRunning = false }
            do {
                if starting {
                    try await platform.startScriptWidgetLiveActivity(for: entityID)
                    status = String(localized: "Live Activity started.", bundle: HanlinLocalization.bundle)
                } else {
                    try await platform.endScriptWidgetLiveActivities(for: entityID)
                    status = String(localized: "Live Activities ended.", bundle: HanlinLocalization.bundle)
                }
            } catch { failure = error.localizedDescription }
        }
    }
}

struct ScriptingApplicationContainerView: View {
    let platform: HanlinScriptingPlatform
    let ownsApplicationLifetime: Bool
    private let onClose: (@MainActor () -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(platform: HanlinScriptingPlatform, ownsApplicationLifetime: Bool = true,
         onClose: (@MainActor () -> Void)? = nil) {
        self.platform = platform
        self.ownsApplicationLifetime = ownsApplicationLifetime
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            Group {
                if let model = platform.activeApplicationModel {
                    HanlinScriptUIView(model: model)
                } else if let controller = platform.activeNativeScriptController {
                    HanlinHostedViewController(controller: controller)
                } else if let controller = platform.activeExpoController {
                    HanlinHostedViewController(controller: controller)
                } else {
                    ContentUnavailableView(hanlin: "Script App Unavailable", systemImage: "exclamationmark.triangle")
                }
            }
            .toolbar {
                if ownsApplicationLifetime {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(hanlin: "Close") {
                            if let onClose { onClose() }
                            else { platform.dismissActiveApplication() }
                            dismiss()
                        }
                        .accessibilityIdentifier("hanlin-script-app-close")
                    }
                }
            }
        }
        .sheet(item: Binding(
            get: { platform.systemUIPresentation },
            set: { value in if value == nil { platform.cancelSystemUI() } }
        )) { presentation in
            HanlinScriptingSystemUIPresentationView(presentation: presentation) { result in
                platform.completeSystemUI(id: presentation.id, result: result)
            }
            .interactiveDismissDisabled()
        }
        .onDisappear {
            // An external invocation supplies its own close/return controls and
            // owns the runtime across this container's nested presentations.
            if ownsApplicationLifetime { platform.dismissActiveApplication() }
        }
    }
}

private struct HanlinHostedViewController: UIViewControllerRepresentable {
    let controller: UIViewController

    func makeUIViewController(context: Context) -> UIViewController { controller }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
