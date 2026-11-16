import Foundation
import Observation
import HanlinHostContracts

/// Live, one-use approval in the original conversation. History never recreates a grant.
@MainActor @Observable
final class HanlinAppToolConsent {
    struct Request: Identifiable {
        let id: UUID
        let tool: String
        let invocation: HanlinHostInvocation
    }
    private(set) var pending: Request?
    @ObservationIgnored private var continuation: CheckedContinuation<Bool, Never>?
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?

    func request(_ invocation: HanlinHostInvocation) async -> Bool {
        guard pending == nil, !Task.isCancelled else { return false }
        let id = UUID()
        let remaining = invocation.request.deadline?.timeIntervalSinceNow ?? 0
        guard remaining > 0 else { return false }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { reply in
                guard !Task.isCancelled else { reply.resume(returning: false); return }
                continuation = reply
                pending = .init(id: id, tool: invocation.request.aliasUsed, invocation: invocation)
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
        let reply = continuation
        deadlineTask?.cancel(); deadlineTask = nil
        pending = nil; continuation = nil
        reply?.resume(returning: allowed)
    }

    func revoke() {
        if let pending { answer(id: pending.id, allowed: false) }
    }
}
