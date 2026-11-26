import HanlinExtensionContracts
import HanlinKeyboardUI

@MainActor
final class HanlinMiniAppsKeyboard: HanlinKeyboardInputViewController {
    override var hostConfiguration: HanlinExtensionHostConfiguration { .miniapps }
}
