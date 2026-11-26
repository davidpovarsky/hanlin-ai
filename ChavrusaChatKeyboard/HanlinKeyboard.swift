import HanlinExtensionContracts
import HanlinKeyboardUI

@MainActor
final class HanlinKeyboard: HanlinKeyboardInputViewController {
    override var hostConfiguration: HanlinExtensionHostConfiguration { .hanlin }
}
