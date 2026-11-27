import Foundation
import Observation
import HanlinHostContracts
import HanlinAgentCore

/// Live consent for a verified scope. A remembered host grant is independent of
/// conversation history; provider-only requests remain one-use.
@MainActor @Observable
public final class HanlinAppToolConsent {
    public struct Request: Identifiable {
        public let id: UUID
        public let tool: String
        public let canonicalRunID: UUID
        public let providerCallID: String
        public let originalArgumentsJSON: Data?
        public let providerApprovalID: String?
        let approvalScope: HanlinToolApprovalScope?
        public var remembersDecision: Bool { approvalScope != nil }
        public var activityID: String { providerApprovalID ?? id.uuidString }
    }
    public private(set) var pending: Request?
    @ObservationIgnored var onChange: ((Request, Bool?) -> Void)?
    @ObservationIgnored private var continuation: CheckedContinuation<Bool, Never>?
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?
    @ObservationIgnored private let grants: HanlinToolApprovalStore

    public convenience init() { self.init(grants: .shared) }
    init(grants: HanlinToolApprovalStore) { self.grants = grants }

    func request(_ invocation: HanlinHostInvocation, approvalScope: HanlinToolApprovalScope) async -> Bool {
        guard !Task.isCancelled else { return false }
        if grants.allows(approvalScope) { return true }
        return await request(.init(id: UUID(), tool: invocation.request.aliasUsed,
            canonicalRunID: invocation.runID, providerCallID: invocation.providerCallID,
            originalArgumentsJSON: invocation.originalArgumentsJSON, providerApprovalID: nil,
            approvalScope: approvalScope),
            deadline: invocation.request.deadline)
    }

    public func request(_ approval: HanlinAgentToolApproval) async -> Bool {
        await request(.init(id: UUID(), tool: approval.request.toolName,
            canonicalRunID: approval.runID, providerCallID: approval.request.toolCallID,
            originalArgumentsJSON: Data(approval.request.argumentsJSON.utf8),
            providerApprovalID: approval.request.approvalID, approvalScope: nil), deadline: approval.deadline)
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

    public func answer(id: UUID, allowed: Bool) {
        guard let pending, pending.id == id else { return }
        let accepted: Bool
        if allowed, let scope = pending.approvalScope {
            accepted = grants.remember(scope, title: pending.tool)
        } else {
            accepted = allowed
        }
        onChange?(pending, accepted)
        let reply = continuation
        deadlineTask?.cancel(); deadlineTask = nil
        self.pending = nil; continuation = nil
        reply?.resume(returning: accepted)
    }

    public func revoke() {
        if let pending { answer(id: pending.id, allowed: false) }
    }
}
