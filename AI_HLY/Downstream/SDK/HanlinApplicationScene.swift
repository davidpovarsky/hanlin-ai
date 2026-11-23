import SwiftData
import SwiftUI
import TorahLibraryKit

/// The original Hanlin application scenes, including window-scoped returns,
/// study deep links, and the original Mini App window. Hosts may instead embed
/// HanlinConversationView or HanlinWorkspaceView in their existing scenes.
@MainActor
public struct HanlinApplicationScene: Scene {
    private let context: HanlinApplicationContext

    public init(context: HanlinApplicationContext) {
        self.context = context
    }
    @State private var deepLinkTarget: String? = nil
    @Environment(\.scenePhase) private var scenePhase

    public var body: some Scene {
        WindowGroup {
            HanlinAIReceivingWindowRoot(onDisappear: { windowID in
                HanlinAppSplitOriginCoordinator.shared.revokeReceivingWindow(windowID)
            }) { receivingWindowID in
            MainTabView(deepLinkTarget: $deepLinkTarget)
                .modelContainer(context.modelContainer)
                .task {
                    await context.prepareApplication()
                    await context.handleScenePhase(scenePhase)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    Task { await context.handleScenePhase(newPhase) }
                }
                .onOpenURL { url in
                    if url.scheme?.lowercased() == "chavrusachat", url.host?.lowercased() == "split" {
                        let receiver = HanlinAppSplitOriginCoordinator.shared
                        if let claimID = receiver.claimReturn(url, receivingWindowID: receivingWindowID) {
                            Task { @MainActor in
                                await receiver.receiveReturn(url, modelContext: context.modelContainer.mainContext,
                                    receivingWindowID: receivingWindowID, claimID: claimID)
                            }
                        }
                    } else if url.host == "openVisionView" {
                        deepLinkTarget = "vision"
                    } else if url.host == "study", let link = TorahStudyDeepLink.parse(url: url) {
                        TorahStudyNavigationRouter.shared.navigate(to: link)
                        NotificationCenter.default.post(
                            name: Notification.Name("TorahStudyDeepLinkNotification"),
                            object: link
                        )
                    }
                }
            }
        }

        WindowGroup("Mini App", for: NativeAppLaunchRequest.self) { $request in
            if let request {
                NativeAppSessionContainerView(request: request)
                    .modelContainer(context.modelContainer)
            } else {
                ContentUnavailableView(
                    "No App Selected",
                    systemImage: "square.grid.2x2",
                    description: Text("Choose a mini app from Hanlin.")
                )
                .modelContainer(context.modelContainer)
            }
        }
    }
}
