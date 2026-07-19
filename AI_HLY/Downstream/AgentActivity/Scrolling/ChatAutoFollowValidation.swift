import Foundation

enum ChatAutoFollowValidation {
    @MainActor
    static func initialModeIsFollowing() -> Bool {
        ChatAutoFollowController().mode == .following
    }

    @MainActor
    static func userDragAwayPausesFollowing() -> Bool {
        let controller = ChatAutoFollowController()
        controller.updateNearBottom(false)
        controller.userInteractionBegan()
        controller.userInteractionEnded()
        return controller.mode == .pausedByUser
            && !controller.shouldRequestScrollForVisualUpdate()
    }

    @MainActor
    static func bottomButtonResumesFollowing() -> Bool {
        let controller = ChatAutoFollowController()
        controller.updateNearBottom(false)
        controller.userInteractionBegan()
        controller.userInteractionEnded()
        controller.resumeFollowing()
        return controller.mode == .following
            && controller.shouldRequestScrollForVisualUpdate()
    }
}
