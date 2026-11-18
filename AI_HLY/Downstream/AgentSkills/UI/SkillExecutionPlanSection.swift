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
    @State private var originalPolicy: SkillRuntimeOpenClaw.Report?
    @State private var output = ""
    @State private var findings: [SkillSyntaxFinding] = []
    @State private var error: String?
    @State private var working = false
    @State private var confirmRun = false
    @State private var operation: Task<Void, Never>?
    @State private var revision = UUID()

    private var scripts: [SkillResourceFile] {
        resources.filter { SkillRuntimeRequirements.suggestedEngine(path: $0.relativePath) != nil }
    }
    private var selectionID: String {
        skillID.rawValue + ":" + path + ":" + engine.rawValue + ":" + String(SkillStore.shared.revision)
    }

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
            if let originalPolicy {
                let availability = SkillL10n.string(originalPolicy.known
                    ? (originalPolicy.rawUpstreamResult?.eligible == true ? "Available" : "Unavailable") : "Unknown")
                LabeledContent(SkillL10n.string("Skill requirements"), value: availability)
                    .accessibilityValue(availability)
                    .accessibilityIdentifier("hanlin-skill-openclaw-policy")
                if !originalPolicy.invocation.userInvocable { Text(SkillL10n.string("This Skill does not allow manual invocation.")).font(.footnote) }
                if originalPolicy.invocation.disableModelInvocation { Text(SkillL10n.string("This Skill is hidden from automatic model invocation.")).font(.footnote) }
                ForEach(originalPolicy.unobserved, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                if !originalPolicy.installHints.isEmpty {
                    Text(SkillL10n.string("Suggested installation")).font(.headline)
                    ForEach(Array(originalPolicy.installHints.enumerated()), id: \.offset) { _, hint in
                        LabeledContent(hint.label ?? hint.kind, value: hint.target)
                            .accessibilityValue(hint.target)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("hanlin-skill-openclaw-install-hint")
                    }
                    Text(SkillL10n.string("Installer suggestions do not install anything automatically. Use a package manager available for the selected runtime."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            ForEach(Array(findings.prefix(64).enumerated()), id: \.offset) { _, finding in
                VStack(alignment: .leading) {
                    Text("\(finding.source.file):\(finding.source.line):\(finding.source.utf8Column)")
                    Text(finding.value ?? finding.reason).textSelection(.enabled)
                    Text("\(finding.confidence.rawValue) · \(finding.reason)").foregroundStyle(.secondary)
                }.font(.caption)
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
            if !path.isEmpty || HanlinSkillCatalog.shared.markdownDocument(for: skillID).map({ SkillRuntimeOpenClaw.requiresPolicy($0) || SkillRuntimeOpenClaw.hasInvocationMetadata($0) }) == true {
                Button(SkillL10n.string(path.isEmpty ? "Check compatibility" : "Start engine and recheck")) { begin(run: false) }
                    .accessibilityIdentifier("hanlin-skill-recheck")
                    .disabled(working || !SkillStore.shared.isSkillEnabled(id: skillID))
            }
            if !path.isEmpty {
                Button("Run with approval") { confirmRun = true }
                    .accessibilityIdentifier("hanlin-skill-run")
                    .disabled(working || !SkillStore.shared.isSkillEnabled(id: skillID)
                              || originalPolicy?.invocation.userInvocable == false)
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
            operation?.cancel(); revision = UUID(); working = false; plan = nil; receipt = nil; originalPolicy = nil; findings = []; output = ""; error = nil
            let token = revision
            receipt = try? SkillRuntimeService.shared.receipt(skillID: skillID, path: path)
            guard SkillStore.shared.isSkillEnabled(id: skillID) else { return }
            do {
                let value = try await SkillRuntimeService.shared.plan(skillID: skillID,
                    path: path.isEmpty ? nil : path,
                    engine: path.isEmpty ? nil : SkillRuntimeRequirements.engine(engine))
                guard !Task.isCancelled, revision == token else { return }
                plan = value
                originalPolicy = await SkillRuntimeService.shared.policyReport(skillID: skillID)
                findings = SkillRuntimeService.shared.findings(skillID: skillID, path: path.isEmpty ? nil : path)
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
        guard SkillStore.shared.isSkillEnabled(id: skillID) else { return "DISABLED" }
        guard let plan else { return SkillL10n.string("Unknown") }
        if plan.action.kind == .instructions {
            return plan.action.requirementsComplete ? "PARSE_ONLY" : "UNKNOWN"
        }
        if receiptIsCurrent, let receipt, receipt.status != .executionPass { return receipt.status.rawValue }
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
        if let receipt {
            return receipt.recordedAt.formatted(date: .abbreviated, time: .shortened)
                + (receiptIsCurrent ? "" : " · Historical")
        }
        guard let date = plan?.lastTest?.evidence.observedAt else { return SkillL10n.string("Not recorded") }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func begin(run: Bool) {
        guard SkillStore.shared.isSkillEnabled(id: skillID) else { return }
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
                        await SkillRuntimeAuthorization.$invocationSource.withValue(.user) {
                            await SkillRuntimeAuthorization.$approved.withValue(true) {
                                await ExecuteSkillResourceTool().execute(argumentsJSON: String(decoding: args, as: UTF8.self),
                                    context: .init(localeIdentifier: Locale.current.identifier, capabilitySession: session))
                            }
                        }
                    }
                    guard revision == token else { return }
                    output = result.userText ?? result.modelText
                } else {
                    _ = try await SkillRuntimeService.shared.recheck(skillID: skillID, path: selectedPath.isEmpty ? nil : selectedPath,
                        engine: selectedPath.isEmpty ? nil : SkillRuntimeRequirements.engine(selectedEngine))
                }
                guard revision == token else { return }
                receipt = try SkillRuntimeService.shared.receipt(skillID: skillID, path: selectedPath)
                if Task.isCancelled {
                    if let receipt { output = receipt.result.stdout + receipt.result.stderr }
                    // The cancellation receipt describes the engine that actually ran. Refresh
                    // passive facts outside the cancelled observer, rather than compare it with
                    // the pre-start Unknown plan and falsely label it historical.
                    let refreshed = try await Task { @MainActor in
                        try await SkillRuntimeService.shared.plan(skillID: skillID, path: selectedPath.isEmpty ? nil : selectedPath,
                            engine: selectedPath.isEmpty ? nil : SkillRuntimeRequirements.engine(selectedEngine))
                    }.value
                    guard revision == token else { return }
                    plan = refreshed
                    return
                }
                plan = try await SkillRuntimeService.shared.plan(skillID: skillID, path: selectedPath.isEmpty ? nil : selectedPath,
                    engine: selectedPath.isEmpty ? nil : SkillRuntimeRequirements.engine(selectedEngine))
                receipt = try SkillRuntimeService.shared.receipt(skillID: skillID, path: selectedPath)
                originalPolicy = await SkillRuntimeService.shared.policyReport(skillID: skillID)
                findings = SkillRuntimeService.shared.findings(skillID: skillID, path: selectedPath.isEmpty ? nil : selectedPath)
            } catch { if revision == token { self.error = error.localizedDescription } }
        }
    }
}
