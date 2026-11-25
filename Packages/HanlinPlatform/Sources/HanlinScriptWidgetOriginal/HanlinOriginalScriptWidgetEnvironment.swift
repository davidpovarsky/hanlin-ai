import Foundation
import HanlinExtensionContracts

/// Process-bundle configuration, shared by the app and its own extension targets.
/// Original providers receive the product namespace, never ScriptWidget's app group.
enum HanlinOriginalScriptWidgetEnvironment {
    static var resourceBundle: Bundle { .module }
    static var isExtension: Bool { Bundle.main.bundleURL.pathExtension == "appex" }
    static var preferencesSuite: String {
        guard let configuration = try? HanlinExtensionHostConfiguration.load(),
              let group = configuration.appGroupIdentifier else {
            return "com.hanlin.scriptwidget.unconfigured"
        }
        return group + ".ScriptWidgetOriginal." + (configuration.storageNamespace ?? "HanlinAI")
            .replacingOccurrences(of: "/", with: ".")
    }
    static var containerURL: URL? {
        guard let configuration = try? HanlinExtensionHostConfiguration.load(),
              let group = configuration.appGroupIdentifier,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group),
              let product = try? configuration.storageContainer(in: container, createIfNeeded: true) else { return nil }
        let root = product.appendingPathComponent("ScriptingExtensions/ScriptWidgetOriginal/v1", isDirectory: true)
        do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); return root }
        catch { return nil }
    }
    static var ubiquityContainerURL: URL? {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "HanlinScriptWidgetICloudContainerIdentifier") as? String,
              !identifier.isEmpty,
              let root = FileManager.default.url(forUbiquityContainerIdentifier: identifier) else { return nil }
        let configuration = try? HanlinExtensionHostConfiguration.load()
        let product = configuration?.storageNamespace ?? "HanlinAI"
        return root.appendingPathComponent(product, isDirectory: true)
            .appendingPathComponent("ScriptWidgetOriginal", isDirectory: true)
    }
}
