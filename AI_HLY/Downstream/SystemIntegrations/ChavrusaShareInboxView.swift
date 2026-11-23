import HanlinPresentationKit
import HanlinLocalization
import HanlinScriptStore
import HanlinScriptExtensions
import QuickLook
import SwiftUI

struct ChavrusaShareInboxView: View {
    let platform: HanlinScriptingPlatform
    var useInChat: ((UUID) async throws -> Void)? = nil
    @State private var batches: [HanlinShareBatch] = []
    @State private var legacyItems: [ChavrusaSharedItem] = []
    @State private var hasUnreadableItems = false
    @State private var loadFailed = false
    @State private var previewFile: URL?
    @State private var receipts: [UUID: HanlinInvocationReceipt] = [:]
    @State private var commands: [UUID: HanlinScriptResumeCommand] = [:]
    @State private var submitting: Set<UUID> = []
    @State private var actionFailed = false
    @State private var draftTask: Task<Void, Never>?
    @State private var preparingDraft: UUID?
    @State private var draftFailed = false
    @State private var draftFailure = ""

    var body: some View {
        List {
            Section {
                if useInChat != nil {
                    Text("Choose a batch to add its text, links and files to your current draft. Nothing is sent until you tap Send.", bundle: HanlinLocalization.bundle)
                        .font(HanlinTypography.footnote).foregroundStyle(.secondary)
                } else {
                    Text("These items are saved on this device. Choose a MiniApp action to send a batch. Its actual status and result appear below.", bundle: HanlinLocalization.bundle)
                        .font(HanlinTypography.footnote).foregroundStyle(.secondary)
                }
                if batches.isEmpty && legacyItems.isEmpty && !loadFailed {
                    Text("No shared items yet", bundle: HanlinLocalization.bundle).foregroundStyle(.secondary)
                }
            }
            if loadFailed || hasUnreadableItems {
                Section {
                    Label(hanlin: "Some shared items couldn’t be read. Their original files were kept.", systemImage: "exclamationmark.triangle")
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
                                Label(item.name ?? String(localized: "Shared file", bundle: HanlinLocalization.bundle), systemImage: "doc")
                            }
                            .accessibilityIdentifier("hanlin-share-file-\(item.id.uuidString.lowercased())")
                        case .rejected:
                            Label(hanlin: "This item could not be loaded from the source app.", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let useInChat {
                        Button {
                            preparingDraft = batch.id
                            draftTask = Task {
                                defer { preparingDraft = nil; draftTask = nil }
                                do { try await useInChat(batch.id) }
                                catch is CancellationError { }
                                catch {
                                    draftFailure = (error as? ChavrusaShareDraftError)?.errorDescription
                                        ?? String(localized: "The shared items could not be added. Your draft and the original items were kept.", bundle: HanlinLocalization.bundle)
                                    draftFailed = true
                                }
                            }
                        } label: {
                            Label(hanlin: "Add to draft", systemImage: "text.badge.plus")
                        }
                        .disabled(preparingDraft != nil)
                        .accessibilityIdentifier("hanlin-share-add-draft-" + batch.id.uuidString.lowercased())
                    } else {
                        deliveryControls(for: batch)
                    }
                } header: { Text(batch.createdAt, style: .date) }
            }
            if !legacyItems.isEmpty {
                Section(hanlin: "Earlier Shared Items") {
                    ForEach(legacyItems) { item in
                        if let text = item.text { Text(text).textSelection(.enabled) }
                        else if let url = item.url, !url.isFileURL { Text(url.absoluteString).textSelection(.enabled) }
                        else { Text("An earlier file link may no longer be available. The original record was kept.", bundle: HanlinLocalization.bundle) }
                    }
                }
            }
        }
        .navigationTitle(Text("Shared Items", bundle: HanlinLocalization.bundle))
        .accessibilityIdentifier("hanlin-share-inbox")
        .task {
#if (DEBUG || HANLIN_TESTING) && targetEnvironment(simulator)
            if let raw = ProcessInfo.processInfo.environment["HANLIN_SHARE_DRAFT_ACCEPTANCE_ID"],
               let nonce = UUID(uuidString: raw) {
                do { try await ChavrusaShareInbox.shared.seedDraftAcceptanceIfRequested(nonce) }
                catch { loadFailed = true; return }
            }
#endif
            await reload()
        }
        .onDisappear { draftTask?.cancel() }
        .alert(Text("Couldn’t add shared items", bundle: HanlinLocalization.bundle), isPresented: $draftFailed) {
            Button(hanlin: "OK", role: .cancel) {}
        } message: { Text(draftFailure) }
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
        .alert(Text("The action could not be submitted", bundle: HanlinLocalization.bundle), isPresented: $actionFailed) {
            Button(hanlin: "OK", role: .cancel) {}
        } message: {
            Text("The saved items were kept. Refresh to check the original action’s status before trying again.", bundle: HanlinLocalization.bundle)
        }
    }

    private var observedInvocationIDs: [UUID] {
        receipts.values.filter { !$0.status.isTerminal }.map(\.invocationID)
            .sorted { $0.uuidString < $1.uuidString }
    }

    @ViewBuilder private func deliveryControls(for batch: HanlinShareBatch) -> some View {
        if let receipt = receipts[batch.id] {
            LabeledContent(hanlin: "Action status", value: statusText(receipt))
                .accessibilityIdentifier("hanlin-share-status-\(batch.id.uuidString.lowercased())")
            if let command = commands[batch.id] {
                Text("\(command.invocation.delivery?.appID.rawValue ?? command.invocation.identity.packageID.rawValue) · \(command.invocation.entityID ?? "")", bundle: HanlinLocalization.bundle)
                    .font(HanlinTypography.caption).textSelection(.enabled)
            }
            if let value = receipt.value,
               let data = try? JSONEncoder().encode(value), let text = String(data: data, encoding: .utf8) {
                Text(text).textSelection(.enabled)
            }
            if !receipt.status.isTerminal && !receipt.cancellationRequested {
                Button(hanlin: "Cancel action", role: .destructive) {
                    do { try platform.cancelResumeCommand(batch.id); refreshReceipts() }
                    catch { actionFailed = true }
                }
            }
        } else if platform.shareActionTargets.isEmpty {
            Text("No installed MiniApp currently declares a supported share action.", bundle: HanlinLocalization.bundle)
                .font(HanlinTypography.footnote).foregroundStyle(.secondary)
        } else {
            Menu(hanlin: "Choose MiniApp action") {
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
        if receipt.cancellationRequested && !receipt.status.isTerminal { return String(localized: "Cancellation requested; waiting for the action to stop", bundle: HanlinLocalization.bundle) }
        switch receipt.status {
        case .queued: return String(localized: "Queued; waiting for the Host", bundle: HanlinLocalization.bundle)
        case .running: return String(localized: "Running", bundle: HanlinLocalization.bundle)
        case .succeeded: return String(localized: "Completed", bundle: HanlinLocalization.bundle)
        case .cancelled: return String(localized: "Cancelled", bundle: HanlinLocalization.bundle)
        case .expired: return String(localized: "Expired", bundle: HanlinLocalization.bundle)
        case .stale: return String(localized: "The installed target changed", bundle: HanlinLocalization.bundle)
        case .needsForeground, .deferred: return String(localized: "Open the target app to continue", bundle: HanlinLocalization.bundle)
        case .failed: return String(localized: "The action failed; saved items were kept", bundle: HanlinLocalization.bundle)
        case .acknowledged: return String(localized: "Acknowledged", bundle: HanlinLocalization.bundle)
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
