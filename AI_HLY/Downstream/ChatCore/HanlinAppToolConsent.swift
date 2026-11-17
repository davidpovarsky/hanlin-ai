import Foundation
import Observation
import HanlinHostContracts
import HanlinAgentCore

/// Live, one-use approval in the original conversation. History never recreates a grant.
@MainActor @Observable
final class HanlinAppToolConsent {
    struct Request: Identifiable {
        let id: UUID
        let tool: String
        let canonicalRunID: UUID
        let providerCallID: String
        let originalArgumentsJSON: Data?
        let providerApprovalID: String?
        var activityID: String { providerApprovalID ?? id.uuidString }
    }
    private(set) var pending: Request?
    @ObservationIgnored var onChange: ((Request, Bool?) -> Void)?
    @ObservationIgnored private var continuation: CheckedContinuation<Bool, Never>?
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?

    func request(_ invocation: HanlinHostInvocation) async -> Bool {
        await request(.init(id: UUID(), tool: invocation.request.aliasUsed,
            canonicalRunID: invocation.runID, providerCallID: invocation.providerCallID,
            originalArgumentsJSON: invocation.originalArgumentsJSON, providerApprovalID: nil),
            deadline: invocation.request.deadline)
    }

    func request(_ approval: HanlinAgentToolApproval) async -> Bool {
        await request(.init(id: UUID(), tool: approval.request.toolName,
            canonicalRunID: approval.runID, providerCallID: approval.request.toolCallID,
            originalArgumentsJSON: Data(approval.request.argumentsJSON.utf8),
            providerApprovalID: approval.request.approvalID), deadline: approval.deadline)
    }

    private func request(_ request: Request, deadline: Date?) async -> Bool {
        guard pending == nil, !Task.isCancelled else { return false }
        let id = request.id
        let remaining = deadline?.timeIntervalSinceNow ?? 0
        guard remaining > 0 else { return false }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { reply in
                guard !Task.isCancelled else { reply.resume(returning: false); return }
                continuation = reply
                pending = request
                if let pending { onChange?(pending, nil) }
                deadlineTask = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(remaining)) }
                    catch { return }
                    self?.answer(id: id, allowed: false)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.answer(id: id, allowed: false) }
        }
    }

    func answer(id: UUID, allowed: Bool) {
        guard pending?.id == id else { return }
        if let pending { onChange?(pending, allowed) }
        let reply = continuation
        deadlineTask?.cancel(); deadlineTask = nil
        pending = nil; continuation = nil
        reply?.resume(returning: allowed)
    }

    func revoke() {
        if let pending { answer(id: pending.id, allowed: false) }
    }
}
