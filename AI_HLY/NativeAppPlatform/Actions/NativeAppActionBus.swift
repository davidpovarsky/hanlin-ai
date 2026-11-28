import Foundation

enum NativeAppActionResult: Hashable {
    case completed
    case launchRequested(NativeAppLaunchRequest)
    case denied(String)
    case unsupported(String)
    case failed(String)
}

@MainActor
struct NativeAppActionBus {
    let router: NativeAppRouter
    let storage: NativeAppStorageBroker
    let pasteboard: NativeAppPasteboardBroker
    let openURL: NativeAppOpenURLBroker
    let network: NativeAppNetworkBroker
    let capabilityRegistry: NativeCapabilityRegistry

    // Built-in/user-initiated low-risk actions execute here. Stricter policy for
    // model, script, permission, and destructive origins is a later platform step.
    func perform(_ action: NativeAppAction) async -> NativeAppActionResult {
        switch action.kind {
        case .openApp:
            guard let appID = action.appID else { return .failed("Missing appID.") }
            return .launchRequested(router.launchRequest(appID: appID, presentationStyle: action.presentationStyle ?? .fullScreen, route: action.route))
        case .openAppRoute:
            guard let route = action.route else { return .failed("Missing route.") }
            return .launchRequested(router.launchRequest(route: route, presentationStyle: action.presentationStyle ?? .fullScreen))
        case .copyText:
            guard let text = action.text else { return .failed("Missing text.") }
            pasteboard.writeString(text); return .completed
        case .pasteText:
            return .completed
        case .openURL:
            guard let urlString = action.urlString else { return .failed("Missing URL.") }
            openURL.open(urlString); return .completed
        case .saveItem:
            guard let key = action.payload["key"], let value = action.text else { return .failed("Missing save key or value.") }
            storage.setPersistentString(value, forKey: key); return .completed
        case .clearAppData:
            storage.clearPersistentAppData(); return .completed
        case .clearAppCache:
            storage.clearCache(); return .completed
        case .resetApp:
            storage.clearPersistentAppData(); storage.clearCache(); return .completed
        case .returnResultToChat, .share, .requestPermission, .runAssistantTool:
            return .unsupported("\(action.kind.rawValue) is not implemented in this foundation step.")
        }
    }
}
