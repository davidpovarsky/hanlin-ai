import Foundation
import HanlinPlatformContracts
import SwiftUI

/// Native controls over Runtime05 and the same execution tool used by chat.
@MainActor
struct SkillExecutionPlanSection: View {
    let skillID: HanlinSkillID
    let resources: [SkillResourceFile]
    @State private var path = ""
    @State private var engine: RuntimeKind = .node
    @State private var plan: SkillRuntimeContract.ExecutionPlan?
    @State private var receipt: SkillRuntimeService.Receipt?
    @State private var output = ""
    @State private var error: String?
    @State private var working = false
    @State private var confirmRun = false
    @State private var operation: Task<Void, Never>?
    @State private var revision = UUID()

    private var scripts: [SkillResourceFile] {
        resources.filter { SkillRuntimeRequirements.suggestedEngine(path: $0.relativePath) != nil }
    }
    private var selectionID: String { skillID.rawValue + ":" + path + ":" + engine.rawValue }

    var body: some View {
        Section(SkillL10n.string("Compatibility")) {
            Picker("Action", selection: $path) {
                Text("Instructions").tag("")
                ForEach(scripts) { Text($0.relativePath).tag($0.relativePath) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("hanlin-skill-action-picker")
            if !path.isEmpty {
                Picker("Engine", selection: $engine) {
                    ForEach(RuntimeKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("hanlin-skill-engine-picker")
            }
            LabeledContent(SkillL10n.string("Status"), value: status)
                .accessibilityValue(status)
                .accessibilityIdentifier("hanlin-skill-detail-compatibility-status")
            if let plan {
                LabeledContent("Source", value: String(plan.action.actionFingerprint.prefix(12)))
                if let binding = plan.binding {
                    LabeledContent("Observed engine", value: binding.engineVersion)
                }
                ForEach(plan.missingRequirements, id: \.id) { requirement in
                    Label(requirement.key.name, systemImage: "exclamationmark.circle")
                }
                ForEach(Array(plan.issues.enumerated()), id: \.offset) { _, issue in
                    Text(issue.code.rawValue).font(.footnote).foregroundStyle(.secondary)
                }
            }
            LabeledContent(SkillL10n.string("Last tested"), value: lastTest)
                .accessibilityValue(lastTest)
                .accessibilityIdentifier("hanlin-skill-detail-compatibility-last-tested")
            if let receipt {
                Text("\(receiptIsCurrent ? receipt.status.rawValue : "Historical \(receipt.status.rawValue) — source or engine changed") · \(receipt.result.executionID.uuidString.prefix(8))")
                    .font(.caption).textSelection(.enabled)
                    .accessibilityIdentifier("hanlin-skill-execution-receipt")
            }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if !path.isEmpty {
                Button("Start engine and recheck") { begin(run: false) }
                    .accessibilityIdentifier("hanlin-skill-recheck")
                    .disabled(working)
                Button("Run with approval") { confirmRun = true }
                    .accessibilityIdentifier("hanlin-skill-run")
                    .disabled(working)
            }
            if working {
                ProgressView()
                Button("Cancel", role: .cancel) { operation?.cancel() }
                    .accessibilityIdentifier("hanlin-skill-cancel-execution")
            }
            if !output.isEmpty {
                Text(output).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    .accessibilityIdentifier("hanlin-skill-execution-output")
            }
            Text("Compatibility is evaluated without running imported code. Run executes code with this app’s access after your approval.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .task(id: selectionID) {
            operation?.cancel(); revision = UUID(); working = false; plan = nil; receipt = nil; output = ""; error = nil
            let token = revision
            do {
                let value = try await SkillRuntimeService.shared.plan(skillID: skillID,
                    path: path.isEmpty ? nil : path,
                    engine: path.isEmpty ? nil : SkillRuntimeRequirements.engine(engine))
                guard !Task.isCancelled, revision == token else { return }
                plan = value
                receipt = try SkillRuntimeService.shared.receipt(skillID: skillID, path: path)
                if let receipt, receipt.test?.sourceFingerprint == value.action.sourceFingerprint,
                   receipt.test?.actionFingerprint == value.action.actionFingerprint {
                    output = receipt.result.stdout + receipt.result.stderr
                }
            } catch { if !Task.isCancelled, revision == token { self.error = error.localizedDescription } }
        }
        .onChange(of: path) { _, value in
            if let suggestion = SkillRuntimeRequirements.suggestedEngine(path: value),
               let kind = SkillRuntimeRequirements.kind(suggestion) { engine = kind }
        }
        .onDisappear { revision = UUID(); operation?.cancel() }
        .confirmationDialog("Run imported code?", isPresented: $confirmRun, titleVisibility: .visible) {
            Button("Allow once") { begin(run: true) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("\(skillID.rawValue) · \(path) · \(engine.rawValue)") }
    }

    private var status: String {
        guard let plan else { return SkillL10n.string("Unknown") }
        if plan.action.kind == .instructions {
            return plan.action.requirementsComplete ? "PARSE_ONLY" : "UNKNOWN"
        }
        return plan.isExecutable ? (plan.readiness == .verified ? "EXECUTION_PASS" : "PLAN_READY") : plan.readiness.rawValue
    }

    private var receiptIsCurrent: Bool {
        guard let receipt, let test = receipt.test, let plan else { return false }
        return test.sourceFingerprint == plan.action.sourceFingerprint
            && test.actionFingerprint == plan.action.actionFingerprint
            && test.binding == plan.binding
            && test.invocationFingerprint == plan.action.invocationFingerprint
    }

    private var lastTest: String {
        guard let date = plan?.lastTest?.evidence.observedAt else { return SkillL10n.string("Not recorded") }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func begin(run: Bool) {
        operation?.cancel()
        let token = UUID(); revision = token
        let selectedPath = path, selectedEngine = engine
        working = true; error = nil
        operation = Task { @MainActor in
            defer { if revision == token { working = false; operation = nil } }
            do {
                if run {
                    let session = AssistantCapabilitySession(chatID: "skill-center-" + skillID.rawValue)
                    guard let descriptor = HanlinSkillCatalog.shared.resolve(id: skillID) else { throw RuntimeCoreError.invalidPath }
                    let instructions = await HanlinSkillCatalog.shared.loadInstructions(for: descriptor)
                    try Task.checkCancellation()
                    session.recordSkillLoaded(id: skillID, instructionText: instructions)
                    let args = try JSONSerialization.data(withJSONObject: ["skill_id": skillID.rawValue,
                        "relative_path": selectedPath, "engine": selectedEngine.rawValue])
                    let result = await RuntimeJobProgress.$reporter.withValue({ job in
                        guard revision == token, job.stdoutBytes > 0 else { return }
                        let file = AppRuntimeCore.shared.jobs.directory(id: job.executionID, kind: selectedEngine).appending(path: "stdout.log")
                        if let bytes = try? Data(contentsOf: file, options: .mappedIfSafe), bytes.count <= 1_048_576 {
                            output = String(decoding: bytes, as: UTF8.self)
                        }
                    }) {
                        await SkillRuntimeAuthorization.$approved.withValue(true) {
                            await ExecuteSkillResourceTool().execute(argumentsJSON: String(decoding: args, as: UTF8.self),
                                context: .init(localeIdentifier: Locale.current.identifier, capabilitySession: session))
                        }
                    }
                    guard revision == token else { return }
                    output = result.userText ?? result.modelText
                } else {
                    _ = try await SkillRuntimeService.shared.recheck(skillID: skillID, path: selectedPath,
                        engine: SkillRuntimeRequirements.engine(selectedEngine))
                }
                guard revision == token else { return }
                receipt = try SkillRuntimeService.shared.receipt(skillID: skillID, path: selectedPath)
                if Task.isCancelled {
                    if let receipt { output = receipt.result.stdout + receipt.result.stderr }
                    return
                }
                plan = try await SkillRuntimeService.shared.plan(skillID: skillID, path: selectedPath,
                    engine: SkillRuntimeRequirements.engine(selectedEngine))
                receipt = try SkillRuntimeService.shared.receipt(skillID: skillID, path: selectedPath)
            } catch { if revision == token { self.error = error.localizedDescription } }
        }
    }
}
