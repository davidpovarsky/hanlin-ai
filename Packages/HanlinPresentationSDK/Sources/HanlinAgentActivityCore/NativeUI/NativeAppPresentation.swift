import Foundation

public enum NativeAppPresentationStyle: String, Hashable, Codable {
    case fullScreen
    case largeSheet
    case newWindow
}

public struct NativeAppLaunchRequest: Identifiable, Hashable, Codable {
    public let id: UUID
    public let appID: String
    public let presentationStyle: NativeAppPresentationStyle
    public let initialRoute: NativeAppRoute?

    public init(
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
