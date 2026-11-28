import Foundation

public enum NativeAppPresentationStyle: String, Hashable, Codable, Sendable {
    case fullScreen
    case largeSheet
    case newWindow
}

public struct NativeAppLaunchRequest: Identifiable, Hashable, Codable, Sendable {
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
