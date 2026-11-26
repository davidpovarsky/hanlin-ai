import Foundation
import HanlinProductSplit
import HanlinScriptCompiler
import Observation
import SwiftData

/// One receiving window owns each user-requested repair. It hands the payload
/// to the existing mounted composer, retaining the ordinary agent/tool pipeline.
@MainActor @Observable
final class MiniAppRepairCoordinator {
    struct Pending: Identifiable {
        let id: UUID
        let conversationID: UUID
        let text: String
        let documents: [URL]
        let selectedModelIndex: Int
    }

    static let shared = MiniAppRepairCoordinator()
    private(set) var pending: [UUID: Pending] = [:]
    private(set) var destinations: [UUID: UUID] = [:]
    private(set) var failures: [UUID: String] = [:]
    @ObservationIgnored private var claims: [UUID: UUID] = [:]
    @ObservationIgnored private var waiting: [UUID: [Pending]] = [:]

    func pending(for window: UUID?) -> Pending? { window.flatMap { pending[$0] } }
    func destination(for window: UUID?) -> UUID? { window.flatMap { destinations[$0] } }
    func failure(for window: UUID?) -> String? { window.flatMap { failures[$0] } }
    func dismissFailure(for window: UUID?) { if let window { failures[window] = nil } }
    func release(window: UUID) {
        claims = claims.filter { $0.value != window }
        pending[window] = nil
        waiting[window] = nil
        destinations[window] = nil
        failures[window] = nil
    }

    /// Called synchronously from the real onOpenURL receiver before its await.
    func claim(_ url: URL, window: UUID?) -> UUID? {
        guard let window,
              let id = MiniAppAuthoringTransfer.reference(in: url, purpose: .repair),
              claims[id] == nil else { return nil }
        claims[id] = window
        NSLog("HANLIN_MINIAPP_REPAIR_CLAIMED %@", id.uuidString)
        return id
    }

