import HanlinLocalization
import HanlinPlatformContracts
import HanlinPresentationKit
import SwiftUI
import UIKit

struct MiniAppImportDiagnosticsSelection: Identifiable {
    let id: UUID
}

/// Presents the same structured diagnostics returned to the authoring tools.
struct MiniAppImportDiagnosticsView: View {
    let platform: HanlinScriptingPlatform
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isSending = false
    @State private var deliveryMessage: String?

    private var errors: Int { platform.importDiagnostics.filter { $0.category == "error" }.count }
    private var warnings: Int { platform.importDiagnostics.filter { $0.category == "warning" }.count }
    private var files: [String] {
        Set(platform.importDiagnostics.map { $0.file ?? "" }).sorted()
    }

    var body: some View {
        List {
            Section {
                LabeledContent(hanlin: "Package", value: platform.preview?.manifest?.name
                    ?? platform.preview?.source.originalFileName ?? String(localized: "Imported package", bundle: HanlinLocalization.bundle))
                LabeledContent(hanlin: "Errors", value: String(errors))
                LabeledContent(hanlin: "Warnings", value: String(warnings))
                if let report = platform.authoringReport {
                    LabeledContent(hanlin: "TypeScript validation",
                        value: report.succeeded
                            ? String(localized: "Passed", bundle: HanlinLocalization.bundle)
                            : String(localized: "Needs correction", bundle: HanlinLocalization.bundle))
                } else if platform.preview == nil {
                    Text("TypeScript validation has not run. The original package is kept with the import diagnostic.", bundle: HanlinLocalization.bundle)
                        .font(HanlinTypography.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("This package does not include an authoring project. Package compatibility was inspected, but original TypeScript types cannot be reconstructed from compiled JavaScript.", bundle: HanlinLocalization.bundle)
                        .font(HanlinTypography.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    sendToAgent()
                } label: {
                    Label(hanlin: "Send to Hanlin AI to fix", systemImage: "sparkles")
                }
                .disabled(!platform.canRepairImport || isSending)
                .accessibilityIdentifier("hanlin-import-repair-agent")
                Button {
                    do {
                        UIPasteboard.general.string = String(decoding: try platform.importDiagnosticJSON(), as: UTF8.self)
                        deliveryMessage = String(localized: "Diagnostic report copied.", bundle: HanlinLocalization.bundle)
                    } catch {
                        deliveryMessage = error.localizedDescription
                    }
                } label: {
                    Label(hanlin: "Copy diagnostic report", systemImage: "doc.on.doc")
                }
                .accessibilityIdentifier("hanlin-import-diagnostics-copy")
                if let deliveryMessage {
                    Text(deliveryMessage)
                        .font(HanlinTypography.footnote)
                        .accessibilityIdentifier("hanlin-import-repair-status")
                }
            } footer: {
                Text("The original package and this report are sent together. Hanlin AI opens a dedicated repair conversation and can rebuild, validate, and return the corrected package.", bundle: HanlinLocalization.bundle)
            }

            ForEach(files, id: \.self) { file in
                Section {
                    ForEach(Array(platform.importDiagnostics.enumerated()).filter {
                        ($0.element.file ?? "") == file
                    }, id: \.offset) { index, diagnostic in
                        MiniAppImportDiagnosticRow(diagnostic: diagnostic)
                            .accessibilityIdentifier("hanlin-import-diagnostic-\(index)")
                    }
                } header: {
                    if file.isEmpty {
                        Text("Package", bundle: HanlinLocalization.bundle).textCase(nil)
                    } else {
                        Text(verbatim: file)
                            .font(HanlinTypography.caption.monospaced())
                            .environment(\.layoutDirection, .leftToRight)
                            .textSelection(.enabled)
                            .textCase(nil)
                    }
                }
            }
        }
        .navigationTitle(Text("Package diagnostics", bundle: HanlinLocalization.bundle))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("hanlin-import-diagnostics-sheet")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(hanlin: "Done") { dismiss() }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func sendToAgent() {
        guard !isSending else { return }
        isSending = true
        do {
            let url = try platform.prepareImportRepair()
            openURL(url) { opened in
                isSending = false
                deliveryMessage = opened
                    ? String(localized: "Repair request saved and Hanlin AI opened.", bundle: HanlinLocalization.bundle)
                    : String(localized: "Hanlin AI could not be opened. The repair request is saved; retry after opening Hanlin AI.", bundle: HanlinLocalization.bundle)
            }
        } catch {
            isSending = false
            deliveryMessage = error.localizedDescription
        }
    }
}

private struct MiniAppImportDiagnosticRow: View {
    let diagnostic: HanlinMiniAppAuthoringDiagnostic

    private var symbol: String {
        switch diagnostic.category {
        case "error": "xmark.octagon.fill"
        case "warning": "exclamationmark.triangle"
        default: "info.circle"
        }
    }

    private var tint: Color {
        switch diagnostic.category {
        case "error": .red
        case "warning": .orange
        default: .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(diagnostic.code, systemImage: symbol)
                .foregroundStyle(tint)
                .font(HanlinTypography.caption.monospaced())
            if let line = diagnostic.line {
                Text("Line \(line), column \(diagnostic.column ?? 1)", bundle: HanlinLocalization.bundle)
                    .font(HanlinTypography.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(diagnostic.message)
            if let remediation = diagnostic.remediation, !remediation.isEmpty {
                Text(remediation)
                    .font(HanlinTypography.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
    }
}
