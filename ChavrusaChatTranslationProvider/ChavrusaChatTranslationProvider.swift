import AppIntents
import HanlinExtensionContracts
import HanlinScriptExtensions
import HanlinTranslationUI
import SwiftUI
@preconcurrency import Translation
@preconcurrency import TranslationUIProvider

@main
final class ChavrusaChatTranslationProvider: TranslationUIProviderExtension {
    // The host alone owns its Keychain service/access-group policy.
    nonisolated private static let providerKeychain = HanlinKeychainCredentialStore(
        service: "com.itorah.chavrusachat.provider-credentials",
        accessGroup: HanlinExtensionHostConfiguration.hanlin.appGroupIdentifier,
        synchronizable: true,
        accessibility: .afterFirstUnlock
    )
    private static let services = HanlinTranslationHostServices(configuration: .hanlin,
        credentialResolver: { reference in
            guard let secret = try providerKeychain.resolve(reference, kind: .model) else {
                throw HanlinCompactAgentError.notConfigured
            }
            return secret
        })

    var body: some TranslationUIProviderExtensionScene {
        TranslationUIProviderSelectedTextScene { context in
            TranslationProviderRootView(context: context, services: Self.services)
        }
    }
}

struct HanlinTranslationIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [HanlinScriptExtensionIntentsPackage.self]
    }
}