    func receive(_ id: UUID, window: UUID, context: HanlinApplicationContext) async {
        guard claims[id] == window else { return }
        do {
            // The original conversation store is sufficient for this handoff.
            // Scene preparation warms runtimes independently; waiting for MCP,
            // notifications or Node here would hide the user's repair request.
            NSLog("HANLIN_MINIAPP_REPAIR_RECEIVING %@", id.uuidString)
            context.dataManager.preloadDataIfNeeded()
            guard claims[id] == window else { return }
            let (store, transfer, archive) = try MiniAppAuthoringDelivery.verifiedArchive(id, purpose: .repair)
            let previous = try store.receipt(for: id)
            let modelContext = context.modelContainer.mainContext
            let record: ChatRecords
            if let conversationID = previous.conversationID {
                record = try context.record(conversationID)
            } else {
                record = try HanlinConversationCreation.create(in: modelContext,
                    title: "MiniApp · " + transfer.originalFileName)
                guard let conversationID = record.id else { throw HanlinApplicationError.invalidConversation }
                try store.record(.init(transferID: id, status: .received, conversationID: conversationID))
                NSLog("HANLIN_MINIAPP_REPAIR_CONVERSATION %@", conversationID.uuidString)
            }
            guard let conversationID = record.id,
                  let modelIndex = record.useModel else { throw HanlinApplicationError.invalidConversation }
            let marker = "[MiniApp repair \(id.uuidString.lowercased())]"
            // If the process ended after the original composer saved the user
            // message, recover that actual send instead of issuing it twice.
            if let sent = record.messages?.first(where: { $0.role == "user" && ($0.text?.contains(marker) == true) }) {
                if previous.status != .submitted {
                    try store.record(.init(transferID: id, status: .submitted,
                        conversationID: conversationID, userMessageID: sent.id))
                }
                if pending[window] == nil { destinations[window] = conversationID }
                return
            }
            if previous.status == .submitted {
                if pending[window] == nil { destinations[window] = conversationID }
                return
            }

            let layout = RuntimeFileLayout.default
            try layout.prepareIfNeeded()
            let workspace = try layout.workspace(client: .agents,
                identifier: "miniapp-repair-" + id.uuidString.lowercased())
            let ownedArchive = workspace.appending(path: transfer.originalFileName)
            if !FileManager.default.fileExists(atPath: ownedArchive.path) {
                try FileManager.default.copyItem(at: archive, to: ownedArchive)
            }
            let reportURL = workspace.appending(path: "diagnostics.json")
            if !FileManager.default.fileExists(atPath: reportURL.path) {
                try FileManager.default.copyItem(at: store.diagnosticsURL(for: id), to: reportURL)
            }
            let project = workspace.appending(path: "project", directoryHint: .isDirectory)
            var extractionMessage = ""
            if !FileManager.default.fileExists(atPath: project.path) {
                do {
                    let center = HanlinPackageCenter()
                    let staged = try center.stageAndInspect(sourceURL: ownedArchive, stagingParent: workspace)
                    defer { try? center.discard(staged) }
                    try FileManager.default.copyItem(at: staged.packageRoot, to: project)
                } catch {
                    // A malformed manifest/ZIP is still repairable by the agent.
                    // Preserve its exact bytes and expose the actual diagnostic.
                    extractionMessage = "\nProject extraction diagnostic: \(error.localizedDescription). Inspect the original archive and repair its package structure first."
                }
            }
            let report = try String(contentsOf: reportURL, encoding: .utf8)
            let text = """
            \(marker)
            תקן את חבילת המיני־אפליקציה \(transfer.originalFileName) ואת השגיאות המצורפות, עד לבנייה, אימות וייבוא מוצלחים ל־Hanlin MiniApps.
            Original package: \(ownedArchive.path(percentEncoded: false))
            Working project: \(project.path(percentEncoded: false))
            Diagnostic report: \(reportURL.path(percentEncoded: false))
            \(extractionMessage)

            Use get_miniapp_sdk for the current host APIs, original library types and examples. Use validate_miniapp with the working project; its sourceRoot identifies the editable project inside source/. Use write_miniapp to repair the actual source in that sourceRoot, run validation again, build with build_miniapp and deliver the resulting archive with import_miniapp. Query import_miniapp with the returned transfer_id for the actual installation result. Preserve package identity, functionality and user data. Report real compiler errors with their file/line/column; do not hide errors or treat a queued import as installed. Legacy Scripting is frozen; active targets are Expo, NativeScript and ScriptWidget.

            Diagnostics:
            \(report)
            """
            guard claims[id] == window else { return }
            let request = Pending(id: id, conversationID: conversationID, text: text,
                documents: [], selectedModelIndex: modelIndex)
            if pending[window] == nil {
                pending[window] = request
                destinations[window] = conversationID
                NSLog("HANLIN_MINIAPP_REPAIR_PENDING %@", id.uuidString)
            } else {
                waiting[window, default: []].append(request)
            }
        } catch {
            NSLog("HANLIN_MINIAPP_REPAIR_FAILED %@", id.uuidString)
            failures[window] = error.localizedDescription
            claims[id] = nil
        }
    }

    func acknowledge(_ submission: HanlinPendingFirstTurn?, window: UUID?) {
        guard let window, let submission, let request = pending[window],
              request.id == submission.submissionID else { return }
        guard case .dispatched(let conversationID) = submission.status else {
            switch submission.status {
            case .failed(let reason), .cancelled(let reason):
                failures[window] = reason
                claims[request.id] = nil
                pending[window] = nil
                activateNext(window)
            default: break
            }
            return
        }
        do {
            try MiniAppAuthoringDelivery.store().record(.init(transferID: request.id, status: .submitted,
                conversationID: conversationID, userMessageID: submission.acceptedUserMessageID))
            pending[window] = nil
            activateNext(window)
        } catch {
            failures[window] = error.localizedDescription
        }
    }

    private func activateNext(_ window: UUID) {
        guard var queue = waiting[window], !queue.isEmpty else { return }
        let next = queue.removeFirst()
        waiting[window] = queue
        pending[window] = next
        destinations[window] = next.conversationID
    }
}
