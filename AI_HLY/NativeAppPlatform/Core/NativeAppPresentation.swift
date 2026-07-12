import Foundation

enum NativeAppPresentationStyle: String, Hashable, Codable {
    case fullScreen
    case largeSheet
    case newWindow
}

struct NativeAppLaunchRequest: Identifiable, Hashable, Codable {
    let id: UUID
    let appID: String
    let presentationStyle: NativeAppPresentationStyle
    let initialRoute: NativeAppRoute?

    init(
        id: UUID = UUID(),
        appID: String,
        presentationStyle: NativeAppPresentationStyle,
        initialRoute: NativeAppRoute? = nil
    ) {
        self.id = id
        self.appID = appID
        self.presentationStyle = presentationStyle
        self.initialRoute = initialRoute
    }
}
