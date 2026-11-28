import HanlinTextStudioMiniApp
import SwiftUI

@MainActor
enum NativeAppTextStudioExports {
    static func service() -> NativeAppTextStudioService { NativeAppTextStudioService() }

    static func rootView(context: NativeAppContext) -> AnyView {
        let route = context.initialRoute?.appID == NativeAppTextStudioIndex.id ? context.initialRoute : nil
        let text = route?.payload.string("text")
        let transform = route?.payload.string("transform").flatMap(NativeAppTextStudioTransform.init(rawValue:))
        let screen = route?.screen

        return AnyView(
            NativeAppTextStudioRootView(
                service: service(),
                storage: context.platform.storage,
                pasteboard: context.platform.pasteboard,
                initialText: text,
                initialTransform: transform,
                initialScreen: screen
            )
        )
    }

    static func assistantTools(context: NativeAppContext) -> [NativeTool] {
        [
            NativeAppTextStudioAnalyzeTool(service: service()),
            NativeAppTextStudioTransformTool(service: service())
        ]
    }
}

extension NativeAppStorageBroker: TextStudioStorage {
    func setPersistentString(_ value: String, forKey key: String) {
        setPersistentString(Optional(value), forKey: key)
    }
    func setPersistentData(_ value: Data, forKey key: String) {
        setPersistentData(Optional(value), forKey: key)
    }
}

extension NativeAppPasteboardBroker: TextStudioPasteboard {}
