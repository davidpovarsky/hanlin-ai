import HanlinScriptStore
import HanlinScriptExtensions
import QuickLook
import SwiftUI

struct ChavrusaShareInboxView: View {
    let platform: HanlinScriptingPlatform
    @State private var batches: [HanlinShareBatch] = []
    @State private var legacyItems: [ChavrusaSharedItem] = []
    @State private var hasUnreadableItems = false
    @State private var loadFailed = false
    @State private var previewFile: URL?
    @State private var receipts: [UUID: HanlinInvocationReceipt] = [:]
    @State private var commands: [UUID: HanlinScriptResumeCommand] = [:]
    @State private var submitting: Set<UUID> = []
    @State private var actionFailed = false

    var body: some View {
        List {
            Section {
                Text("These items are saved on this device. Choose a MiniApp action to send a batch. Its actual status and result appear below.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if loadFailed || hasUnreadableItems {
                Section {
                    Label("Some shared items couldn’t be read. Their original files were kept.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            ForEach(batches) { batch in
                Section {
                    ForEach(batch.items) { item in
                        switch item.content {
                        case .text, .url:
                            Text(item.text ?? "").textSelection(.enabled)
                        case .file:
                            Button {
                                Task {
                                    do { previewFile = try await ChavrusaShareInbox.shared.ownedFile(batchID: batch.id, itemID: item.id) }
                                    catch { loadFailed = true }
                                }
                            } label: {
                                Label(item.name ?? String(localized: "Shared file"), systemImage: "doc")
                            }
                            .accessibilityIdentifier("hanlin-share-file-\(item.id.uuidString.lowercased())")
                        case .rejected:
                            Label("This item could not be loaded from the source app.", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
                        }
                    }
                    deliveryControls(for: batch)
                } header: { Text(batch.createdAt, style: .date) }
            }
            if !legacyItems.isEmpty {
                Section("Earlier Shared Items") {
                    ForEach(legacyItems) { item in
                        if let text = item.text { Text(text).textSelection(.enabled) }
                        else if let url = item.url, !url.isFileURL { Text(url.absoluteString).textSelection(.enabled) }
                        else { Text("An earlier file link may no longer be available. The original record was kept.") }
                    }
                }
            }
        }
        .navigationTitle("Shared Items")
        .accessibilityIdentifier("hanlin-share-inbox")
        .task { await reload() }
        .task(id: observedInvocationIDs) {
            guard !observedInvocationIDs.isEmpty else { return }
            // Observe durable receipts only while this screen is visible. A
            // running receipt is never presented as successful completion.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                refreshReceipts()
            }
        }
        .refreshable { await reload() }
        .quickLookPreview($previewFile)
        .alert("The action could not be submitted", isPresented: $actionFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The saved items were kept. Refresh to check the original action’s status before trying again.")
        }
    }

    private var observedInvocationIDs: [UUID] {
        receipts.values.filter { !$0.status.isTerminal }.map(\.invocationID)
            .sorted { $0.uuidString < $1.uuidString }
    }

    @ViewBuilder private func deliveryControls(for batch: HanlinShareBatch) -> some View {
        if let receipt = receipts[batch.id] {
            LabeledContent("Action status", value: statusText(receipt))
                .accessibilityIdentifier("hanlin-share-status-\(batch.id.uuidString.lowercased())")
            if let command = commands[batch.id] {
                Text("\(command.invocation.delivery?.appID.rawValue ?? command.invocation.identity.packageID.rawValue) · \(command.invocation.entityID ?? "")")
                    .font(.caption).textSelection(.enabled)
            }
            if let value = receipt.value,
               let data = try? JSONEncoder().encode(value), let text = String(data: data, encoding: .utf8) {
                Text(text).textSelection(.enabled)
            }
            if !receipt.status.isTerminal && !receipt.cancellationRequested {
                Button("Cancel action", role: .destructive) {
                    do { try platform.cancelResumeCommand(batch.id); refreshReceipts() }
                    catch { actionFailed = true }
                }
            }
        } else if platform.shareActionTargets.isEmpty {
            Text("No installed MiniApp currently declares a supported share action.")
                .font(.footnote).foregroundStyle(.secondary)
        } else {
            Menu("Choose MiniApp action") {
                ForEach(platform.shareActionTargets) { target in
                    Button(target.title) {
                        submitting.insert(batch.id)
                        Task {
                            defer { submitting.remove(batch.id); refreshReceipts() }
                            do { try await platform.submitShareBatch(batch.id, to: target) }
                            catch { actionFailed = true }
                        }
                    }
                }
            }
            .disabled(submitting.contains(batch.id))
            .accessibilityIdentifier("hanlin-share-choose-\(batch.id.uuidString.lowercased())")
        }
    }

    private func statusText(_ receipt: HanlinInvocationReceipt) -> String {
        if receipt.cancellationRequested && !receipt.status.isTerminal { return String(localized: "Cancellation requested; waiting for the action to stop") }
        switch receipt.status {
        case .queued: return String(localized: "Queued; waiting for the Host")
        case .running: return String(localized: "Running")
        case .succeeded: return String(localized: "Completed")
        case .cancelled: return String(localized: "Cancelled")
        case .expired: return String(localized: "Expired")
        case .stale: return String(localized: "The installed target changed")
        case .needsForeground, .deferred: return String(localized: "Open the target app to continue")
        case .failed: return String(localized: "The action failed; saved items were kept")
        case .acknowledged: return String(localized: "Acknowledged")
        }
    }

    private func refreshReceipts() {
        do {
            var updatedReceipts: [UUID: HanlinInvocationReceipt] = [:]
            var updatedCommands: [UUID: HanlinScriptResumeCommand] = [:]
            for batch in batches {
                updatedReceipts[batch.id] = try platform.resumeReceipt(batch.id)
                updatedCommands[batch.id] = try platform.submittedResumeCommand(batch.id)
            }
            receipts = updatedReceipts
            commands = updatedCommands
        } catch { loadFailed = true }
    }

    private func reload() async {
        do {
            let scan = try await ChavrusaShareInbox.shared.pendingBatches()
            batches = scan.batches
            hasUnreadableItems = !scan.rejected.isEmpty
            legacyItems = try await ChavrusaShareInbox.shared.pendingItems()
            loadFailed = false
            refreshReceipts()
        } catch { loadFailed = true }
    }
}
