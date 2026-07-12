import Foundation

@MainActor
struct NativeAppRouter {
    func launchRequest(
        appID: String,
        presentationStyle: NativeAppPresentationStyle,
        route: NativeAppRoute? = nil
    ) -> NativeAppLaunchRequest {
        NativeAppLaunchRequest(appID: appID, presentationStyle: presentationStyle, initialRoute: route)
    }

    func launchRequest(
        route: NativeAppRoute,
        presentationStyle: NativeAppPresentationStyle
    ) -> NativeAppLaunchRequest {
        launchRequest(appID: route.appID, presentationStyle: presentationStyle, route: route)
    }
}
