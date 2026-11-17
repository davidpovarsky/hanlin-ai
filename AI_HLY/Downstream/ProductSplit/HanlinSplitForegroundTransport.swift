import Foundation
import HanlinProductSplit
import UIKit

/// Implement in the existing AI Session/conversation owner, not a second store.
/// Cold return may display a historical receipt; it never restores old grants.
@MainActor
protocol HanlinSplitOriginalOrigin {
    /// Resolve the original existing conversation/session, live target metadata
    /// and current Host/OS authority. Never substitute the selected conversation.
    func currentContext(for request: SplitBridgeRequest) async throws -> SplitReceiverContext

    /// Persist into the original canonical conversation/Host receipt path. MUST
    /// be idempotent by full request+origin: mailbox commit can fail after this save.
    func persistVerifiedResult(_ response: SplitBridgeReturn) async throws

    /// Called only after the receipt and mailbox acceptance commit. Navigate by
    /// the immutable origin; a deleted origin shows unavailable, never a new chat.
    func navigateToOriginalConversation(_ request: SplitBridgeRequest)
}

/// Leaf lifecycle seam. Production callers use the OS-resolved group and opener;
/// owned tests inject the same adapter over a temporary group and a fake OS result.
@MainActor
struct HanlinSplitForegroundTransport {
    private let mailbox: HanlinSplitMailbox
    private let openURL: @MainActor (URL) async -> Bool

    init() throws {
        mailbox = try HanlinSplitMailbox()
        openURL = { url in
            await withCheckedContinuation { continuation in
                UIApplication.shared.open(url, options: [:]) { continuation.resume(returning: $0) }
            }
        }
    }

    init(mailbox: HanlinSplitMailbox, openURL: @escaping @MainActor (URL) async -> Bool) {
        self.mailbox = mailbox
        self.openURL = openURL
    }

    /// Open success means dispatch only. The trusted origin supplies authority;
    /// native product URLs do not become logical canonical MiniApp callers.
    func dispatch(_ request: SplitBridgeRequest, origin: any HanlinSplitOriginalOrigin) async throws {
        let context = try await origin.currentContext(for: request)
        try context.validate(request)
        guard request.caller.rawValue == "hanlin.host" else { throw SplitBridgeFailure.denied }
        guard context.online else { throw SplitBridgeFailure.offline }
        let target = try mailbox.registration(for: request.target)
        _ = try request.launchPlan(descriptor: target.descriptor, installedPackageID: target.installedPackage,
                                   currentGeneration: target.generation)
        try mailbox.prepareDispatch(request, now: .now, currentGeneration: context.generation,
            authorized: context.authorized, routeAvailable: context.routeAvailable, handlerAvailable: true)
        guard await openURL(SplitForegroundRoute.openMiniApps.url(reference: request.id)) else {
            try mailbox.finishDispatchFailure(request.id, reason: .companionMissing)
            throw SplitBridgeFailure.companionMissing
        }
    }

    /// The existing origin owner must call this when its account/session/run is
    /// cancelled or invalidated. It revokes pending delivery, never grants access.
    func invalidate(_ reference: UUID) throws {
        try mailbox.cancelDispatch(reference)
    }

    func receiveReturn(_ url: URL, origin: any HanlinSplitOriginalOrigin) async throws {
        let reference = try SplitForegroundRoute.returnToAI.reference(in: url)
        let request = try mailbox.original(reference)
        let before = try await origin.currentContext(for: request)
        let response = try mailbox.previewCompleted(reference, context: before, now: .now)
        try await origin.persistVerifiedResult(response)
        // Recheck after the existing conversation save; cancellation/account or
        // session changes during that await must not inherit the prior context.
        let current = try await origin.currentContext(for: request)
        let accepted = try mailbox.acceptCompleted(reference, context: current, now: .now)
        origin.navigateToOriginalConversation(accepted.request)
    }
}
