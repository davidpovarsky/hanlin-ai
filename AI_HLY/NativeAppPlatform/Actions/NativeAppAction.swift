import Foundation

enum NativeAppActionOrigin: String, Codable, Hashable {
    case userInterface, assistantTool, modelSuggested, automation, runtimeScript
}

enum NativeAppActionRisk: String, Codable, Hashable { case low, medium, high }

enum NativeAppActionKind: String, Codable, Hashable {
    case openApp, openAppRoute, openURL, copyText, pasteText, saveItem
    case clearAppData, clearAppCache, resetApp, returnResultToChat, share
    case requestPermission, runAssistantTool
}

struct NativeAppAction: Identifiable, Codable, Hashable {
    let id: UUID
    var kind: NativeAppActionKind
    var origin: NativeAppActionOrigin
    var risk: NativeAppActionRisk
    var title: String
    var systemImage: String?
    var appID: String?
    var route: NativeAppRoute?
    var presentationStyle: NativeAppPresentationStyle?
    var urlString: String?
    var text: String?
    var payload: [String: String]
    var requiresUserGesture: Bool

    init(
        id: UUID = UUID(), kind: NativeAppActionKind,
        origin: NativeAppActionOrigin = .userInterface,
        risk: NativeAppActionRisk = .low, title: String,
        systemImage: String? = nil, appID: String? = nil,
        route: NativeAppRoute? = nil,
        presentationStyle: NativeAppPresentationStyle? = nil,
        urlString: String? = nil, text: String? = nil,
        payload: [String: String] = [:], requiresUserGesture: Bool = false
    ) {
        self.id = id; self.kind = kind; self.origin = origin; self.risk = risk
        self.title = title; self.systemImage = systemImage; self.appID = appID
        self.route = route; self.presentationStyle = presentationStyle
        self.urlString = urlString; self.text = text; self.payload = payload
        self.requiresUserGesture = requiresUserGesture
    }
}

extension NativeAppAction {
    static func openAppRoute(
        _ route: NativeAppRoute, title: String,
        systemImage: String? = "arrow.up.forward.app",
        presentationStyle: NativeAppPresentationStyle = .fullScreen,
        origin: NativeAppActionOrigin = .userInterface
    ) -> NativeAppAction {
        NativeAppAction(kind: .openAppRoute, origin: origin, title: title, systemImage: systemImage,
                        appID: route.appID, route: route, presentationStyle: presentationStyle)
    }

    static func copyText(
        _ text: String, title: String = "Copy", systemImage: String? = "doc.on.doc",
        origin: NativeAppActionOrigin = .userInterface
    ) -> NativeAppAction {
        NativeAppAction(kind: .copyText, origin: origin, title: title, systemImage: systemImage, text: text)
    }

    static func openURL(
        _ urlString: String, title: String = "Open", systemImage: String? = "safari",
        origin: NativeAppActionOrigin = .userInterface
    ) -> NativeAppAction {
        NativeAppAction(kind: .openURL, origin: origin, risk: .medium, title: title,
                        systemImage: systemImage, urlString: urlString,
                        requiresUserGesture: origin != .userInterface)
    }
}
