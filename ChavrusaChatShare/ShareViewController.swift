import HanlinExtensionContracts
import HanlinShareExtensionUI

/// The OS principal class owns only this app's entitlement policy.
final class ShareViewController: HanlinShareViewController {
    override var hostConfiguration: HanlinExtensionHostConfiguration { .hanlin }
}
