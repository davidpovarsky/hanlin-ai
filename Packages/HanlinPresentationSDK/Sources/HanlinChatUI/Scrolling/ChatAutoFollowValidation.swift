import Foundation

public enum ChatAutoFollowValidation {
    @MainActor
    public static func initialModeIsFollowing() -> Bool {
        ChatAutoFollowController().mode == .following
    }

    @MainActor
    public static func userDragAwayPausesFollowing() -> Bool {
        let controller = ChatAutoFollowController()
        controller.updateNearBottom(false)
        controller.userInteractionBegan()
        controller.userInteractionEnded()
        return controller.mode == .pausedByUser
            && !controller.shouldRequestScrollForVisualUpdate()
    }

    @MainActor
    public static func bottomButtonResumesFollowing() -> Bool {
        let controller = ChatAutoFollowController()
        controller.updateNearBottom(false)
        controller.userInteractionBegan()
        controller.userInteractionEnded()
        controller.resumeFollowing()
        return controller.mode == .following
            && controller.shouldRequestScrollForVisualUpdate()
    }
}
