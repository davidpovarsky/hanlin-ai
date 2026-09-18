import Foundation
import ExpoBrownfield
import ExpoModulesCore
import ExpoUI
import React
import React_RCTAppDelegate
import UIKit

@_silgen_name("jsrt_create_hermes_factory")
private func hanlin_create_hermes_factory() -> JSRuntimeFactoryRef

private final class HanlinExpoJSRuntimeConfigurator: NSObject, RCTJSRuntimeConfiguratorProtocol {
    func createJSRuntimeFactory() -> JSRuntimeFactoryRef {
        return hanlin_create_hermes_factory()
    }
}

@objc(ExpoModulesProvider)
public final class HanlinExpoModulesProvider: ModulesProvider {
    public override func getModuleClasses() -> [ExpoModuleTupleType] {
        return [
            (module: ExpoUIModule.self, name: "ExpoUI"),
            (module: ExpoBrownfieldModule.self, name: "ExpoBrownfieldModule"),
            (module: ExpoBrownfieldStateModule.self, name: "ExpoBrownfieldStateModule")
        ]
    }
}

@MainActor
public final class HanlinExpoSession {
    private static let supportedSDKVersion = "58.0.3"
    private static let supportedUIVersion = "58.0.3"
    private static weak var activeSession: HanlinExpoSession?

    public let applicationRoot: URL
    public let containerController: UIViewController
    public let bundleURL: URL

    private var rootViewFactory: RCTRootViewFactory?
    private var runtimeConfigurator: HanlinExpoJSRuntimeConfigurator?
    private var appContext: AppContext?
    private var hostedView: UIView?
    private(set) public var isActive = false

    public init(applicationRoot: URL) throws {
        let root = applicationRoot.standardizedFileURL
        guard root.isFileURL else {
            throw HanlinExpoError.invalidApplicationRoot("the URL is not a file URL")
        }
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw HanlinExpoError.invalidApplicationRoot("the root is not a real directory")
        }

        let packageJSONURL = root.appending(path: "package.json", directoryHint: .notDirectory)
        guard FileManager.default.fileExists(atPath: packageJSONURL.path(percentEncoded: false)) else {
            throw HanlinExpoError.missingPreparedFile("package.json")
        }

        let packageData = try Data(contentsOf: packageJSONURL)
        guard let packageJSON = try JSONSerialization.jsonObject(with: packageData) as? [String: Any] else {
            throw HanlinExpoError.invalidApplicationRoot("package.json is not a valid JSON object")
        }

        guard packageJSON["hanlinRuntime"] as? String == "hanlin-expo" else {
            throw HanlinExpoError.unsupportedRuntimeVersion("package.json does not declare hanlinRuntime: hanlin-expo")
        }

        let entryFileName = (packageJSON["main"] as? String) ?? "bundle.js"
        let resolvedBundleURL = root.appending(path: entryFileName, directoryHint: .notDirectory)
        guard FileManager.default.fileExists(atPath: resolvedBundleURL.path(percentEncoded: false)) else {
            throw HanlinExpoError.missingPreparedFile(entryFileName)
        }

        self.applicationRoot = root
        self.bundleURL = resolvedBundleURL
        self.containerController = UIViewController()
        self.containerController.view.backgroundColor = .systemBackground
    }

    public func start(moduleName: String = "main") throws {
        guard !isActive else { return }
        guard Self.activeSession == nil else {
            throw HanlinExpoError.sessionAlreadyActive
        }

        do {
            HanlinExpoModifierRegistry.registerCustomModifiers()

            let modulesProvider = HanlinExpoModulesProvider()
            let appContext = AppContext()
            appContext.registerNativeModules(provider: modulesProvider)
            self.appContext = appContext

            let bundle = bundleURL
            let configurator = HanlinExpoJSRuntimeConfigurator()
            self.runtimeConfigurator = configurator

            let config = RCTRootViewFactoryConfiguration(
                bundleURL: bundle,
                newArchEnabled: true
            )
            config.bundleURLBlock = { bundle }
            config.jsRuntimeConfiguratorDelegate = configurator

            let factory = RCTRootViewFactory(configuration: config)
            self.rootViewFactory = factory

            let rootView = factory.view(
                withModuleName: moduleName,
                initialProperties: nil,
                launchOptions: nil
            )

            rootView.translatesAutoresizingMaskIntoConstraints = false
            containerController.view.addSubview(rootView)
            NSLayoutConstraint.activate([
                rootView.topAnchor.constraint(equalTo: containerController.view.topAnchor),
                rootView.leadingAnchor.constraint(equalTo: containerController.view.leadingAnchor),
                rootView.trailingAnchor.constraint(equalTo: containerController.view.trailingAnchor),
                rootView.bottomAnchor.constraint(equalTo: containerController.view.bottomAnchor)
            ])

            self.hostedView = rootView
            Self.activeSession = self
            isActive = true

            NSLog("%@", "HANLIN_EXPO_INITIALIZED_EXTERNAL_ROOT path=\(applicationRoot.path(percentEncoded: false)) bundle=\(bundleURL.lastPathComponent)")
        } catch {
            shutdown()
            throw HanlinExpoError.bootstrapFailed(error.localizedDescription)
        }
    }

    public func shutdown() {
        guard isActive || rootViewFactory != nil else {
            HanlinExpoModifierRegistry.unregisterCustomModifiers()
            return
        }

        hostedView?.removeFromSuperview()
        hostedView = nil

        if let factory = rootViewFactory {
            factory.reactHost = nil
            factory.setValue(nil, forKey: "_reactHost")
        }
        rootViewFactory = nil
        appContext?.destroy()
        appContext = nil
        runtimeConfigurator = nil
        isActive = false

        HanlinExpoModifierRegistry.unregisterCustomModifiers()

        if Self.activeSession === self {
            Self.activeSession = nil
        }
    }

    deinit {
        MainActor.assumeIsolated {
            shutdown()
        }
    }
}
